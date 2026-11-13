import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';

/// Existing database terminology: PACK = carton/outer pack,
/// STRIP = packet/strip, UNIT = individual tablet/item.
/// No separate inventory stock table or shadow drug catalog is used.
class OpeningStockPrices {
  const OpeningStockPrices({this.carton, this.packet, this.unit});
  final double? carton;
  final double? packet;
  final double? unit;

  // Only automatically calculated prices are rounded upward to a full 10.
  // Explicitly entered carton/packet/unit prices always remain unchanged.
  static double _rounded(double value) => (value / 10).ceil() * 10.0;

  OpeningStockPrices fillMissing(int packetsPerCarton, int unitsPerPacket) {
    if (packetsPerCarton <= 0 || unitsPerPacket <= 0) {
      throw ArgumentError('يجب تحديد وحدات التعبئة بأعداد موجبة');
    }
    for (final price in [carton, packet, unit]) {
      if (price != null && (!price.isFinite || price < 0)) {
        throw ArgumentError('سعر البيع غير صالح');
      }
    }
    if (carton == null && packet == null && unit == null) return this;
    final calculatedCarton = carton ??
        _rounded((packet ?? unit! * unitsPerPacket) * packetsPerCarton);
    final calculatedPacket = packet ??
        _rounded(carton != null
            ? carton! / packetsPerCarton
            : unit! * unitsPerPacket);
    final calculatedUnit = unit ??
        _rounded(packet != null
            ? packet! / unitsPerPacket
            : carton! / (packetsPerCarton * unitsPerPacket));
    return OpeningStockPrices(
        carton: calculatedCarton,
        packet: calculatedPacket,
        unit: calculatedUnit);
  }
}

class OpeningStockLine {
  const OpeningStockLine({
    this.drugId,
    this.drugName = '',
    this.dosageForm,
    required this.warehouseId,
    this.shelfCode,
    this.batchNo = '',
    required this.expiryDate,
    this.effectiveDate,
    this.cartons = 0,
    this.packets = 0,
    this.units = 0,
    required this.packetsPerCarton,
    required this.unitsPerPacket,
    this.resolveUnitsFromCatalog = false,
    this.prices = const OpeningStockPrices(),
    this.unitCost = 0,
    this.note = '',
  });

  final int? drugId;
  final String drugName;
  final String? dosageForm;
  final int warehouseId;
  final String? shelfCode;
  final String batchNo;
  final String expiryDate;
  final String? effectiveDate;
  final int cartons, packets, units, packetsPerCarton, unitsPerPacket;

  /// Four-column Excel omits tablet count per strip. Resolve from the
  /// medicine's saved packaging rather than assuming it is one.
  final bool resolveUnitsFromCatalog;
  final OpeningStockPrices prices;
  final double unitCost;
  final String note;

  int get quantityUnits =>
      cartons * packetsPerCarton * unitsPerPacket +
      packets * unitsPerPacket +
      units;

  OpeningStockLine withUnitsPerPacket(int resolved) => OpeningStockLine(
        drugId: drugId,
        drugName: drugName,
        dosageForm: dosageForm,
        warehouseId: warehouseId,
        shelfCode: shelfCode,
        batchNo: batchNo,
        expiryDate: expiryDate,
        effectiveDate: effectiveDate,
        cartons: cartons,
        packets: packets,
        units: units,
        packetsPerCarton: packetsPerCarton,
        unitsPerPacket: resolved,
        prices: prices,
        unitCost: unitCost,
        note: note,
      );
}

class OpeningStockPreview {
  const OpeningStockPreview(this.totalUnits, this.errors);
  final int totalUnits;
  final List<String> errors;
  bool get isValid => errors.isEmpty;
}

