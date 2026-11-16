/// Configuración de compilación.
///
/// La URL de la API se pasa al compilar:
///   flutter run --dart-define=API_URL=https://app.vexi.com/api/v1
///
/// Sin ella se usa el servidor local: `10.0.2.2` es el «localhost» de la
/// computadora visto desde el emulador de Android.
class AppConfig {
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8000/api/v1');

  static const appName = 'Vexi';
}
