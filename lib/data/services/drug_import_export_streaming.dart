part of 'drug_import_export_service.dart';

/// File imports do not load an entire CSV/JSON payload into a TextField or List.
/// Rows are decoded incrementally and transactions contain at most [batchSize].
extension DrugImportFileStreaming on DrugImportExportService {
  Stream<_DrugFileRow> _fileRows(File file, String format) async* {
    if (format.toUpperCase() == 'JSON') {
      final parser = _DrugJsonArrayReader();
      var rowNumber = 1;
      await for (final chunk in file.openRead().transform(utf8.decoder)) {
        for (final row in parser.add(chunk)) {
          yield _DrugFileRow(++rowNumber, row);
        }
      }
      parser.finish();
      return;
    }
    if (format.toUpperCase() != 'CSV') {
      throw const FormatException('صيغة الملف يجب أن تكون CSV أو JSON');
    }
    final parser = _DrugCsvRecordReader();
    List<String>? headers;
    var rowNumber = 0;
    await for (final chunk in file.openRead().transform(utf8.decoder)) {
      for (final line in parser.add(chunk)) {
        if (line.trim().isEmpty) continue;
        rowNumber++;
        final rows = const CsvToListConverter(shouldParseNumbers: false)
            .convert(line);
        if (rows.length != 1) {
          throw FormatException('صف CSV غير صالح: ' + rowNumber.toString());
        }
        final values = rows.single.map((value) => value.toString()).toList();
        if (headers == null) {
          headers = values
              .map((value) => value.replaceFirst('\uFEFF', '').trim())
              .toList();
          continue;
        }
        final result = <String, Object?>{};
        for (var i = 0; i < headers.length && i < values.length; i++) {
          result[headers[i]] = values[i];
        }
        yield _DrugFileRow(rowNumber, result);
      }
    }
    for (final line in parser.finish()) {
      if (line.trim().isEmpty) continue;
      rowNumber++;
      final rows = const CsvToListConverter(shouldParseNumbers: false)
          .convert(line);
      if (rows.length != 1) {
        throw FormatException('صف CSV غير صالح: ' + rowNumber.toString());
      }
      final values = rows.single.map((value) => value.toString()).toList();
      if (headers == null) {
        headers = values
            .map((value) => value.replaceFirst('\uFEFF', '').trim()).toList();
        continue;
      }
      final result = <String, Object?>{};
      for (var i = 0; i < headers.length && i < values.length; i++) {
        result[headers[i]] = values[i];
      }
      yield _DrugFileRow(rowNumber, result);
    }
  }

  String? _rowProblem(Map<String, Object?> row) {
    final name = (row['trade_name_ar'] ?? row['trade_name_en'] ?? '')
        .toString().trim();
    if (name.isEmpty &&
        (row['scientific_name'] ?? '').toString().trim().isEmpty) {
      return 'الاسم التجاري أو العلمي مطلوب';
    }
    for (final key in ['strips_per_pack', 'units_per_strip', 'units_per_pack']) {
      if (row[key] != null && (row[key] as int) < 1) {
        return 'القيمة يجب أن تكون موجبة: ' + key;
      }
    }
    for (final key in ['stock_total_units', 'min_stock_units',
                       'reorder_qty_packs']) {
      if (row[key] != null && (row[key] as int) < 0) {
        return 'القيمة لا يمكن أن تكون سالبة: ' + key;
      }
    }
    for (final key in ['cost_price_pack', 'last_purchase_cost_pack',
                       'sell_price_pack', 'sell_price_strip',
                       'sell_price_unit', 'public_price_pack']) {
      if (row[key] != null && (row[key] as num) < 0) {
        return 'السعر لا يمكن أن يكون سالباً: ' + key;
      }
    }
    return null;
  }

  String _rowKey(Map<String, Object?> row) {
    final code = (row['internal_code'] ?? '').toString().trim().toLowerCase();
    if (code.isNotEmpty) return 'code:' + code;
    final name = (row['trade_name_ar'] ?? row['trade_name_en'] ?? '')
        .toString().trim().toLowerCase();
    final scientific = (row['scientific_name'] ?? '')
        .toString().trim().toLowerCase();
    return 'name:' + name + '|' + scientific;
  }