class _Prepared {
  const _Prepared({
    required this.row,
    required this.drugId,
    required this.drug,
    required this.qty,
    required this.shelfId,
    required this.prices,
    required this.effectiveDate,
  });
  final OpeningStockLine row;
  final int drugId, qty;
  final Map<String, Object?> drug;
  final int? shelfId;
  final OpeningStockPrices prices;
  final String effectiveDate;
}

/// Posts initial branch stock only through batches_fefo + stock_movements.
/// Each operation uses a durable key and one SQLite transaction.
class _PreviewRollback implements Exception {
  const _PreviewRollback();
}

class OpeningInventoryService {
  OpeningInventoryService({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;
  final DatabaseHelper _helper;

  static String _newIdentifier() {
    final random = Random.secure();
    final values = List<int>.generate(16, (_) => random.nextInt(256));
    // RFC 4122 version 4 / variant 1 UUID.
    values[6] = (values[6] & 0x0f) | 0x40;
    values[8] = (values[8] & 0x3f) | 0x80;
    final hex = values.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  static String _normalizeName(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  static bool _validDate(String s) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return false;
    final value = DateTime.tryParse(s);
    return value != null &&
        value.year.toString().padLeft(4, '0') == s.substring(0, 4) &&
        value.month.toString().padLeft(2, '0') == s.substring(5, 7) &&
        value.day.toString().padLeft(2, '0') == s.substring(8, 10);
  }

  Future<_Prepared> _prepare(Transaction txn, int branchId,
      OpeningStockLine row, String defaultDate) async {
    if (row.packetsPerCarton < 1 ||
        row.unitsPerPacket < 1 ||
        row.cartons < 0 ||
        row.packets < 0 ||
        row.units < 0 ||
        row.quantityUnits <= 0 ||
        row.quantityUnits > 9007199254740991) {
      throw StateError('كميات أو وحدات التعبئة غير صحيحة');
    }
    if (row.unitCost < 0 || !row.unitCost.isFinite) {
      throw StateError('تكلفة الوحدة غير صحيحة');
    }
    final effective = row.effectiveDate ?? defaultDate;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (!_validDate(row.expiryDate) ||
        !_validDate(effective) ||
        effective.compareTo(today) > 0) {
      throw StateError('تاريخ الانتهاء أو تاريخ الإدخال غير صحيح');
    }
    final warehouses = await txn.query('warehouses',
        where: 'id=? AND branch_id=?',
        whereArgs: [row.warehouseId, branchId],
        limit: 1);
    if (warehouses.isEmpty) throw StateError('المخزن لا يتبع الفرع الحالي');

    List<Map<String, Object?>> drugs;
    if (row.drugId != null) {
      drugs = await txn.query('drugs',
          where: 'id=? AND branch_id=? AND is_deleted=0 AND is_active=1',
          whereArgs: [row.drugId, branchId],
          limit: 1);
      if (drugs.isEmpty) {
        throw StateError('معرّف الدواء غير موجود أو غير نشط في الفرع');
      }
    } else {
      final name = _normalizeName(row.drugName);
      if (name.isEmpty) throw StateError('اسم الدواء مطلوب');
      // Exact match first; do not silently merge different drugs.
      drugs = await txn.query('drugs',
          where: 'branch_id=? AND is_deleted=0 AND '
              '(trade_name_ar=? OR trade_name_en=? OR internal_code=?)',
          whereArgs: [branchId, name, name, name]);
      if (drugs.length > 1) {
        throw StateError('اسم الدواء مكرر؛ استخدم معرّف الدواء: $name');
      }
      if (drugs.isNotEmpty && drugs.first['is_active'] != 1) {
        throw StateError('الدواء موجود ولكنه غير نشط: $name');
      }
      if (drugs.isEmpty && row.resolveUnitsFromCatalog) {
        throw StateError(
            'الصنف غير موجود: $name. أضفه أولاً وحدد عدد الحبات في الشريط '
            'حتى لا يُسجّل الرصيد بوحدات غير صحيحة');
      }
      if (drugs.isEmpty) {
        // The user explicitly enabled automatic catalog creation on posting.
        // Only data present in Excel is used. Never infer clinical properties.
        final uuid = _newIdentifier();
        final now = DateTime.now().toUtc().toIso8601String();
        final id = await txn.insert('drugs', {
          'uuid': uuid,
          'branch_id': branchId,
          'created_at': now,
          'updated_at': now,
          'internal_code': 'OPEN-${uuid.replaceAll('-', '')}',
          'trade_name_ar': name,
          'dosage_form': row.dosageForm ?? 'OTHER',
          'strips_per_pack': row.packetsPerCarton,
          'units_per_strip': row.unitsPerPacket,
          'units_per_pack': row.packetsPerCarton * row.unitsPerPacket,
          'stock_total_units': 0,
        });
        drugs =
            await txn.query('drugs', where: 'id=?', whereArgs: [id], limit: 1);
      }
    }
    final drug = drugs.first;
    final resolvedUnitsPerStrip = row.resolveUnitsFromCatalog
        ? (drug['units_per_strip'] as int? ?? 0)
        : row.unitsPerPacket;
    if (resolvedUnitsPerStrip < 1) {
      throw StateError('يجب تحديد عدد الحبات في الشريط للصنف ${row.drugName}');
    }
    // Catalog medicines often have the schema default of 1 unit per strip.
    // For tablets/capsules or unidentified forms that value is unverified.
    // Never silently count entire strips as one tablet in opening stock.
    final form = (drug['dosage_form'] as String? ?? 'OTHER').toUpperCase();
    if (row.resolveUnitsFromCatalog &&
        resolvedUnitsPerStrip == 1 &&
        {'TABLET', 'CAPSULE', 'OTHER'}.contains(form)) {
      throw StateError(
          'تعبئة الصنف ${row.drugName} غير مكتملة: تحقق من عدد الحبات '
          'في الشريط ونوع الدواء ببطاقة الصنف قبل ترحيل الرصيد');
    }
    final effectiveRow = row.resolveUnitsFromCatalog
        ? row.withUnitsPerPacket(resolvedUnitsPerStrip)
        : row;
    if (effectiveRow.quantityUnits <= 0 ||
        effectiveRow.quantityUnits > 9007199254740991) {
      throw StateError('حجم الرصيد غير صالح');
    }
    final drugId = drug['id'] as int;
    final storedForm = (drug['dosage_form'] as String?) ?? 'OTHER';
    if (row.dosageForm != null &&
        storedForm != 'OTHER' &&
        storedForm != row.dosageForm) {
      throw StateError(
          'نوع الدواء لا يطابق الصنف المسجل: ${row.drugName} ($storedForm)');
    }
    final currentRatio =
        (drug['strips_per_pack'] as int) * (drug['units_per_strip'] as int);
    final newRatio =
        effectiveRow.packetsPerCarton * effectiveRow.unitsPerPacket;
    if (currentRatio != newRatio ||
        drug['strips_per_pack'] != effectiveRow.packetsPerCarton ||
        drug['units_per_strip'] != effectiveRow.unitsPerPacket) {
      final anyBatches = await txn.query('batches_fefo',
          columns: ['id'], where: 'drug_id=?', whereArgs: [drugId], limit: 1);
      if (anyBatches.isNotEmpty ||
          (drug['stock_total_units'] as int? ?? 0) > 0) {
        throw StateError('لا يمكن تغيير تعبئة دواء له تشغيلات مسجلة');
      }
    }
    if ((drug['requires_refrigeration'] as num? ?? 0) == 1 &&
        warehouses.first['wh_type'] != 'FRIDGE') {
      throw StateError('الدواء المبرد يتطلب مخزن ثلاجة');
    }
    int? shelfId;
    if (row.shelfCode != null && row.shelfCode!.trim().isNotEmpty) {
      final shelves = await txn.query('shelf_locations',
          where: 'warehouse_id=? AND code=?',
          whereArgs: [row.warehouseId, row.shelfCode!.trim()],
          limit: 1);
      if (shelves.isEmpty)
        throw StateError('رقم الرف غير موجود في المخزن المحدد');
      if ((drug['requires_refrigeration'] as num? ?? 0) == 1 &&
          (shelves.first['is_fridge'] as num? ?? 0) != 1) {
        throw StateError('الدواء المبرد يجب أن يكون على رف مبرد عند تحديد رف');
      }
      shelfId = shelves.first['id'] as int;
    }
    return _Prepared(
      row: effectiveRow,
      drugId: drugId,
      drug: drug,
      qty: effectiveRow.quantityUnits,
      shelfId: shelfId,
      prices: effectiveRow.prices.fillMissing(
          effectiveRow.packetsPerCarton, effectiveRow.unitsPerPacket),
      effectiveDate: effective,
    );
  }

  /// Distinct lots of one medicine must not silently overwrite each other's
  /// explicit branch selling prices. A missing price is not a conflict.
  static void _verifyRepeatedPrices(
      Map<int, OpeningStockPrices> byDrug, _Prepared prepared) {
    final original = prepared.row.prices;
    final previous = byDrug[prepared.drugId];
    if (previous != null) {
      for (final pair in [
        [previous.carton, original.carton],
        [previous.packet, original.packet],
        [previous.unit, original.unit],
      ]) {
        if (pair[0] != null &&
            pair[1] != null &&
            (pair[0]! - pair[1]!).abs() > 0.000001) {
          throw StateError(
              'أسعار بيع مختلفة للدواء نفسه في صفوف متعددة؛ وحّدها أو راجعها');
        }
      }
      byDrug[prepared.drugId] = OpeningStockPrices(
        carton: previous.carton ?? original.carton,
        packet: previous.packet ?? original.packet,
        unit: previous.unit ?? original.unit,
      );
    } else {
      byDrug[prepared.drugId] = original;
    }
  }

  Future<OpeningStockPreview> preview({
    required int branchId,
    required String effectiveDate,
    required List<OpeningStockLine> lines,
  }) async {
    final errors = <String>[];
    var total = 0;
    final seenRatio = <int, String>{};
    final seenPrices = <int, OpeningStockPrices>{};
    if (lines.isEmpty) errors.add('أدخل صنفًا واحدًا على الأقل');
    if (!_validDate(effectiveDate) ||
        effectiveDate
                .compareTo(DateTime.now().toIso8601String().substring(0, 10)) >
            0) {
      errors.add('تاريخ الإدخال غير صالح');
    }
    final db = await _helper.database;
    try {
      await db.transaction((txn) async {
        for (var i = 0; i < lines.length; i++) {
          try {
            final prepared =
                await _prepare(txn, branchId, lines[i], effectiveDate);
            final key =
                '${prepared.row.packetsPerCarton}x${prepared.row.unitsPerPacket}';
            if (seenRatio[prepared.drugId] != null &&
                seenRatio[prepared.drugId] != key) {
              throw StateError('تعبئة مختلفة لنفس الدواء داخل الملف');
            }
            seenRatio[prepared.drugId] = key;
            _verifyRepeatedPrices(seenPrices, prepared);
            total += prepared.qty;
          } catch (e) {
            errors.add('الصف ${i + 2}: $e');
          }
        }
        // Preview may provision missing catalog rows for validation, but must
        // never persist them. All provisional inserts are rolled back here.
        throw const _PreviewRollback();
      });
    } on _PreviewRollback {
      // Validation completed; database remains unchanged.
    }
    return OpeningStockPreview(total, errors);
  }

  Future<int> post({
    required int branchId,
    required String operationUuid,
    required String effectiveDate,
    required List<OpeningStockLine> lines,
    String? sourceHash,
    String? sourceName,
  }) async {
    if (operationUuid.trim().isEmpty) {
      throw ArgumentError('معرّف العملية مطلوب');
    }
    final db = await _helper.database;
    return db.transaction((txn) async {
      final repeated = await txn.query('opening_inventory_posts',
          where: 'operation_uuid=? AND branch_id=?',
          whereArgs: [operationUuid, branchId],
          limit: 1);
      if (repeated.isNotEmpty) return repeated.first['id'] as int;
      if (sourceHash != null) {
        final prior = await txn.query('opening_inventory_posts',
            where: 'branch_id=? AND source_hash=?',
            whereArgs: [branchId, sourceHash],
            limit: 1);
        if (prior.isNotEmpty) {
          throw StateError('تم استيراد ملف Excel نفسه مسبقًا؛ لن نكرر الرصيد');
        }
      }
      final previewResult = <_Prepared>[];
      final perDrugRatio = <int, String>{};
      final perDrugPrices = <int, OpeningStockPrices>{};
      final perDrugForms = <int, String>{};
      for (var i = 0; i < lines.length; i++) {
        final value = await _prepare(txn, branchId, lines[i], effectiveDate);
        final key = '${value.row.packetsPerCarton}x${value.row.unitsPerPacket}';
        if (perDrugRatio[value.drugId] != null &&
            perDrugRatio[value.drugId] != key) {
          throw StateError('تعبئة مختلفة لنفس الدواء في الصف ${i + 2}');
        }
        perDrugRatio[value.drugId] = key;
        final form = lines[i].dosageForm;
        if (form != null) {
          final previousForm = perDrugForms[value.drugId];
          if (previousForm != null && previousForm != form) {
            throw StateError('أنواع مختلفة لنفس الدواء في الصف ${i + 2}');
          }
          perDrugForms[value.drugId] = form;
        }
        _verifyRepeatedPrices(perDrugPrices, value);
        previewResult.add(value);
      }
      if (previewResult.isEmpty) throw StateError('لا توجد أصناف لاعتمادها');
      if (!_validDate(effectiveDate) ||
          effectiveDate.compareTo(
                  DateTime.now().toIso8601String().substring(0, 10)) >
              0) {
        throw StateError('تاريخ الإدخال غير صالح');
      }
      final now = DateTime.now().toIso8601String();
      final id = await txn.insert('opening_inventory_posts', {
        'operation_uuid': operationUuid,
        'branch_id': branchId,
        'source_hash': sourceHash,
        'source_name': sourceName,
        'effective_date': effectiveDate,
        'posted_at': now,
        'line_count': lines.length,
        'total_units': previewResult.fold<int>(0, (sum, p) => sum + p.qty),
      });

      for (var i = 0; i < previewResult.length; i++) {
        final p = previewResult[i];
        final line = p.row;
        final drug = p.drug;
        // Combine explicit prices across lots before suggesting missing fields.
        // No later row may erase an earlier manual carton/packet/unit price.
        final resolvedPrices = perDrugPrices[p.drugId]!
            .fillMissing(line.packetsPerCarton, line.unitsPerPacket);
        // Prices are medicine-level fields already consumed by clinical details.
        // Never copy stock quantities or expiry batches to clinical fields.
        final update = <String, Object?>{
          'strips_per_pack': line.packetsPerCarton,
          'units_per_strip': line.unitsPerPacket,
          'units_per_pack': line.packetsPerCarton * line.unitsPerPacket,
          'strip_price_mode': 'MANUAL',
          'updated_at': now,
        };
        // Populate only an unclassified medicine, never overwrite a known form.
        if (((drug['dosage_form'] as String?) ?? 'OTHER') == 'OTHER' &&
            perDrugForms[p.drugId] != null) {
          update['dosage_form'] = perDrugForms[p.drugId];
        }
        if (resolvedPrices.carton != null)
          update['sell_price_pack'] = resolvedPrices.carton;
        if (resolvedPrices.packet != null)
          update['sell_price_strip'] = resolvedPrices.packet;
        if (resolvedPrices.unit != null)
          update['sell_price_unit'] = resolvedPrices.unit;
        await txn.update('drugs', update,
            where: 'id=? AND branch_id=? AND is_deleted=0',
            whereArgs: [p.drugId, branchId]);

        final batchNo = line.batchNo.trim().isEmpty
            ? 'OPEN-${operationUuid.substring(0, operationUuid.length < 8 ? operationUuid.length : 8)}-${i + 1}'
            : line.batchNo.trim();
        final existing = await txn.query('batches_fefo',
            where:
                'drug_id=? AND warehouse_id=? AND batch_no=? AND expiry_date=?',
            whereArgs: [p.drugId, line.warehouseId, batchNo, line.expiryDate],
            limit: 1);
        final unitsPerCarton = line.packetsPerCarton * line.unitsPerPacket;
        final today = now.substring(0, 10);
        final expired = line.expiryDate.compareTo(today) < 0;
        int batchId;
        int balance;
        if (existing.isEmpty) {
          batchId = await txn.insert('batches_fefo', {
            'drug_id': p.drugId,
            'warehouse_id': line.warehouseId,
            'location_id': p.shelfId,
            'batch_no': batchNo,
            'expiry_date': line.expiryDate,
            'sealed_packs': p.qty ~/ unitsPerCarton,
            'loose_units': p.qty % unitsPerCarton,
            'total_units': p.qty,
            'unit_cost': line.unitCost,
            'pack_cost': line.unitCost * unitsPerCarton,
            'status': expired ? 'EXPIRED' : 'ACTIVE',
          });
          balance = p.qty;
        } else {
          final old = existing.first;
          if (p.shelfId != null &&
              old['location_id'] != null &&
              old['location_id'] != p.shelfId) {
            throw StateError('التشغيلة موجودة في رف مختلف؛ راجع الصف ${i + 2}');
          }
          if (old['purchase_invoice_item_id'] != null &&
              (old['unit_cost'] as num).toDouble() != line.unitCost) {
            throw StateError(
                'تكلفة التشغيلة المحاسبية مختلفة؛ راجع الصف ${i + 2}');
          }
          balance = (old['total_units'] as int) + p.qty;
          final oldCost = (old['unit_cost'] as num).toDouble();
          final weightedCost =
              ((old['total_units'] as int) * oldCost + p.qty * line.unitCost) /
                  balance;
          batchId = old['id'] as int;
          await txn.update(
              'batches_fefo',
              {
                'location_id': old['location_id'] ?? p.shelfId,
                'total_units': balance,
                'sealed_packs': balance ~/ unitsPerCarton,
                'loose_units': balance % unitsPerCarton,
                'unit_cost': weightedCost,
                'pack_cost': weightedCost * unitsPerCarton,
                'status': expired ? 'EXPIRED' : 'ACTIVE',
              },
              where: 'id=?',
              whereArgs: [batchId]);
        }
        await txn.insert('stock_movements', {
          'drug_id': p.drugId,
          'batch_id': batchId,
          'warehouse_id': line.warehouseId,
          'movement_type': 'OPENING_IN',
          'qty_units': p.qty,
          'unit_cost': line.unitCost,
          'unit_price':
              p.prices.unit ?? (drug['sell_price_unit'] as num).toDouble(),
          'balance_after_units': balance,
          'doc_type': 'OPENING_INVENTORY',
          'doc_id': id,
          'doc_line_id': i + 1,
          'movement_at': now,
          'note': 'تاريخ الرصيد: ${p.effectiveDate}; ${line.note}',
        });
        await txn.rawUpdate(
            'UPDATE drugs SET stock_total_units=stock_total_units+?,updated_at=? WHERE id=? AND branch_id=?',
            [p.qty, now, p.drugId, branchId]);
      }
      return id;
    });
  }
}
