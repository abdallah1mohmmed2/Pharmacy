import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

abstract final class SecurityHashService {
  static const int _iterations = 120000;
  static const int _saltLength = 16;

  static String hash(String secret) {
    if (secret.isEmpty) {
      throw ArgumentError.value(secret, 'secret', 'لا يمكن تجزئة قيمة فارغة');
    }
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(_saltLength, (_) => random.nextInt(256)),
    );
    final derived = _pbkdf2(secret, salt, _iterations);
    final separator = String.fromCharCode(36);
    return [
      'pbkdf2_sha256',
      _iterations.toString(),
      base64Url.encode(salt),
      base64Url.encode(derived),
    ].join(separator);
  }

  static bool verify(String secret, String encoded) {
    final separator = String.fromCharCode(36);
    final parts = encoded.split(separator);
    if (parts.length != 4 || parts[0] != 'pbkdf2_sha256') return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 10000 || iterations > 1000000) {
      return false;
    }
    try {
      final salt = base64Url.decode(parts[2]);
      final expected = base64Url.decode(parts[3]);
      final actual = _pbkdf2(secret, salt, iterations);
      if (actual.length != expected.length) return false;
      var difference = 0;
      for (var i = 0; i < actual.length; i++) {
        difference |= actual[i] ^ expected[i];
      }
      return difference == 0;
    } on FormatException {
      return false;
    }
  }

  static Uint8List _pbkdf2(String password, List<int> salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final block = Uint8List(salt.length + 4)..setRange(0, salt.length, salt);
    block[salt.length] = 0;
    block[salt.length + 1] = 0;
    block[salt.length + 2] = 0;
    block[salt.length + 3] = 1;
    var u = Uint8List.fromList(hmac.convert(block).bytes);
    final output = Uint8List.fromList(u);
    for (var round = 1; round < iterations; round++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var i = 0; i < output.length; i++) {
        output[i] ^= u[i];
      }
    }
    return output;
  }
}