  Future<ImportDryRunResult> dryRunImportFile({
    required File file,
    required String format,
    Map<String, String> mapping = const {},
  }) async {
    final errors = <ImportRowIssue>[];
    final seen = <String>{};
    var count = 0, valid = 0, duplicates = 0;
    await for (final item in _fileRows(file, format)) {
      count++;
      try {
        final row = _mapFields(item.values, mapping);
        final problem = _rowProblem(row);
        if (problem != null) {
          errors.add(ImportRowIssue(item.number, problem));
          continue;
        }
        if (!seen.add(_rowKey(row))) {
          duplicates++;
          errors.add(ImportRowIssue(item.number, 'سجل مكرر داخل الملف'));
          continue;
        }
        DrugModel.fromMap(row);
        valid++;
      } catch (e) {
        errors.add(ImportRowIssue(item.number, e.toString()));
      }
    }
    return ImportDryRunResult(totalRows: count, validRows: valid,
        errors: errors, duplicates: duplicates);
  }

  Future<ImportExecutionResult> executeImportFile({
    required File file,
    required String format,
    Map<String, String> mapping = const {},
    String conflictPolicy = 'SKIP',
    String? fileName,
    int branchId = 1,
    int batchSize = 100,
    int expectedRows = 0,
    void Function(int done, int total)? onProgress,
  }) async {
    if (!{'SKIP', 'UPDATE_EMPTY_ONLY', 'OVERWRITE'}.contains(conflictPolicy)) {
      throw ArgumentError('سياسة تعارض غير معروفة');
    }
    if (batchSize < 1 || batchSize > 500) {
      throw ArgumentError('حجم الدفعة يجب أن يكون من 1 إلى 500');
    }
    final db = await _helper.database;
    final jobId = await db.insert('import_jobs', {
      'source_type': format.toUpperCase(),
      'file_name': fileName ?? file.path,
      'mapping_json': jsonEncode(mapping),
      'conflict_policy': conflictPolicy,
      'total_rows': expectedRows,
      'status': 'RUNNING',
      'started_at': DateTime.now().toIso8601String(),
    });
    var inserted = 0, updated = 0, skipped = 0, errors = 0, done = 0;
    final pending = <_DrugFileRow>[];
    final seen = <String>{};

    Future<void> flush() async {
      if (pending.isEmpty) return;
      await db.transaction((txn) async {
        for (final item in pending) {
          done++;
          try {
            final incoming = _mapFields(item.values, mapping);
            if (_rowProblem(incoming) != null || !seen.add(_rowKey(incoming))) {
              errors++;
              continue;
            }
            final name = (incoming['trade_name_ar'] ??
                    incoming['trade_name_en'] ??
                    incoming['scientific_name'] ?? '')
                .toString().trim();
            final scientific = (incoming['scientific_name'] ?? '')
                .toString().trim();
            final barcode = (incoming['barcode_international'] ??
                    incoming['barcode_local'] ?? '')
                .toString().trim();
            final specifiedCode =
                (incoming['internal_code'] ?? '').toString().trim();
            // Stable identifiers make partial imports safe to retry.
            final digest = sha1.convert(utf8.encode(
                '$branchId|$name|$scientific|$barcode'));
            final code = specifiedCode.isEmpty
                ? 'IMP-' + digest.toString().substring(0, 24)
                : specifiedCode;
            final matching = await txn.rawQuery(
              '''SELECT * FROM drugs WHERE is_deleted=0 AND branch_id=? AND
              (internal_code=? OR
              (LOWER(TRIM(trade_name_ar))=? AND
               LOWER(TRIM(COALESCE(scientific_name,'')))=?) OR
              (?<>'' AND (barcode_international=? OR barcode_local=?)))
              LIMIT 2''',
              [branchId, code, name.toLowerCase(), scientific.toLowerCase(),
               barcode, barcode, barcode],
            );
            if (matching.length > 1) {
              errors++;
              continue;
            }
            if (matching.isNotEmpty && conflictPolicy == 'SKIP') {
              skipped++;
              continue;
            }
            final drug = DrugModel.fromMap(incoming).toMap();
            drug.remove('id');
            drug['branch_id'] = branchId;
            drug['internal_code'] = code;
            drug['uuid'] = 'drug-import-' + branchId.toString() +
                '-' + digest.toString();
            drug['trade_name_ar'] = name;
            final dosage = drug['dosage_form']?.toString().toUpperCase();
            const forms = {'TABLET','CAPSULE','SYRUP','SUSPENSION','DROPS',
              'INJECTION','CREAM','OINTMENT','INHALER','SUPPOSITORY',
              'SACHET','OTHER'};
            if (dosage != null && !forms.contains(dosage)) {
              drug['dosage_form'] = 'OTHER';
            }
            final route = drug['route']?.toString().toUpperCase();
            const routes = {'ORAL','IV','IM','SC','TOPICAL','OPHTHALMIC',
              'INHALATION','RECTAL','OTHER'};
            if (route != null && !routes.contains(route)) {
              drug['route'] = 'OTHER';
            }
            final pregnancy = drug['pregnancy_category']?.toString().toUpperCase();
            if (pregnancy != null &&
                !{'A','B','C','D','X','N','UNKNOWN'}.contains(pregnancy)) {
              drug['pregnancy_category'] = 'UNKNOWN';
            }
            final lactation = drug['lactation_risk']?.toString().toUpperCase();
            if (lactation != null &&
                !{'L1','L2','L3','L4','L5','UNKNOWN'}.contains(lactation)) {
              drug['lactation_risk'] = 'UNKNOWN';
            }
            final timestamp = DateTime.now().toIso8601String();
            if (matching.isEmpty) {
              drug['created_at'] = timestamp;
              drug['updated_at'] = timestamp;
              await txn.insert('drugs', drug,
                  conflictAlgorithm: ConflictAlgorithm.abort);
              inserted++;
            } else {
              final old = matching.single;
              final updates = <String, Object?>{};
              // Update explicit import values only, never model defaults.
              const protected = {
                'id','uuid','internal_code','branch_id','created_at',
                'updated_at','sync_status','sync_version','is_deleted',
                'stock_total_units','completeness_pct'
              };
              for (final entry in incoming.entries) {
                if (protected.contains(entry.key) ||
                    !drug.containsKey(entry.key)) continue;
                final previous = old[entry.key];
                if (conflictPolicy == 'OVERWRITE' ||
                    previous == null || previous == '' ||
                    previous == 'UNKNOWN') {
                  updates[entry.key] = drug[entry.key];
                }
              }
              if (updates.isEmpty) {
                skipped++;
              } else {
                updates['updated_at'] = timestamp;
                updates['completeness_pct'] = DrugModel.fromMap(
                    {...old, ...updates}).calculateCompletenessPct();
                await txn.update('drugs', updates,
                    where: 'id=?', whereArgs: [old['id']]);
                updated++;
              }
            }
          } catch (_) {
            errors++;
          }
        }
      });
      pending.clear();
      onProgress?.call(done, expectedRows);
    }

    try {
      await for (final item in _fileRows(file, format)) {
        pending.add(item);
        if (pending.length >= batchSize) await flush();
      }
      await flush();
      await db.update('import_jobs', {
        'total_rows': done,
        'inserted_rows': inserted, 'updated_rows': updated,
        'skipped_rows': skipped, 'error_rows': errors,
        'status': errors == 0 ? 'COMPLETED' : 'COMPLETED_WITH_ERRORS',
        'finished_at': DateTime.now().toIso8601String(),
      }, where: 'id=?', whereArgs: [jobId]);
      await _refreshFts(db);
      await AuditService(helper: _helper).record(
        action: 'CREATE', entityType: 'drugs', entityId: jobId,
        entityLabel: 'Import job #' + jobId.toString(),
        newValues: {'inserted': inserted, 'updated': updated,
                    'skipped': skipped, 'errors': errors},
        severity: errors == 0 ? 'INFO' : 'WARNING',
      );
      return ImportExecutionResult(jobId: jobId, inserted: inserted,
          updated: updated, skipped: skipped, errors: errors);
    } catch (_) {
      await db.update('import_jobs', {
        'total_rows': done,
        'inserted_rows': inserted, 'updated_rows': updated,
        'skipped_rows': skipped, 'error_rows': errors + 1,
        'status': 'FAILED',
        'finished_at': DateTime.now().toIso8601String(),
      }, where: 'id=?', whereArgs: [jobId]);
      rethrow;
    }
  }
}

