import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:vexi_movil/core/api_client.dart';
import 'package:vexi_movil/core/models.dart';
import 'package:vexi_movil/core/session.dart';
import 'package:vexi_movil/screens/auth_screens.dart';

class MemoryStore implements TokenStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async => value == null ? values.remove(key) : values[key] = value;
}

Map<String, dynamic> profileJson({List<Map<String, dynamic>>? companies, Map<String, dynamic>? company}) => {
  'user': {'id': 4, 'name': 'Laura Vet', 'email': 'vet@demo.test'},
  'is_super_admin': false,
  'company': company,
  'companies':
      companies ??
      [
        {'id': 1, 'name': 'Veterinaria Demo'},
      ],
  'permissions': company == null ? [] : ['appointments.view', 'pets.view'],
  'plan': company == null
      ? null
      : {
          'name': 'Pro',
          'features': ['agenda'],
        },
  'subscription': company == null ? null : {'status': 'active', 'label': 'Al día', 'allows_write': true},
};

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  group('Profile', () {
    test('combina plan y permiso como la web', () {
      final p = Profile.fromJson(profileJson(company: {'id': 1, 'name': 'Demo'}));
      expect(p.canUse('agenda', 'appointments.view'), isTrue);
      expect(p.canUse('vacunas', 'vaccinations.view'), isFalse); // falta el módulo
      expect(p.can('products.view'), isFalse);
    });
  });

  group('ApiClient', () {
    test('envía token y veterinaria, y traduce los errores con código', () async {
      late http.BaseRequest seen;
      final api =
          ApiClient(
              baseUrl: 'https://vexi.test/api/v1',
              httpClient: MockClient((request) async {
                seen = request;
                return json({'code': 'permission_denied', 'message': 'Tu rol no tiene permiso.'}, 403);
              }),
            )
            ..token = 'abc'
            ..companyId = 7;

      await expectLater(
        api.get('/appointments'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'permission_denied').having((e) => e.status, 'status', 403)),
      );
      expect(seen.headers['Authorization'], 'Bearer abc');
      expect(seen.headers['X-Company-Id'], '7');
    });

    test('expone los errores de validación por campo', () async {
      final api = ApiClient(
        baseUrl: 'https://vexi.test/api/v1',
        httpClient: MockClient(
          (_) async => json({
            'message': 'Datos inválidos',
            'errors': {
              'email': ['El correo o la contraseña no son correctos.'],
            },
          }, 422),
        ),
      );

      try {
        await api.post('/auth/login', {});
        fail('debía fallar');
      } on ApiException catch (e) {
        expect(e.field('email'), 'El correo o la contraseña no son correctos.');
      }
    });

    test('un 401 avisa para cerrar la sesión', () async {
      var expired = false;
      final api = ApiClient(baseUrl: 'https://vexi.test/api/v1', httpClient: MockClient((_) async => json({}, 401)))
        ..onUnauthorized = () => expired = true;

      await expectLater(api.get('/me'), throwsA(isA<ApiException>()));
      expect(expired, isTrue);
    });
  });

  group('Session', () {
    test('con una sola veterinaria entra directo y guarda el token', () async {
      final store = MemoryStore();
      final api = ApiClient(
        baseUrl: 'https://vexi.test/api/v1',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/login')) return json({'token': 't1', ...profileJson()});
          expect(request.headers['X-Company-Id'], '1');
          return json(profileJson(company: {'id': 1, 'name': 'Veterinaria Demo'}));
        }),
      );
      final session = Session(api, store: store);

      await session.login('vet@demo.test', 'secreta', 'test');

      expect(session.status, SessionStatus.ready);
      expect(session.profile!.company!.name, 'Veterinaria Demo');
      expect(store.values['vexi_token'], 't1');
      expect(store.values['vexi_company'], '1');
    });

    test('con varias veterinarias pide elegir', () async {
      final companies = [
        {'id': 1, 'name': 'Demo'},
        {'id': 2, 'name': 'Prueba'},
      ];
      final api = ApiClient(
        baseUrl: 'https://vexi.test/api/v1',
        httpClient: MockClient(
          (request) async => request.url.path.endsWith('/auth/login')
              ? json({'token': 't1', ...profileJson(companies: companies)})
              : json(profileJson(companies: companies)),
        ),
      );
      final session = Session(api, store: MemoryStore());

      await session.login('vet@demo.test', 'secreta', 'test');

      expect(session.status, SessionStatus.choosingCompany);
    });

    test('sin token guardado muestra el login', () async {
      final session = Session(ApiClient(httpClient: MockClient((_) async => json({}))), store: MemoryStore());
      await session.restore();
      expect(session.status, SessionStatus.signedOut);
    });
  });

  testWidgets('el login muestra el error del servidor junto al campo', (tester) async {
    final api = ApiClient(
      baseUrl: 'https://vexi.test/api/v1',
      httpClient: MockClient(
        (_) async => json({
          'message': 'x',
          'errors': {
            'email': ['El correo o la contraseña no son correctos.'],
          },
        }, 422),
      ),
    );
    final session = Session(api, store: MemoryStore())..status = SessionStatus.signedOut;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'vet@demo.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'mala');
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();

    expect(find.text('El correo o la contraseña no son correctos.'), findsOneWidget);
  });
}
