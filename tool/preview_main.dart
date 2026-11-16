// Vista previa para revisar pantallas en el navegador contra una API real.
// NO es la app: se compila aparte y no se distribuye.
//
//   flutter build web -t tool/preview_main.dart \
//     --dart-define=API_URL=http://127.0.0.1:8201/api/v1 \
//     --dart-define=PREVIEW_TOKEN=<token> --dart-define=PREVIEW_COMPANY=1
//
// Luego abrir ?screen=home|agenda|patients|pet&id=5|stay&id=1|vaccines|inventory|notifications|profile|login
// Recepción: waiting|clients|client&id=1|walkin|schedule&id=5|reschedule&id=6|petform&id=5
// Laboratorio: lab|labrequest&id=4|labresults&id=4|labform
// Vacunación: vaccines|health&id=5|vaccinate&id=5|deworm&id=5
// Hospitalización: hospital|stay&id=1|admit&id=5|treat&id=1|discharge&id=1|stays&id=5
// Inventario: inventory|product&id=1|count&id=1|stockin&id=1|kardex&id=1|scan
// Para el dueño: summary|receivables|debt&id=<cliente>|pay&id=<cliente> (abono a su primera venta con saldo)
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:vexi_movil/core/api_client.dart';
import 'package:vexi_movil/core/models.dart';
import 'package:vexi_movil/core/session.dart';
import 'package:vexi_movil/screens/agenda_screens.dart';
import 'package:vexi_movil/screens/auth_screens.dart';
import 'package:vexi_movil/screens/consultation_screens.dart';
import 'package:vexi_movil/screens/finance_screens.dart';
import 'package:vexi_movil/screens/hospital_screens.dart';
import 'package:vexi_movil/screens/inventory_screens.dart';
import 'package:vexi_movil/screens/lab_screens.dart';
import 'package:vexi_movil/screens/notifications_screen.dart';
import 'package:vexi_movil/screens/pet_screens.dart';
import 'package:vexi_movil/screens/profile_screen.dart';
import 'package:vexi_movil/screens/reception_screens.dart';
import 'package:vexi_movil/screens/shell.dart';
import 'package:vexi_movil/screens/vaccine_screens.dart';
import 'package:vexi_movil/ui/common.dart';

class _Store implements TokenStore {
  final values = <String, String>{
    'vexi_token': const String.fromEnvironment('PREVIEW_TOKEN'),
    'vexi_company': const String.fromEnvironment('PREVIEW_COMPANY'),
  };

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async => value == null ? values.remove(key) : values[key] = value;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  FlutterError.onError = (d) => debugPrint('PREVIEW ERROR: ${d.exceptionAsString()} ${d.stack}');
  final params = Uri.base.queryParameters;
  final screen = params['screen'] ?? 'home';
  final id = int.tryParse(params['id'] ?? '') ?? 1;

  final session = Session(ApiClient(), store: _Store());
  if (screen == 'login') {
    session.status = SessionStatus.signedOut;
  } else {
    await session.restore();
  }