class _DrugFileRow {
  const _DrugFileRow(this.number, this.values);
  final int number;
  final Map<String, Object?> values;
}

/// Splits a large JSON array into objects, with a 4 MiB per-record bound.
class _DrugJsonArrayReader {
  bool _started = false, _wrapped = false, _inArray = false, _done = false;
  bool _wrapperClosed = false, _capturing = false;
  bool _quoted = false, _escaped = false, _needSeparator = false;
  bool _afterComma = false;
  int _depth = 0, _recordSize = 0;
  StringBuffer _prefix = StringBuffer(), _object = StringBuffer();
  static final _drugsPrefix = RegExp(r'"drugs"\s*:\s*\[$');

  List<Map<String, Object?>> add(String chunk) {
    final output = <Map<String, Object?>>[];
    for (var i = 0; i < chunk.length; i++) {
      final c = chunk[i];
      if (!_started) {
        if (c.trim().isEmpty || c == '\uFEFF') continue;
        if (c == '[') {
          _started = true;
          _inArray = true;
          continue;
        }
        if (c != '{') {
          throw const FormatException('يجب أن يبدأ JSON بمصفوفة أدوية');
        }
        _started = true;
        _wrapped = true;
        _prefix.write(c);
        continue;
      }
      if (!_inArray) {
        _prefix.write(c);
        if (c == '[' && _drugsPrefix.hasMatch(_prefix.toString())) {
          _inArray = true;
          _prefix = StringBuffer();
        } else if (_prefix.length > 65536) {
          throw const FormatException('لم يتم العثور على drugs داخل JSON');
        }
        continue;
      }
      if (_done) {
        if (c.trim().isEmpty) continue;
        if (_wrapped && c == '}' && !_wrapperClosed) {
          _wrapperClosed = true;
          continue;
        }
        throw const FormatException('بيانات زائدة بعد مصفوفة الأدوية');
      }
      if (_capturing) {
        _object.write(c);
        if (++_recordSize > 4 * 1024 * 1024) {
          throw const FormatException('سجل JSON كبير جداً');
        }
        if (_escaped) {
          _escaped = false;
        } else if (_quoted && c == '\\') {
          _escaped = true;
        } else if (c == '"') {
          _quoted = !_quoted;
        } else if (!_quoted) {
          if (c == '{') _depth++;
          if (c == '}' && --_depth == 0) {
            final decoded = jsonDecode(_object.toString());
            if (decoded is! Map) {
              throw const FormatException('السجل ليس كائناً JSON');
            }
            output.add(Map<String, Object?>.from(decoded));
            _object = StringBuffer();
            _capturing = false;
            _needSeparator = true;
            _afterComma = false;
          }
        }
        continue;
      }
      if (c.trim().isEmpty) continue;
      if (_needSeparator) {
        if (c == ',') {
          _needSeparator = false;
          _afterComma = true;
          continue;
        }
        if (c == ']') {
          _done = true;
          continue;
        }
        throw const FormatException('فاصل JSON غير صالح');
      }
      if (c == ']' && !_afterComma) {
        _done = true;
        continue;
      }
      if (c != '{') {
        throw const FormatException('كل عنصر يجب أن يكون كائناً JSON');
      }
      _capturing = true;
      _depth = 1;
      _quoted = false;
      _escaped = false;
      _recordSize = 1;
      _object.write(c);
    }
    return output;
  }

  void finish() {
    if (!_done || _capturing || (_wrapped && !_wrapperClosed)) {
      throw const FormatException('ملف JSON غير مكتمل أو غير صالح');
    }
  }
}

class _DrugCsvRecordReader {
  StringBuffer _record = StringBuffer();
  bool _quoted = false;
  int _length = 0;
  List<String> add(String chunk) {
    final records = <String>[];
    for (var i = 0; i < chunk.length; i++) {
      final c = chunk[i];
      if (c == '"') _quoted = !_quoted;
      if (c == '\n' && !_quoted) {
        final record = _record.toString();
        records.add(record.endsWith('\r')
            ? record.substring(0, record.length - 1) : record);
        _record = StringBuffer();
        _length = 0;
      } else {
        _record.write(c);
        if (++_length > 4 * 1024 * 1024) {
          throw const FormatException('صف CSV كبير جداً');
        }
      }
    }
    return records;
  }

  List<String> finish() {
    if (_quoted) throw const FormatException('علامة اقتباس غير مغلقة في CSV');
    return _length == 0 ? const [] : [_record.toString()];
  }
}
