import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vexi_movil/core/api_client.dart';
import 'package:vexi_movil/screens/consultation_screens.dart';

import 'app_test.dart' show json;
import 'screens_test.dart' show app, sessionWith;

const _options = {
  'hydration': [],
  'diagnosis_types': [
    {'key': 'primary', 'label': 'Principal'},
  ],
  'routes': [
    {'key': 'oral', 'label': 'Oral'},
  ],
  'professionals': [
    {'id': 4, 'name': 'Laura Vet'},
  ],
  'products': [
    {'id': 5, 'name': 'Jeringa 5 ml', 'presentation': null, 'unit': 'Unidad'},
    {'id': 6, 'name': 'Amoxicilina', 'presentation': '500 mg', 'unit': 'Comprimido'},
  ],
  'diagnosis_suggestions': [],
  'medication_suggestions': [],
};

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('leadingNumber toma la cantidad de un texto libre', () {
    expect(leadingNumber('14 comp.'), 14);
    expect(leadingNumber('1,5 ml'), 1.5);
    expect(leadingNumber('una caja'), isNull);
  });

  testWidgets('el editor conserva y envía procedimientos, insumos y el producto de la receta', (tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    addTearDown(tester.view.reset);

    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/options')) return json(_options);
      if (request.method == 'PUT') sent = jsonDecode(request.body) as Map<String, dynamic>;
      return json({'id': 9, 'is_open': true});
    });
    final session = sessionWith(client, permissions: ['consultations.edit'], features: ['consultas', 'inventario']);

    await tester.pumpWidget(
      app(
        session,
        const ConsultationEditor(
          id: 9,
          initial: {
            'id': 9,
            'is_open': true,
            'pet': {'name': 'Firulais'},
            'supplies': [
              {'product': 'Jeringa 5 ml', 'quantity': 2},
            ],
            'form': {
              'diagnoses': [],
              'prescription': [
                {'medication': 'Amoxicilina', 'dose': '1 comp.', 'route': 'oral', 'frequency': 'cada 12 h', 'product_id': 6},
              ],
              'procedures': [
                {'name': 'Sutura', 'materials': 'Nylon 3-0', 'medications': 'Lidocaína', 'performed_by': 4, 'cost': 80},
              ],
              'supplies': [
                {'product_id': 5, 'quantity': 2, 'notes': null},
              ],
            },
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jeringa 5 ml'), findsOneWidget);
    expect(find.text('Amoxicilina · 500 mg'), findsOneWidget); // vínculo al inventario
    await tester.enterText(find.widgetWithText(TextField, 'Cantidad').last, '3');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(sent!['procedures'], [
      {'name': 'Sutura', 'description': null, 'materials': 'Nylon 3-0', 'medications': 'Lidocaína', 'performed_by': 4, 'cost': 80},
    ]);
    expect(sent!['supplies'], [
      {'product_id': 5, 'quantity': 3, 'notes': null},
    ]);
    expect((sent!['prescription'] as List).single['product_id'], 6);
    expect(sent!['finish'], isFalse);
  });

  testWidgets('dispensar propone la cantidad recetada y la envía', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    addTearDown(tester.view.reset);

    final posts = <String, Object?>{};
    final client = MockClient((request) async {
      if (request.method == 'POST') posts[request.url.path] = jsonDecode(request.body);
      return json({
        'id': 9,
        'is_open': false,
        'prescription_number': 'R-000009',
        'pet': {'name': 'Firulais'},
        'status_badge': {'label': 'Finalizada', 'color': 'success'},
        'prescription': [
          {'id': 3, 'medication': 'Amoxicilina', 'dose': '1 comp.', 'quantity': '14 comp.', 'product_id': 6, 'dispensed_at': null},
        ],
        'procedures': [
          {'name': 'Sutura', 'performed_by': 'Laura Vet', 'cost': 80},
        ],
        'supplies': [
          {'product': 'Jeringa 5 ml', 'unit': 'Unidad', 'quantity': 2},
        ],
      });
    });
    final session = sessionWith(client, permissions: ['consultations.view', 'consultations.edit'], features: ['consultas', 'inventario']);

    await tester.pumpWidget(app(session, const ConsultationScreen(id: 9)));
    await tester.pumpAndSettle();

    expect(find.text('Receta R-000009'.toUpperCase()), findsOneWidget);
    expect(find.text('Sutura'), findsOneWidget);
    expect(find.text('2 Unidad'), findsOneWidget);
    expect(find.byTooltip('Compartir receta (PDF)'), findsOneWidget);

    await tester.tap(find.text('Dispensar'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Cantidad entregada'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Dispensar'));
    await tester.pumpAndSettle();

    expect(posts, {
      '/api/v1/consultations/9/prescription/3/dispense': {'quantity': 14},
    });
  });

  test('download devuelve los bytes y traduce los errores', () async {
    final api = ApiClient(
      baseUrl: 'https://vexi.test/api/v1',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/9/prescription.pdf')) {
          return http.Response.bytes(utf8.encode('%PDF-1.7'), 200, headers: {'content-type': 'application/pdf'});
        }
        return json({'code': 'permission_denied', 'message': 'Tu rol no tiene permiso.'}, 403);
      }),
    )..token = 't1';

    expect(utf8.decode(await api.download('/consultations/9/prescription.pdf')), '%PDF-1.7');
    await expectLater(
      api.download('/consultations/8/prescription.pdf'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'permission_denied')),
    );
  });
}
