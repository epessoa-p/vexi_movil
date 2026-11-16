import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vexi_movil/ui/common.dart';

void main() {
  testWidgets('sin logo propio, la veterinaria muestra el dibujo de Vexi', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CompanyLogo(url: null))));
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, 'assets/brand/vexi_mark.png');
  });

  testWidgets('con logo propio, se usa el de la veterinaria', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CompanyLogo(url: 'https://vexi.test/storage/logo.png'))));
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, 'https://vexi.test/storage/logo.png');
  });
}
