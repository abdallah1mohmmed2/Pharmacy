import 'dart:convert';
import 'dart:io';

/// Reads import rows incrementally. Only one CSV record or JSON object is
/// buffered at a time; a 30,000-drug file is never placed in a TextField or
/// deserialized into one giant List.
abstract final class DrugImportStreamReader {
  static Stream<Map<String, Object?>> read(File file, String format) {
    final chunks = file.openRead().transform(utf8.decoder);
    switch (format.toUpperCase()) {
      case 'JSON':
        return _jsonRows(chunks);
      case 'CSV':
        return _csvRows(chunks);
      default:
        throw ArgumentError('الصيغة المدعومة CSV أو JSON فقط');
    }
  }

  static Stream<Map<String, Object?>> _jsonRows(Stream<String> chunks) async* {
    // 0 = root, 1 = wrapper prefix, 2 = array, 3 = drug object, 4 = done.
    var state = 0;
    var nesting = 0;
    var quoted = false;
    var escaped = false;
    var wrapper = StringBuffer();
    var object = StringBuffer();
    final drugsArray = RegExp(r'"drugs"\s*:\s*\[$');

    await for (final chunk in chunks) {
      for (var i = 0; i < chunk.length; i++) {
        final c = chunk[i];
        if (state == 0) {
          if (c.trim().isEmpty || c == '\uFEFF') continue;
          if (c == '[') {
            state = 2;
          } else if (c == '{') {
            wrapper.write(c);
            state = 1;
          } else {
            throw const FormatException('JSON يجب أن يبدأ بقائمة أدوية');
          }
        } else if (state == 1) {
          wrapper.write(c);
          if (c == '[' && drugsArray.hasMatch(wrapper.toString())) {
            state = 2;
            wrapper = StringBuffer();
          } else if (wrapper.length > 131072) {
            throw const FormatException('تعذر العثور على مصفوفة drugs');
          }
        } else if (state == 2) {
          if (c.trim().isEmpty || c == ',') continue;
          if (c == ']') {
            state = 4;
          } else if (c == '{') {
            state = 3;
            nesting = 1;
            quoted = false;
            escaped = false;
            object = StringBuffer()..write(c);
          } else {
            throw const FormatException('كل دواء في JSON يجب أن يكون كائناً');
          }
        } else if (state == 3) {
          object.write(c);
          if (quoted) {
            if (escaped) {
              escaped = false;
            } else if (c == '\\') {
              escaped = true;
            } else if (c == '"') {
              quoted = false;
            }
          } else if (c == '"') {
            quoted = true;
          } else if (c == '{') {
            nesting++;
          } else if (c == '}') {
            nesting--;
            if (nesting == 0) {
              final decoded = jsonDecode(object.toString());
              if (decoded is! Map) {
                throw const FormatException('سجل JSON غير صالح');
              }
              yield Map<String, Object?>.from(decoded);
              object = StringBuffer();
              state = 2;
            }
          }
        } else if (state == 4 && c.trim().isNotEmpty &&
            c != '}' && c != '\uFEFF') {
          throw const FormatException('بيانات إضافية بعد نهاية قائمة الأدوية');
        }
      }
    }
    if (state != 4) {
      throw const FormatException('ملف JSON غير مكتمل أو غير صالح');
    }
  }

  static Stream<Map<String, Object?>> _csvRows(Stream<String> chunks) async* {
    List<String>? headers;
    var cells = <String>[];
    var field = StringBuffer();
    var quoted = false;
    var quotePending = false;
    var hasData = false;
    var first = true;

    await for (final chunk in chunks) {
      for (var i = 0; i < chunk.length; i++) {
        var c = chunk[i];
        if (first) {
          first = false;
          if (c == '\uFEFF') continue;
        }
        if (quoted && quotePending) {
          if (c == '"') {
            field.write('"');
            quotePending = false;
            hasData = true;
            continue;
          }
          quoted = false;
          quotePending = false;
        }
        if (quoted) {
          if (c == '"') {
            quotePending = true;
          } else {
            field.write(c);
          }
          hasData = true;
          continue;
        }
        if (c == '"' && field.length == 0) {
          quoted = true;
          hasData = true;
        } else if (c == ',') {
          cells.add(field.toString());
          field = StringBuffer();
          hasData = true;
        } else if (c == '\n') {
          cells.add(field.toString());
          field = StringBuffer();
          if (headers == null) {
            headers = cells.map((e) => e.trim()).toList();
            if (headers!.isNotEmpty) {
              headers![0] = headers![0].replaceFirst('\uFEFF', '');
            }
          } else if (cells.any((e) => e.trim().isNotEmpty)) {
            final row = <String, Object?>{};
            for (var k = 0; k < headers!.length && k < cells.length; k++) {
              row[headers![k]] = cells[k];
            }
            yield row;
          }
          cells = <String>[];
          hasData = false;
        } else if (c != '\r') {
          field.write(c);
          hasData = true;
        }
      }
    }
    if (quoted && !quotePending) {
      throw const FormatException('علامة اقتباس CSV غير مغلقة');
    }
    if (hasData || cells.isNotEmpty) {
      cells.add(field.toString());
      if (headers == null) {
        headers = cells.map((e) => e.trim()).toList();
      } else if (cells.any((e) => e.trim().isNotEmpty)) {
        final row = <String, Object?>{};
        for (var k = 0; k < headers.length && k < cells.length; k++) {
          row[headers[k]] = cells[k];
        }
        yield row;
      }
    }
  }
}
