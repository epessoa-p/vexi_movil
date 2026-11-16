import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vexi_movil/screens/finance_screens.dart';
import 'package:vexi_movil/screens/home_screen.dart';

import 'app_test.dart' show json;
import 'screens_test.dart' show app, sessionWith;

const _owner = ['sales.view', 'sales.create', 'reports.finance'];
const _features = ['pos', 'caja', 'estadisticas'];

Map<String, dynamic> _sale() => {
  'id': 41,
  'code': 'V-000041',
  'created_at': '2026-10-02T10:00:00-04:00',
  'due_date': '2026-11-01',
  'overdue': true,
  'total': 500,
  'paid': 200,
  'balance': 300,
  'pet': 'Luna',
  'items': [
    {'description': 'Cirugía', 'quantity': 1, 'total': 500},
  ],
  'payments': [
    {'id': 1, 'paid_at': '2026-10-02T10:00:00-04:00', 'amount': 200, 'method': 'Efectivo', 'kind': 'sale'},
  ],
};

Map<String, dynamic> _options({List<Map<String, dynamic>>? sessions}) => {
  'methods': [
    {'id': 1, 'name': 'Efectivo', 'type': 'cash', 'requires_reference': false},
    {'id': 2, 'name': 'Transferencia', 'type': 'transfer', 'requires_reference': true},
  ],
  'cash_enabled': true,
  'sessions':
      sessions ??
      [
        {'id': 9, 'name': 'Caja 1'},
      ],
};

