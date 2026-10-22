import 'package:flutter_test/flutter_test.dart';
import 'package:gomuku/services/server_address.dart';

void main() {
  test(
      'IP and bare domain use game port, full URLs use their own scheme and port',
      () {
    for (final entry in {
      ' 192.0.2.1 ': 'http://192.0.2.1:3000',
      'game.example.com:3001': 'http://game.example.com:3001',
      'game.example.com': 'http://game.example.com:3000',
      'https://game.example.com/': 'https://game.example.com',
      'http://game.example.com:3001': 'http://game.example.com:3001',
      'wss://game.example.com': 'https://game.example.com',
      'ws://game.example.com:3001': 'http://game.example.com:3001',
      '[::1]:3001': 'http://[::1]:3001',
    }.entries) {
      expect(parseServerAddress(entry.key).toString(), entry.value);
    }
  });
  test('rejects incomplete addresses, credentials and non-root URLs', () {
    for (final input in [
      '',
      'https://',
      'ftp://example.com',
      'https://user:pass@example.com',
      'https://example.com/admin',
      'https://example.com?token=secret',
      'http://example.com:0'
    ]) {
      expect(() => parseServerAddress(input), throwsFormatException,
          reason: input);
    }
  });
}