  final shellKey = GlobalKey<AppShellState>();
  if (screen == 'drawer') {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => Future.delayed(const Duration(seconds: 1), () => shellKey.currentState?.openDrawer()),
    );
  }

  final Widget home = switch (screen) {
    'login' => const LoginScreen(),
    'agenda' => const AgendaScreen(),
    'appointment' => AppointmentScreen(id: id),
    'patients' => const PetSearchScreen(),
    'pet' => PetScreen(id: id),
    'consultation' => ConsultationScreen(id: id),
    'consultations' => const ConsultationsScreen(),
    'stay' => StayScreen(id: id),
    'treat' => TreatmentScreen(stayId: id),
    'admit' => FutureBuilder<Map<String, dynamic>>(
      future: session.api.get('/pets/$id'),
      builder: (context, snap) =>
          snap.hasData ? AdmitScreen(pet: snap.data!) : const Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
    'discharge' => FutureBuilder<Map<String, dynamic>>(
      future: session.api.get('/hospitalizations/$id'),
      builder: (context, snap) =>
          snap.hasData ? DischargeScreen(stay: snap.data!) : const Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
    'stays' => FutureBuilder<Map<String, dynamic>>(
      future: session.api.get('/pets/$id'),
      builder: (context, snap) => snap.hasData
          ? Scaffold(
              appBar: AppBar(title: Text('${snap.data!['name']} · Internaciones')),
              body: PetStaysTab(pet: snap.data!, reload: () async {}),
            )
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
    'hospital' => const HospitalScreen(),
    'vaccines' => const VaccinesScreen(),
    'vaccinate' => VaccinateScreen(petId: id, petName: 'Copito'),
    'deworm' => DewormScreen(petId: id, petName: 'Copito'),
    'health' => FutureBuilder<Map<String, dynamic>>(
      future: session.api.get('/pets/$id'),
      builder: (context, snap) => snap.hasData
          ? Scaffold(
              appBar: AppBar(title: Text('${snap.data!['name']} · Salud')),
              body: PetHealthTab(pet: snap.data!, reload: () async {}),
            )
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
    'summary' => const SummaryScreen(),
    'receivables' => const ReceivablesScreen(),
    'debt' => ClientDebtScreen(clientId: id),
    'pay' => FutureBuilder<Map<String, dynamic>>(
      future: session.api.get('/clients/$id/receivables'),
      builder: (context, snap) => !snap.hasData
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : PaymentScreen(sale: snap.data!.list('sales').first, clientName: snap.data!.obj('client')?.str('name')),
    ),
    'inventory' => const InventoryScreen(),
    'product' => ProductScreen(id: id),
    'scan' => const BarcodeScanScreen(title: 'Contar: escanea el producto'),
    'count' || 'stockin' || 'kardex' => FutureBuilder<Map<String, dynamic>>(
      future: session.api.get('/products/$id'),
      builder: (context, snap) => !snap.hasData
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : screen == 'kardex'
          ? MovementsScreen(product: snap.data!)
          : StockMoveScreen(product: snap.data!, operation: screen == 'count' ? 'adjustment' : 'in', chained: screen == 'count'),
    ),
    'notifications' => const NotificationsScreen(),
    'profile' => const ProfileScreen(),
    'editor' => FutureBuilder<Map<String, dynamic>>(
      future: session.api.get('/consultations/$id'),
      builder: (context, snap) =>
          snap.hasData ? ConsultationEditor(id: id, initial: snap.data!) : const Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
    'waiting' => const WaitingRoomScreen(),
    'clients' => const ClientSearchScreen(),
    'client' => ClientScreen(id: id),
    'walkin' => const WalkInScreen(),
    'schedule' => FutureBuilder<Map<String, dynamic>>(
      future: session.api.get('/pets/$id'),
      builder: (context, snap) =>
          snap.hasData ? AppointmentFormScreen(pet: snap.data!) : const Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
    'reschedule' => FutureBuilder<Map<String, dynamic>>(
      future: session.api.get('/appointments/$id'),
      builder: (context, snap) =>
          snap.hasData ? AppointmentFormScreen(appointment: snap.data!) : const Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
    'petform' => FutureBuilder<Map<String, dynamic>>(
      future: session.api.get('/pets/$id'),
      builder: (context, snap) => snap.hasData
          ? PetFormScreen(client: snap.data!['client'] as Map<String, dynamic>, pet: snap.data!)
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
    'lab' => const LabScreen(),
    'labrequest' => LabRequestScreen(id: id),
    'labform' => const LabRequestForm(),
    'labresults' => FutureBuilder<Map<String, dynamic>>(
      future: session.api.get('/lab/$id'),
      builder: (context, snap) =>
          snap.hasData ? LabResultsEditor(lab: snap.data!) : const Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
    'drawer' => AppShell(key: shellKey),
    _ => const AppShell(),
  };

  runApp(
    ChangeNotifierProvider.value(
      value: session,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // ?toast=success|error|info muestra un aviso encima de la pantalla.
        home: params['toast'] == null
            ? home
            : Builder(
                builder: (context) {
                  // Fijo: el navegador sin ventana toma la foto cuando quiere.
                  Future.delayed(const Duration(milliseconds: 1500), () {
                    if (!context.mounted) return;
                    final (text, kind) = switch (params['toast']) {
                      'error' => ('El profesional ya tiene una cita a esa hora.', ToastKind.error),
                      'info' => ('Subiendo la foto…', ToastKind.info),
                      'offline' => ('Sin conexión con el servidor. Revisa tu internet.', ToastKind.offline),
                      _ => ('Cita confirmada. Se avisó al propietario.', ToastKind.success),
                    };
                    showToast(context, text, kind: kind, duration: const Duration(minutes: 5));
                  });
                  return home;
                },
              ),
      ),
    ),
  );
}
