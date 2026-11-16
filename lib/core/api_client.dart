import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

/// Error de la API ya traducido a algo que se puede mostrar.
///
/// `code` es el código estable del servidor (`company_required`,
/// `permission_denied`, `subscription_inactive`, …) y `fieldErrors` trae los
/// mensajes de validación por campo (HTTP 422).
class ApiException implements Exception {
  ApiException(this.status, this.message, {this.code, this.fieldErrors = const {}});

  final int status;
  final String message;
  final String? code;
  final Map<String, String> fieldErrors;

  bool get isUnauthorized => status == 401;
  bool get isOffline => status == 0;

  /// Primer mensaje de validación del campo, si lo hay.
  String? field(String name) => fieldErrors[name];

  @override
  String toString() => message;
}

/// Cliente HTTP de la API v1. Agrega el token y la veterinaria activa a cada
/// petición, y convierte cualquier fallo en [ApiException].
class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl}) : _http = httpClient ?? http.Client(), _baseUrl = baseUrl ?? AppConfig.apiUrl;

  final http.Client _http;
  final String _baseUrl;

  String? token;
  int? companyId;

  /// Se llama cuando el servidor rechaza el token (sesión vencida o revocada).
  void Function()? onUnauthorized;

  static const _timeout = Duration(seconds: 20);

  Future<Map<String, dynamic>> get(String path, {Map<String, String?>? query}) => _send('GET', path, query: query);

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) => _send('POST', path, body: body);

  Future<Map<String, dynamic>> put(String path, [Map<String, dynamic>? body]) => _send('PUT', path, body: body);

  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  /// Sube un archivo (multipart), p. ej. la foto de la mascota tomada con la cámara.
  Future<Map<String, dynamic>> upload(String path, String field, List<int> bytes, String filename) {
    final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl$path'))
      ..headers.addAll(_headers(json: false))
      ..files.add(http.MultipartFile.fromBytes(field, bytes, filename: filename));
    return _dispatch(request, timeout: const Duration(seconds: 60));
  }

  Map<String, String> _headers({bool json = true}) => {
    'Accept': 'application/json',
    if (json) 'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
    if (companyId != null) 'X-Company-Id': '$companyId',
  };

  Future<Map<String, dynamic>> _send(String method, String path, {Map<String, String?>? query, Map<String, dynamic>? body}) {
    final params = <String, String>{
      for (final entry in (query ?? {}).entries)
        if (entry.value != null && entry.value!.isNotEmpty) entry.key: entry.value!,
    };
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: params.isEmpty ? null : params);

    final request = http.Request(method, uri)..headers.addAll(_headers());
    if (body != null) request.body = jsonEncode(body);
    return _dispatch(request);
  }

  /// Descarga un archivo (p. ej. la receta en PDF) y devuelve sus bytes.
  Future<List<int>> download(String path) async {
    final request = http.Request('GET', Uri.parse('$_baseUrl$path'))..headers.addAll(_headers(json: false));
    final response = await _receive(request, const Duration(seconds: 60));
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> _dispatch(http.BaseRequest request, {Duration timeout = _timeout}) async =>
      _decode((await _receive(request, timeout)).body);

  /// Envía la petición y convierte cualquier respuesta que no sea 2xx en [ApiException].
  Future<http.Response> _receive(http.BaseRequest request, Duration timeout) async {
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(timeout));
    } on TimeoutException {
      throw ApiException(0, 'El servidor tarda en responder. Revisa tu conexión e intenta de nuevo.');
    } on http.ClientException {
      throw ApiException(0, 'Sin conexión con el servidor. Revisa tu internet.');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }

    final decoded = _decode(response.body);

    if (response.statusCode == 401) {
      onUnauthorized?.call();
      throw ApiException(401, 'Tu sesión terminó. Vuelve a ingresar.');
    }

    final errors = <String, String>{};
    final raw = decoded['errors'];
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is List && value.isNotEmpty) errors['$key'] = '${value.first}';
      });
    }

    throw ApiException(
      response.statusCode,
      (decoded['message'] as String?) ?? _fallbackMessage(response.statusCode),
      code: decoded['code'] as String?,
      fieldErrors: errors,
    );
  }

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return {};
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : {'data': value};
    } on FormatException {
      return {};
    }
  }

  String _fallbackMessage(int status) => switch (status) {
    404 => 'No encontramos lo que buscabas. Puede que lo hayan eliminado.',
    429 => 'Demasiados intentos. Espera un minuto.',
    >= 500 => 'El servidor tuvo un problema. Intenta de nuevo en un momento.',
    _ => 'No se pudo completar la acción.',
  };
}
