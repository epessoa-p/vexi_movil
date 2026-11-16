import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vexi_movil/screens/vaccine_screens.dart';

import 'app_test.dart' show json;
import 'screens_test.dart' show app, sessionWith;

const _perms = ['pets.view', 'vaccinations.view', 'vaccinations.create', 'vaccinations.edit', 'vaccinations.delete'];

const _reminder = 'https://wa.me/59170000001?text=Hola';

Map<String, dynamic> _deworming({bool pending = true}) => {
  'id': 5,
  'kind': 'deworming',
  'name': 'Desparasitación Externa',
  'type': 'external',
  'product': 'Pipeta X',
  'dose': '1 pipeta',
  'weight': 12.5,
  'applied_at': '2026-11-11',
  'next_due_at': '2026-12-11',
  'veterinarian': 'Laura Vet',
  'notes': null,
  'pending': pending,
  'whatsapp_reminder': pending ? _reminder : null,
};

Map<String, dynamic> _pet({List<Map<String, dynamic>> dewormings = const []}) => {
  'id': 3,
  'name': 'Toby',
  'health': {'vaccinations': [], 'dewormings': dewormings},
};

Map<String, dynamic> _options() => {
  'types': [
    {'key': 'internal', 'label': 'Interna', 'interval_days': 90},
    {'key': 'external', 'label': 'Externa', 'interval_days': 30},
    {'key': 'both', 'label': 'Interna y externa', 'interval_days': 30},
  ],
  'professionals': [],
  'product_suggestions': ['Pipeta X'],
  'inventory_products': [],
  'last_weight': 12.5,
};

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  Future<void> tab(WidgetTester tester, Map<String, dynamic> pet, MockClient client) async {
    tester.view.physicalSize = const Size(1080, 3200);
    addTearDown(tester.view.reset);
    final session = sessionWith(client, permissions: _perms, features: ['vacunas']);
    await tester.pumpWidget(
      app(
        session,
        Scaffold(
          body: PetHealthTab(pet: pet, reload: () async {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('la pendiente se ve arriba con el recordatorio; el detalle permite recordar, corregir y eliminar', (tester) async {
    final deletes = <String>[];
    final client = MockClient((request) async {
      if (request.method == 'DELETE') deletes.add(request.url.path);
      return json({'deleted': true});
    });
    await tab(tester, _pet(dewormings: [_deworming()]), client);

    expect(find.text('PENDIENTES'), findsOneWidget);
    expect(find.text('Compartir carnet sanitario (PDF)'), findsOneWidget);
    // Una sola vez: en «Pendientes»; en el historial no se repite el botón.
    expect(find.byTooltip('Recordar por WhatsApp'), findsOneWidget);

    await tester.tap(find.text('Desparasitación Externa').last);
    await tester.pumpAndSettle();
    expect(find.text('1 pipeta · 12,5 kg'), findsOneWidget);
    expect(find.text('Próxima: ${'11 de dic 2026'}'), findsOneWidget);
    expect(find.text('Recordar por WhatsApp'), findsOneWidget);
    expect(find.text('Corregir'), findsOneWidget);

    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar esta desparasitación?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();
    expect(deletes, ['/api/v1/dewormings/5']);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('registrar una desparasitación propone el peso y muestra la próxima automática', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    addTearDown(tester.view.reset);

    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return json(_deworming(), 201);
      }
      return json(_options());
    });
    final session = sessionWith(client, permissions: _perms, features: ['vacunas']);
    await tester.pumpWidget(app(session, const DewormScreen(petId: 3, petName: 'Toby')));
    await tester.pumpAndSettle();

    expect(find.text('Desparasitar a Toby'), findsOneWidget);
    expect(find.text('12,5'), findsOneWidget); // peso actual de la mascota

    // Sin producto no se envía.
    await tester.tap(find.text('Registrar desparasitación'));
    await tester.pumpAndSettle();
    expect(find.text('Anota el producto que se aplicó.'), findsOneWidget);
    expect(sent, isNull);

    await tester.tap(find.text('Externa'));
    await tester.pumpAndSettle();
    expect(find.textContaining('En 30 días:'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Producto aplicado'), 'Pipeta X');
    await tester.tap(find.text('No programar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar desparasitación'));
    await tester.pumpAndSettle();

    expect(sent!['type'], 'external');
    expect(sent!['product'], 'Pipeta X');
    expect(sent!['weight'], 12.5);
    expect(sent!['no_next_due'], true);
    expect(sent!.containsKey('next_due_at'), isFalse);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('corregir una vacuna envía PUT con la fecha de la próxima dosis que ya tenía', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    addTearDown(tester.view.reset);

    final calls = <String>[];
    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}?${request.url.query}');
      if (request.method == 'PUT') {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return json({'id': 9});
      }
      return json({
        'vaccines': [
          {'id': 1, 'name': 'Polivalente', 'protocol': '3 dosis cada 21 días', 'suggested_dose': 2},
        ],
        'professionals': [],
      });
    });
    final session = sessionWith(client, permissions: _perms, features: ['vacunas']);
    final record = {
      'id': 9,
      'kind': 'vaccine',
      'name': 'Polivalente',
      'vaccine_id': 1,
      'dose_number': 1,
      'lot': 'L-1',
      'applied_at': '2026-11-01',
      'next_due_at': '2026-11-22',
    };
    await tester.pumpWidget(app(session, VaccinateScreen(petId: 3, petName: 'Toby', record: record)));
    await tester.pumpAndSettle();

    expect(find.text('Corregir vacuna'), findsOneWidget);
    expect(calls.first, 'GET /api/v1/pets/3/vaccination-options?vaccination_id=9');
    expect(find.text('L-1'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'L-1'), 'L-77');
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    expect(calls.last, startsWith('PUT /api/v1/vaccinations/9'));
    expect(sent!['lot'], 'L-77');
    expect(sent!['dose_number'], 1); // al corregir no cambia sola la dosis
    expect(sent!['next_due_at'], '2026-11-22');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
