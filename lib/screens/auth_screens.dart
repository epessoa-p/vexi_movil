import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/session.dart';
import '../ui/common.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: _Brand()));
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // El logo tiene partes transparentes pensadas para fondo claro: en modo oscuro va sobre una tarjeta blanca.
        Container(
          padding: dark ? const EdgeInsets.all(14) : EdgeInsets.zero,
          decoration: dark ? BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)) : null,
          child: Image.asset('assets/brand/vexi_logo.png', height: 150, semanticLabel: 'Vexi'),
        ),
        const SizedBox(height: 8),
        Text('Gestión veterinaria', style: TextStyle(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class OfflineScreen extends StatelessWidget {
  const OfflineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      body: Center(
        child: EmptyState(
          icon: Icons.wifi_off,
          message: session.notice ?? 'Sin conexión con el servidor.',
          action: Column(
            children: [
              FilledButton.icon(onPressed: session.restore, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
              TextButton(onPressed: session.logout, child: const Text('Cerrar sesión')),
            ],
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  ApiException? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<Session>().login(_email.text.trim(), _password.text, _deviceName());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _deviceName() => switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iPhone',
    _ => kIsWeb ? 'Navegador' : 'Escritorio',
  };

  @override
  Widget build(BuildContext context) {
    final notice = context.watch<Session>().notice;
    final general = _error != null && _error!.fieldErrors.isEmpty ? _error!.message : notice;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Brand(),
                      const SizedBox(height: 32),
                      if (general != null) ...[
                        Card(
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(general, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Correo',
                          prefixIcon: const Icon(Icons.mail_outline),
                          errorText: _error?.field('email'),
                        ),
                        validator: (v) => (v == null || !v.contains('@')) ? 'Escribe tu correo.' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'Escribe tu contraseña.' : null,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        child: _busy
                            ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                            : const Text('Ingresar'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '¿Olvidaste tu contraseña? Pídele al administrador de tu veterinaria que la restablezca.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CompanyPickerScreen extends StatefulWidget {
  const CompanyPickerScreen({super.key});

  @override
  State<CompanyPickerScreen> createState() => _CompanyPickerScreenState();
}

class _CompanyPickerScreenState extends State<CompanyPickerScreen> {
  int? _busy;

  Future<void> _choose(int id) async {
    setState(() => _busy = id);
    try {
      await context.read<Session>().chooseCompany(id);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final companies = session.profile?.companies ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Elige tu veterinaria'),
        actions: [TextButton(onPressed: session.logout, child: const Text('Salir'))],
      ),
      body: companies.isEmpty
          ? const EmptyState(
              icon: Icons.domain_disabled,
              message: 'Tu usuario no está activo en ninguna veterinaria. Habla con el administrador.',
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(
                    'Trabajas en varias veterinarias. ¿Con cuál entras ahora? Podrás cambiarla desde tu perfil.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                for (final c in companies)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.local_hospital_outlined)),
                    title: Text(c.name),
                    trailing: _busy == c.id
                        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.chevron_right),
                    onTap: _busy == null ? () => _choose(c.id) : null,
                  ),
              ],
            ),
    );
  }
}
