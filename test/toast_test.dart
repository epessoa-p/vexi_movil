import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vexi_movil/core/api_client.dart';
import 'package:vexi_movil/ui/common.dart';

void main() {
  Future<BuildContext> host(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    return ctx;
  }

  testWidgets('el aviso aparece arriba y se va solo', (tester) async {
    final context = await host(tester);

    showDone(context, 'Cita confirmada.');
    await tester.pumpAndSettle();
    expect(find.text('Cita confirmada.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.getTopLeft(find.text('Cita confirmada.')).dy, lessThan(100)); // arriba, no abajo

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Cita confirmada.'), findsNothing);
  });

  testWidgets('los errores duran más, se cierran al tocarlos y el nuevo reemplaza al anterior', (tester) async {
    final context = await host(tester);

    showError(context, ApiException(422, 'La cita ya está cerrada.'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.error_rounded), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('La cita ya está cerrada.'), findsOneWidget); // sigue visible

    await tester.tap(find.text('La cita ya está cerrada.'));
    await tester.pumpAndSettle();
    expect(find.text('La cita ya está cerrada.'), findsNothing);

    showInfo(context, 'Subiendo la foto…');
    await tester.pumpAndSettle();
    showDone(context, 'Foto actualizada.');
    await tester.pumpAndSettle();
    expect(find.text('Subiendo la foto…'), findsNothing);
    expect(find.text('Foto actualizada.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
