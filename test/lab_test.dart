import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vexi_movil/screens/lab_screens.dart';
import 'package:vexi_movil/screens/shell.dart';

import 'app_test.dart' show json;
import 'screens_test.dart' show app, sessionWith;

const _perms = ['lab_requests.view', 'lab_requests.create', 'lab_requests.edit', 'lab_results.edit'];

Map<String, dynamic> _detail({String status = 'in_process', bool editable = true, List<String> actions = const ['cancel']}) => {
  'id': 7,
  'code': 'L-000007',
  'study': 'Hemograma',
  'category': 'Hematología',
  'status': status,
  'status_badge': {'label': status == 'completed' ? 'Completado' : 'En proceso', 'color': 'info'},
  'requested_at': '2026-11-11T10:00:00-04:00',
  'requester': 'Laura Vet',
  'out_of_range': 1,
  'editable': editable,
  'actions': actions,
  'report_available': status == 'completed',
  'pet': {'id': 3, 'name': 'Nube', 'species': 'Felino'},
  'timeline': [
    {'label': 'Solicitado', 'at': '2026-11-11T10:00:00-04:00'},
  ],
  'results': [
    {'name': 'Hematocrito', 'value': '30', 'unit': '%', 'reference': '37 – 55', 'flag': 'low'},
    {'name': 'Leucocitos', 'value': '12', 'unit': 'x10³/µL', 'reference': '6 – 17', 'flag': 'normal'},
  ],
  'rows': [
    {'name': 'Hematocrito', 'value': '30', 'unit': '%', 'reference_min': 37, 'reference_max': 55, 'reference_text': null},
    {'name': 'Leucocitos', 'value': null, 'unit': 'x10³/µL', 'reference_min': 6, 'reference_max': 17, 'reference_text': null},
  ],
  'attachments': [
    {'id': 1, 'name': 'informe.pdf', 'mime_type': 'application/pdf', 'is_image': false, 'path': '/lab/7/attachments/1'},
  ],
};

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('el detalle marca los valores fuera de rango y entrega el estudio completado', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    addTearDown(tester.view.reset);

    final posts = <String>[];
    final client = MockClient((request) async {
      if (request.method == 'POST') posts.add(request.url.path);
      return json(_detail(status: 'completed', editable: false, actions: ['deliver', 'cancel']));
    });
    final session = sessionWith(client, permissions: _perms, features: ['laboratorio']);

    await tester.pumpWidget(app(session, const LabRequestScreen(id: 7)));
    await tester.pumpAndSettle();

    expect(find.text('1 valor fuera del rango de referencia.'), findsOneWidget);
    expect(find.text('Bajo'), findsOneWidget); // solo el hematocrito
    expect(find.text('30 %'), findsOneWidget);
    expect(find.text('Ref. 37 – 55'), findsOneWidget);
    expect(find.text('informe.pdf'), findsOneWidget);
    expect(find.byTooltip('Compartir informe (PDF)'), findsOneWidget);
    // Cerrado: ni cargar resultados ni adjuntar.
    expect(find.text('Editar resultados'), findsNothing);
    expect(find.text('Adjuntar foto'), findsNothing);

    await tester.tap(find.text('Marcar entregado al propietario'));
    await tester.pumpAndSettle();
    expect(posts, ['/api/v1/lab/7/deliver']);
  });

  testWidgets('cargar resultados avisa el rango al escribir y envía las filas con su referencia', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    addTearDown(tester.view.reset);

    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/options')) {
        return json({
          'study_types': [],
          'professionals': [
            {'id': 4, 'name': 'Laura Vet'},
          ],
        });
      }
      if (request.method == 'PUT') sent = jsonDecode(request.body) as Map<String, dynamic>;
      return json(_detail());
    });
    final session = sessionWith(client, permissions: _perms, features: ['laboratorio']);

    await tester.pumpWidget(
      app(
        session,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LabResultsEditor(lab: _detail()))),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Ref. 37 – 55'), findsOneWidget);
    expect(find.text('Bajo'), findsOneWidget); // 30 < 37

    await tester.enterText(find.widgetWithText(TextField, 'Valor').last, '19');
    await tester.pump();
    expect(find.text('Alto'), findsOneWidget);

    await tester.tap(find.text('Agregar parámetro'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Parámetro'), 'Plaquetas');
    await tester.enterText(find.widgetWithText(TextField, 'Valor').last, '250');
    await tester.enterText(find.widgetWithText(TextField, 'Observaciones'), 'Anemia leve');

    await tester.tap(find.text('Completar estudio'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Completar'));
    await tester.pumpAndSettle();

    expect(sent!['finish'], isTrue);
    expect(sent!['result_notes'], 'Anemia leve');
    expect(sent!['responsible_id'], 4);
    expect(sent!['results'], [
      {'name': 'Hematocrito', 'value': '30', 'unit': '%', 'reference_min': 37.0, 'reference_max': 55.0, 'reference_text': null},
      {'name': 'Leucocitos', 'value': '19', 'unit': 'x10³/µL', 'reference_min': 6.0, 'reference_max': 17.0, 'reference_text': null},
      {'name': 'Plaquetas', 'value': '250', 'unit': null, 'reference_min': null, 'reference_max': null, 'reference_text': null},
    ]);
    expect(find.byType(LabResultsEditor), findsNothing); // volvió al detalle
  });

  testWidgets('solicitar varios estudios desde la consulta', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    addTearDown(tester.view.reset);

    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/lab/options')) {
        return json({
          'study_types': [
            {'id': 1, 'name': 'Hemograma', 'category_label': 'Hematología'},
            {'id': 2, 'name': 'Perfil renal', 'category_label': 'Bioquímica'},
            {'id': 3, 'name': 'Radiografía', 'category_label': 'Imagen'},
          ],
          'professionals': [],
        });
      }
      if (request.method == 'POST') {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return json({
          'data': [
            {'id': 8},
            {'id': 9},
          ],
        }, 201);
      }
      return http.Response('{}', 404);
    });
    final session = sessionWith(client, permissions: _perms, features: ['laboratorio']);

    bool? result;
    await tester.pumpWidget(
      app(
        session,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await requestLabFor(context, {
                'id': 21,
                'pet': {'id': 3, 'name': 'Nube'},
              }),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Ligado a la consulta'), findsOneWidget);
    await tester.tap(find.text('Hemograma'));
    await tester.tap(find.text('Perfil renal'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Laboratorio externo (opcional)'), 'Lab Central');
    await tester.tap(find.text('Solicitar 2 estudios'));
    await tester.pumpAndSettle();

    expect(sent!['pet_id'], 3);
    expect(sent!['consultation_id'], 21);
    expect(sent!['study_types'], [1, 2]);
    expect(sent!['external_lab'], 'Lab Central');
    expect(result, isTrue);
  });

  testWidgets('el drawer muestra Laboratorio solo con el módulo', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final empty = MockClient((request) async => json({'data': [], 'alerts': [], 'today': null}));

    for (final (features, expected) in [
      (['laboratorio'], findsOneWidget),
      (<String>[], findsNothing),
    ]) {
      await tester.pumpWidget(app(sessionWith(empty, permissions: _perms, features: features), AppShell(key: UniqueKey())));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Menú').first);
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(NavigationDrawer), matching: find.text('Laboratorio')), expected);
    }
  });
}
