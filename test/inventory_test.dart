import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vexi_movil/screens/inventory_screens.dart';

import 'app_test.dart' show json;
import 'screens_test.dart' show app, sessionWith;

const _perms = ['products.view', 'inventory.view', 'inventory.create'];

Map<String, dynamic> _product({bool batches = false}) => {
  'id': 7,
  'code': 'BRV20',
  'barcode': '7791234567890',
  'name': 'Bravecto 20 kg',
  'presentation': 'Comprimido',
  'unit': 'unidad',
  'sale_price': 250,
  'min_stock': 2,
  'stock': 8,
  'track_batches': batches,
  'by_branch': [
    {'branch_id': 1, 'branch': 'Central', 'quantity': 8},
  ],
  'batches': batches
      ? [
          {'id': 31, 'lot': 'A1', 'expires_at': '2027-05-01', 'quantity': 5, 'branch_id': 1, 'days_left': 170},
          {'id': 32, 'lot': 'B2', 'expires_at': '2027-09-01', 'quantity': 3, 'branch_id': 1, 'days_left': 290},
        ]
      : [],
};

Map<String, dynamic> _options() => {
  'operations': [],
  'branches': [
    {'id': 1, 'name': 'Central'},
  ],
  'in_reasons': [
    {'key': 'purchase', 'label': 'Compra'},
  ],
  'out_reasons': [
    {'key': 'loss', 'label': 'Merma / rotura'},
  ],
};

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('el conteo muestra la diferencia con el sistema y sigue con el próximo producto', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return json(_product(), 201);
      }
      return json(_options());
    });
    final session = sessionWith(client, permissions: _perms, features: ['inventario']);

    String? result;
    await tester.pumpWidget(
      app(
        session,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await Navigator.of(context).push<String>(
              MaterialPageRoute(
                builder: (_) => StockMoveScreen(product: _product(), operation: 'adjustment', chained: true),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Según el sistema: 8 unidad'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Cantidad contada'), '7');
    await tester.pump();
    expect(find.text('Diferencia: -1 unidad'), findsOneWidget);

    await tester.tap(find.text('Guardar y escanear otro'));
    await tester.pumpAndSettle();
    expect(sent, containsPair('operation', 'adjustment'));
    expect(sent!['quantity'], 7);
    expect(sent!['branch_id'], 1);
    expect(result, 'next');
    expect(find.text('Bravecto 20 kg: ajustado -1.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('con lotes, el conteo es por lote y compara con lo de ese lote', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return json(_product(batches: true), 201);
      }
      return json(_options());
    });
    final session = sessionWith(client, permissions: _perms, features: ['inventario']);
    await tester.pumpWidget(app(session, StockMoveScreen(product: _product(batches: true), operation: 'adjustment')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Según el sistema'), findsNothing); // primero el lote
    await tester.tap(find.text('Lote contado'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Lote B2').last);
    await tester.pumpAndSettle();
    expect(find.text('Según el sistema: 3 unidad'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Cantidad contada'), '3');
    await tester.pump();
    expect(find.text('Coincide con el sistema.'), findsOneWidget);
    await tester.tap(find.text('Guardar conteo'));
    await tester.pumpAndSettle();
    expect(sent!['product_batch_id'], 32);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('la ficha del producto ofrece contar, entrada y salida, y el kardex', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    final client = MockClient((request) async {
      if (request.url.path.endsWith('/movements')) {
        return json({
          'data': [
            {
              'id': 3,
              'created_at': '2026-11-12T10:00:00-04:00',
              'type_badge': {'label': 'Ajuste', 'color': 'warning'},
              'reason': 'Inventario físico',
              'quantity': -1,
              'balance_after': 7,
              'branch': 'Central',
              'user': 'Ana',
            },
          ],
          'meta': {'total': 1},
        });
      }
      return json(_product());
    });
    final session = sessionWith(client, permissions: _perms, features: ['inventario']);
    await tester.pumpWidget(app(session, const ProductScreen(id: 7)));
    await tester.pumpAndSettle();

    expect(find.text('7791234567890'), findsOneWidget);
    expect(find.text('Contar'), findsOneWidget);
    expect(find.text('Entrada'), findsOneWidget);
    expect(find.text('Salida'), findsOneWidget);

    await tester.tap(find.byTooltip('Movimientos (kardex)'));
    await tester.pumpAndSettle();
    expect(find.text('Kardex · Bravecto 20 kg'), findsOneWidget);
    expect(find.text('-1'), findsOneWidget);
    expect(find.text('saldo 7'), findsOneWidget);
  });

  testWidgets('sin permiso de movimientos solo se consulta', (tester) async {
    final client = MockClient((request) async => json(_product()));
    final session = sessionWith(client, permissions: const ['products.view'], features: ['inventario']);
    await tester.pumpWidget(app(session, const ProductScreen(id: 7)));
    await tester.pumpAndSettle();

    expect(find.text('Contar'), findsNothing);
    expect(find.byTooltip('Movimientos (kardex)'), findsNothing);
  });
}
