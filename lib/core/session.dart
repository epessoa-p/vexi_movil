import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'models.dart';

/// Almacén del token. Interfaz propia para poder probar sin el llavero del sistema.
abstract class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SecureTokenStore implements TokenStore {
  const SecureTokenStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) => value == null ? _storage.delete(key: key) : _storage.write(key: key, value: value);
}

enum SessionStatus { loading, offline, signedOut, choosingCompany, ready }

/// Estado de la sesión: token, perfil y veterinaria activa.
///
/// El token y la veterinaria elegida se guardan en el almacenamiento seguro
/// del teléfono, así la app abre directo donde quedó.
class Session extends ChangeNotifier {
  Session(this.api, {TokenStore? store}) : _store = store ?? const SecureTokenStore() {
    api.onUnauthorized = _expire;
  }

  final ApiClient api;
  final TokenStore _store;

  static const _tokenKey = 'vexi_token';
  static const _companyKey = 'vexi_company';

  SessionStatus status = SessionStatus.loading;
  Profile? profile;

  /// Mensaje para mostrar en el login cuando la sesión se cerró sola.
  String? notice;

  Future<void> restore() async {
    _set(SessionStatus.loading);
    api.token = await _store.read(_tokenKey);
    api.companyId = int.tryParse(await _store.read(_companyKey) ?? '');

    if (api.token == null) {
      _set(SessionStatus.signedOut);
      return;
    }

    try {
      await _loadProfile();
    } on ApiException catch (e) {
      if (e.isUnauthorized) return; // _expire ya cerró la sesión
      if (e.code == 'company_forbidden') {
        // Ya no pertenece a la veterinaria guardada: que elija otra.
        await _rememberCompany(null);
        await _loadProfile();
        return;
      }
      // Sin conexión: la sesión sigue guardada; se ofrece reintentar.
      notice = e.message;
      _set(SessionStatus.offline);
    }
  }

  Future<void> login(String email, String password, String device) async {
    final json = await api.post('/auth/login', {'email': email, 'password': password, 'device_name': device});
    api.token = json['token'] as String;
    await _store.write(_tokenKey, api.token);
    notice = null;

    final first = Profile.fromJson(json);
    final saved = api.companyId;
    final keep = saved != null && first.companies.any((c) => c.id == saved);
    api.companyId = keep ? saved : (first.companies.length == 1 ? first.companies.first.id : null);
    await _rememberCompany(api.companyId);
    await _loadProfile();
  }

  Future<void> chooseCompany(int id) async {
    api.companyId = id;
    await _rememberCompany(id);
    await _loadProfile();
  }

  /// Volver a leer permisos y plan (p. ej. tras cambiar de veterinaria).
  Future<void> refreshProfile() => _loadProfile();

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } on ApiException {
      // Si no hay red, igual se cierra la sesión en el teléfono.
    }
    await _clear();
    _set(SessionStatus.signedOut);
  }

  Future<void> _loadProfile() async {
    final json = await api.get('/me');
    profile = Profile.fromJson(json);
    _set(profile!.company == null ? SessionStatus.choosingCompany : SessionStatus.ready);
  }

  Future<void> _rememberCompany(int? id) async {
    api.companyId = id;
    await _store.write(_companyKey, id?.toString());
  }

  void _expire() {
    if (status == SessionStatus.signedOut) return;
    notice = 'Tu sesión terminó. Vuelve a ingresar.';
    _clear();
    _set(SessionStatus.signedOut);
  }

  Future<void> _clear() async {
    api.token = null;
    profile = null;
    await _store.write(_tokenKey, null);
  }

  void _set(SessionStatus value) {
    status = value;
    notifyListeners();
  }
}
