import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:vexi_movil/core/api_client.dart';
import 'package:vexi_movil/core/models.dart';
import 'package:vexi_movil/core/session.dart';
import 'package:vexi_movil/screens/consultation_screens.dart';
import 'package:vexi_movil/screens/shell.dart';

import 'app_test.dart' show MemoryStore, json;

Session sessionWith(MockClient client, {List<String> permissions = const [], List<String> features = const []}) {
  final session = Session(
    ApiClient(baseUrl: 'https://vexi.test/api/v1', httpClient: client),
    store: MemoryStore(),
  );
  session.profile = Profile.fromJson({
    'user': {'id': 4, 'name': 'Laura Vet', 'email': 'vet@demo.test'},
    'company': {'id': 1, 'name': 'Veterinaria Demo'},
    'companies': [
      {'id': 1, 'name': 'Veterinaria Demo'},
    ],
    'permissions': permissions,
    'plan': {'name': 'Pro', 'features': features},
  });
  session.status = SessionStatus.ready;
  return session;
}

Widget app(Session session, Widget home) => ChangeNotifierProvider.value(
  value: session,
  child: MaterialApp(home: home),
);

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('el drawer muestra solo las secciones del plan y del rol', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final empty = MockClient((request) async => json({'data': [], 'alerts': [], 'today': null}));
    final session = sessionWith(empty, permissions: ['pets.view', 'products.view'], features: ['inventario']);

    await tester.pumpWidget(app(session, const AppShell()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menú').first);
    await tester.pumpAndSettle();

    final drawer = find.byType(NavigationDrawer);
    expect(find.descendant(of: drawer, matching: find.text('Pacientes')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('Inventario')), findsOneWidget);
    // Sin el módulo de agenda ni el de hospitalización en el plan.
    expect(find.descendant(of: drawer, matching: find.text('Agenda')), findsNothing);
    expect(find.descendant(of: drawer, matching: find.text('Hospitalización')), findsNothing);
    expect(find.text('Cerrar sesión'), findsOneWidget);

    await tester.tap(find.descendant(of: drawer, matching: find.text('Inventario')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Inventario'), findsOneWidget);
  });

  testWidgets('el editor envía la consulta y finaliza tras confirmar', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    addTearDown(tester.view.reset);

    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/options')) {
        return json({
          'hydration': [
            {'key': 'normal', 'label': 'Normal'},
          ],
          'diagnosis_types': [
            {'key': 'primary', 'label': 'Principal'},
          ],
          'routes': [
            {'key': 'oral', 'label': 'Oral'},
          ],
          'diagnosis_suggestions': [],
          'medication_suggestions': [],
        });
      }
      if (request.method == 'PUT') sent = jsonDecode(request.body) as Map<String, dynamic>;
      return json({'id': 9, 'is_open': false});
    });
    final session = sessionWith(client, permissions: ['consultations.edit'], features: ['consultas']);

    await tester.pumpWidget(
      app(
        session,
        const ConsultationEditor(
          id: 9,
          initial: {
            'id': 9,
            'is_open': true,
            'pet': {'name': 'Firulais'},
            'form': {
              'reason': 'Vómitos',
              'diagnoses': [
                {'type': 'primary', 'description': 'Gastritis'},
              ],
              'prescription': [],
            },
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Temperatura'), '39,5');
    await tester.tap(find.text('Finalizar consulta'));
    await tester.pumpAndSettle();
    expect(find.text('¿Finalizar la consulta?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Finalizar'));
    await tester.pumpAndSettle();

    expect(sent!['finish'], isTrue);
    expect(sent!['reason'], 'Vómitos');
    expect(sent!['temperature'], 39.5);
    expect(sent!['diagnoses'], [
      {'type': 'primary', 'description': 'Gastritis', 'notes': null},
    ]);
  });
}