final _vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('el inicio muestra al dueño lo que entró y lo que le deben', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    final client = MockClient(
      (request) async => json({
        'greeting': 'Buenos días',
        'alerts': [],
        'finance': {
          'today': 380,
          'sales_today': 2,
          'month': 4250.5,
          'month_delta': {'pct': 12.0, 'direction': 'up', 'tone': 'good'},
          'receivable': 400,
          'receivable_overdue': 300,
          'report': true,
        },
      }),
    );
    final session = sessionWith(client, permissions: _owner, features: _features);
    await tester.pumpWidget(app(session, const HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Cobrado hoy'), findsOneWidget);
    expect(find.text('380.00'), findsOneWidget);
    expect(find.text('2 ventas hoy'), findsOneWidget);
    expect(find.text('4,250.50'), findsOneWidget);
    expect(find.text('12 %'), findsOneWidget);
    expect(find.text('Te deben 400.00'), findsOneWidget);
    expect(find.text('300.00 vencido'), findsOneWidget);
  });

  testWidgets('el resumen muestra las cifras del período y cambia de período', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    final presets = <String?>[];
    final client = MockClient((request) async {
      presets.add(request.url.queryParameters['preset']);
      return json({
        'period': {'preset': 'this_month', 'label': '1 nov – 12 nov 2026', 'previous_label': 'los mismos días del mes anterior'},
        'presets': [
          {'key': 'this_month', 'label': 'Este mes'},
          {'key': 'last_month', 'label': 'Mes pasado'},
        ],
        'branches': [],
        'insights': [
          {'icon': 'graph-up-arrow', 'text': 'Ingresaste Bs 380.00, 12 % más que los mismos días del mes anterior.'},
        ],
        'totals': {'income': 380, 'cost': 50, 'expenses': 0, 'profit': -20},
        'deltas': {
          'income': {'pct': 12.0, 'direction': 'up', 'tone': 'good'},
          'profit': {'pct': -40.0, 'direction': 'down', 'tone': 'bad'},
        },
        'with_expenses': true,
        'chart': {
          'labels': ['1 nov', '2 nov', '3 nov'],
          'income': [0, 300, 80],
          'expenses': [0, 0, 0],
        },
        'sales': {
          'total': 500,
          'count': 2,
          'ticket': 250,
          'deltas': {},
          'top': [
            {'label': 'Consulta general', 'value': 300, 'quantity': 1, 'share': 60},
          ],
        },
        'clinic': null,
        'by_method': [
          {'label': 'Efectivo', 'value': 380, 'share': 100},
        ],
        'expenses_by_category': [],
        'receivable': 120,
        'receivable_overdue': 0,
        'payable': null,
      });
    });
    final session = sessionWith(client, permissions: _owner, features: _features);
    await tester.pumpWidget(app(session, const SummaryScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ingresaste Bs 380.00'), findsOneWidget);
    expect(find.text('Utilidad estimada'), findsOneWidget);
    expect(find.text('40 %'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Consulta general'), 300, scrollable: _vertical);
    expect(find.text('Consulta general'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Te deben'), 300, scrollable: _vertical);
    expect(find.text('Te deben'), findsOneWidget);
    expect(find.text('120.00'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Mes pasado'), -300, scrollable: _vertical);
    await tester.tap(find.text('Mes pasado'));
    await tester.pumpAndSettle();
    expect(presets, ['this_month', 'last_month']);
  });

  testWidgets('abono: la referencia la exige el servidor y al final ofrece el recibo', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    final sent = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        sent.add(body);
        if (body['payment_method_id'] == 2 && body['reference'] == null) {
          return json({
            'message': 'El pago con Transferencia necesita un número de referencia.',
            'errors': {
              'reference': ['El pago con Transferencia necesita un número de referencia.'],
            },
          }, 422);
        }
        return json({
          'amount': 100,
          'sale': _sale(),
          'client_balance': 300,
          'whatsapp_receipt': 'https://wa.me/59170011222?text=hola',
        }, 201);
      }
      if (request.url.path.endsWith('/payments/options')) return json(_options());
      return json({
        'client': {'id': 5, 'name': 'Ana Pérez', 'phone': '70011222'},
        'balance': 400,
        'overdue_balance': 300,
        'whatsapp_reminder': 'https://wa.me/59170011222?text=saldo',
        'sales': [_sale()],
      });
    });
    final session = sessionWith(client, permissions: _owner, features: _features);
    await tester.pumpWidget(app(session, const ClientDebtScreen(clientId: 5, name: 'Ana Pérez')));
    await tester.pumpAndSettle();

    expect(find.text('400.00'), findsOneWidget);
    expect(find.text('Vencida'), findsOneWidget);
    expect(find.text('Recordar por WhatsApp'), findsOneWidget);

    await tester.tap(find.text('Registrar abono'));
    await tester.pumpAndSettle();
    expect(find.text('Se registra en Caja 1.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Monto'), '100');
    await tester.tap(find.text('Transferencia'));
    await tester.pumpAndSettle();
    expect(find.text('Número de referencia'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Registrar abono'));
    await tester.pumpAndSettle();
    expect(find.text('El pago con Transferencia necesita un número de referencia.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Número de referencia'), 'TRX-9');
    await tester.tap(find.widgetWithText(FilledButton, 'Registrar abono'));
    await tester.pumpAndSettle();
    expect(sent.last, {'amount': 100, 'payment_method_id': 2, 'reference': 'TRX-9', 'cash_session_id': 9});
    expect(find.text('Abono de 100.00 registrado'), findsOneWidget);
    expect(find.text('Ana Pérez todavía debe 300.00.'), findsOneWidget);
    expect(find.text('Enviar recibo'), findsOneWidget);

    await tester.tap(find.text('Listo'));
    await tester.pumpAndSettle();
    expect(find.text('Saldo pendiente'), findsOneWidget); // volvió a la cuenta del cliente
  });

  testWidgets('sin caja abierta no deja cobrar y lo explica', (tester) async {
    final client = MockClient((request) async => json(_options(sessions: [])));
    final session = sessionWith(client, permissions: _owner, features: _features);
    await tester.pumpWidget(app(session, PaymentScreen(sale: _sale(), clientName: 'Ana Pérez')));
    await tester.pumpAndSettle();

    expect(find.text('No hay ninguna caja abierta'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Registrar abono'));
    expect(button.onPressed, isNull);
    expect(find.widgetWithText(TextField, 'Monto'), findsOneWidget);
    expect(find.text('300'), findsOneWidget); // propone todo el saldo
  });
}
