import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import '../../core/utils/noctra_logger.dart';
import '../rust/noctra_rust_bridge.dart';

/// Declarative, self-healing HTTP API template engine service for Noctra.
/// Inspired by `api-anything`.
class DynamicTemplateService {
  DynamicTemplateService._();
  static final DynamicTemplateService instance = DynamicTemplateService._();

  final Map<String, Map<String, dynamic>> _dartTemplates = {};
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// Initializes the service by loading bundled template definitions.
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final jsonStr = await rootBundle.loadString('assets/templates/provider_endpoints.json');
      await loadTemplates(jsonStr);
      _isInitialized = true;
      NoctraLogger.i('DynamicTemplateService initialized with bundled templates');
    } catch (e) {
      NoctraLogger.w('Failed to load bundled provider templates: $e');
    }
  }

  /// Loads template registry from JSON string into both Rust FFI and Dart fallback.
  Future<bool> loadTemplates(String jsonStr) async {
    try {
      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
      final operations = (parsed['operations'] as Map<String, dynamic>?) ?? parsed;
      _dartTemplates.clear();
      for (final entry in operations.entries) {
        if (entry.value is Map<String, dynamic>) {
          _dartTemplates[entry.key] = entry.value as Map<String, dynamic>;
        }
      }

      // Sync with native Rust engine if available
      final rustOk = NoctraRustBridge.instance.loadTemplateRegistry(jsonStr);
      NoctraLogger.d('Template registry loaded (${_dartTemplates.length} ops, Rust FFI: $rustOk)');
      return true;
    } catch (e) {
      NoctraLogger.e('Failed to load templates into DynamicTemplateService', e);
      return false;
    }
  }

  /// Check if a template operation exists.
  bool hasOperation(String operationId) {
    if (NoctraRustBridge.instance.hasTemplate(operationId)) return true;
    return _dartTemplates.containsKey(operationId);
  }

  /// Executes an operation template with automatic parameter interpolation and fallback cascading.
  Future<dynamic> execute(String operationId, [Map<String, dynamic> params = const {}]) async {
    if (!_isInitialized) await init();

    // 1. Try native Rust core template engine
    if (NoctraRustBridge.instance.hasTemplate(operationId)) {
      final rustJson = NoctraRustBridge.instance.executeTemplate(operationId, params);
      if (rustJson != null && rustJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(rustJson);
          if (decoded is Map<String, dynamic> && decoded['error'] != null && decoded['status'] == 'error') {
            NoctraLogger.w('Rust template execution error for $operationId: ${decoded['error']}');
          } else {
            return decoded;
          }
        } catch (_) {}
      }
    }

    // 2. Pure Dart fallback execution
    return _executeDart(operationId, params);
  }

  Future<dynamic> _executeDart(String operationId, Map<String, dynamic> params) async {
    final template = _dartTemplates[operationId];
    if (template == null) {
      NoctraLogger.w('Operation $operationId not found in Dart template registry');
      return null;
    }

    try {
      final urlPattern = template['url'] as String? ?? '';
      final method = (template['method'] as String? ?? 'GET').toUpperCase();
      final headersMap = (template['headers'] as Map<String, dynamic>?) ?? {};
      final paramsMap = (template['params'] as Map<String, dynamic>?) ?? {};
      final fallbacks = (template['fallbacks'] as List<dynamic>?)?.cast<String>() ?? [];

      final url = _interpolate(urlPattern, params);
      final headers = headersMap.map((k, v) => MapEntry(k, _interpolate(v.toString(), params)));

      final queryParams = <String, String>{};
      paramsMap.forEach((k, v) {
        final val = _interpolate(v.toString(), params);
        if (val.isNotEmpty) queryParams[k] = val;
      });

      final baseUri = Uri.parse(url);
      final finalUri = baseUri.replace(queryParameters: {
        ...baseUri.queryParameters,
        ...queryParams,
      });

      http.Response response;
      if (method == 'POST') {
        response = await http.post(finalUri, headers: headers).timeout(const Duration(seconds: 8));
      } else {
        response = await http.get(finalUri, headers: headers).timeout(const Duration(seconds: 8));
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }

      // Try fallback cascade
      for (final fallbackId in fallbacks) {
        final fallbackRes = await _executeDart(fallbackId, params);
        if (fallbackRes != null) return fallbackRes;
      }

      return null;
    } catch (e) {
      NoctraLogger.d('Dart template execution failed for $operationId: $e');
      final fallbacks = (template['fallbacks'] as List<dynamic>?)?.cast<String>() ?? [];
      for (final fallbackId in fallbacks) {
        final fallbackRes = await _executeDart(fallbackId, params);
        if (fallbackRes != null) return fallbackRes;
      }
      return null;
    }
  }

  static String _interpolate(String pattern, Map<String, dynamic> vars) {
    var result = pattern;
    final exp = RegExp(r'\{\{\s*([a-zA-Z0-9_|:]+)\s*\}\}');
    final matches = exp.allMatches(pattern).toList().reversed;

    for (final match in matches) {
      final token = match.group(1) ?? '';
      String varName;
      String? defaultVal;

      if (token.contains('|default:')) {
        final parts = token.split('|default:');
        varName = parts[0].trim();
        defaultVal = parts[1].trim();
      } else {
        varName = token.trim();
      }

      final val = vars[varName]?.toString() ?? defaultVal ?? '';
      result = result.replaceRange(match.start, match.end, val);
    }

    return result;
  }
}
