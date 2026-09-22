import 'package:flutter_test/flutter_test.dart';
import 'package:reelriot_tv/services/update_service.dart';

void main() {
  group('UpdateService.isVersionHigher', () {
    late UpdateService service;

    setUp(() {
      service = UpdateService();
    });

    test('detects patch release update', () {
      expect(service.isVersionHigher('1.0.1', '1.0.0'), isTrue);
      expect(service.isVersionHigher('1.0.0', '1.0.1'), isFalse);
    });

    test('detects minor and major release updates', () {
      expect(service.isVersionHigher('1.1.0', '1.0.9'), isTrue);
      expect(service.isVersionHigher('2.0.0', '1.9.9'), isTrue);
      expect(service.isVersionHigher('1.0.0', '2.0.0'), isFalse);
    });

    test('handles build metadata with plus symbol correctly', () {
      expect(service.isVersionHigher('1.0.0+3', '1.0.0+2'), isTrue);
      expect(service.isVersionHigher('1.0.0+2', '1.0.0+3'), isFalse);
      expect(service.isVersionHigher('1.0.0+2', '1.0.0+2'), isFalse);
    });

    test('prioritizes base version over build numbers', () {
      expect(service.isVersionHigher('1.0.1+1', '1.0.0+99'), isTrue);
      expect(service.isVersionHigher('1.0.0+99', '1.0.1+1'), isFalse);
    });

    test('handles leading v prefix seamlessly', () {
      expect(service.isVersionHigher('v1.0.1', '1.0.0'), isTrue);
      expect(service.isVersionHigher('1.0.1', 'v1.0.0'), isTrue);
      expect(service.isVersionHigher('v1.0.1', 'v1.0.1'), isFalse);
    });

    test('handles CalVer scheme releases', () {
      expect(service.isVersionHigher('2026.09.21+145', '2026.09.20+144'), isTrue);
      expect(service.isVersionHigher('2026.09.20+144', '2026.09.21+145'), isFalse);
    });

    test('prevents downgrade loops on older server versions', () {
      expect(service.isVersionHigher('1.0.0', '1.0.2'), isFalse);
      expect(service.isVersionHigher('v1.0.0+1', 'v1.0.1+2'), isFalse);
    });

    test('handles empty or malformed strings safely without throwing', () {
      expect(service.isVersionHigher('', '1.0.0'), isFalse);
      expect(service.isVersionHigher('1.0.0', ''), isFalse);
      expect(service.isVersionHigher('invalid', '1.0.0'), isFalse);
    });
  });
}
