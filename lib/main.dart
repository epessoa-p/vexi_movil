import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/session.dart';
import 'screens/auth_screens.dart';
import 'screens/shell.dart';
import 'ui/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');

  final session = Session(ApiClient());
  runApp(VexiApp(session: session));
  session.restore();
}

class VexiApp extends StatelessWidget {
  const VexiApp({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: session,
      child: MaterialApp(
        title: 'Vexi',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const _Root(),
      ),
    );
  }
}

/// Elige la pantalla según el estado de la sesión.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: switch (session.status) {
        SessionStatus.loading => const SplashScreen(),
        SessionStatus.offline => const OfflineScreen(),
        SessionStatus.signedOut => const LoginScreen(),
        SessionStatus.choosingCompany => const CompanyPickerScreen(),
        // La clave fuerza a reconstruir todo al cambiar de veterinaria.
        SessionStatus.ready => AppShell(key: ValueKey(session.profile!.company!.id)),
      },
    );
  }
}
