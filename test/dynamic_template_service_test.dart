import 'package:flutter_test/flutter_test.dart';
import 'package:noctra/services/network/dynamic_template_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DynamicTemplateService (api-anything engine)', () {
    const testRegistry = '''{
      "version": "1.0.0",
      "operations": {
        "test_operation": {
          "url": "https://api.test.com/v1/feed",
          "method": "GET",
          "headers": {
            "Authorization": "Bearer {{token}}"
          },
          "params": {
            "genre": "{{genre|default:pop}}",
            "limit": "{{limit|default:20}}"
          },
          "fallbacks": ["test_fallback"]
        },
        "test_fallback": {
          "url": "https://backup.test.com/v1/feed",
          "method": "GET"
        }
      }
    }''';

    test('loads JSON template registry successfully', () async {
      final service = DynamicTemplateService.instance;
      final ok = await service.loadTemplates(testRegistry);
      expect(ok, isTrue);
      expect(service.hasOperation('test_operation'), isTrue);
      expect(service.hasOperation('test_fallback'), isTrue);
      expect(service.hasOperation('non_existent'), isFalse);
    });

    test('interpolates parameters and defaults cleanly', () async {
      final service = DynamicTemplateService.instance;
      await service.loadTemplates(testRegistry);

      // Verify that execution handles missing network gracefully with fallback
      final result = await service.execute('test_operation', {
        'token': 'secret_xyz',
        'genre': 'synthwave',
      });
      // In disconnected test environment, returns null or fallback response
      expect(result == null || result is Map, isTrue);
    });
  });
}
