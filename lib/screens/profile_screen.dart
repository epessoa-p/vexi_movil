import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'notifications_screen.dart';
import 'shell.dart';

/// Perfil (§17.8): datos, veterinaria activa, contraseña y cierre de sesión.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _switchCompany(BuildContext context) async {
    final session = context.read<Session>();
    final companies = session.profile!.companies;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Cambiar de veterinaria', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final c in companies)
              ListTile(
                leading: const Icon(Icons.local_hospital_outlined),
                title: Text(c.name),
                trailing: c.id == session.profile!.company?.id ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, c.id),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen == session.profile!.company?.id) return;
    try {
      await session.chooseCompany(chosen);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text('Tendrás que volver a ingresar tu correo y contraseña.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cerrar sesión')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      await context.read<Session>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(leading: shellMenuButton(context), title: const Text('Mi perfil')),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: scheme.primaryContainer,
              child: Text(
                profile.name.isEmpty ? '?' : profile.name[0].toUpperCase(),
                style: TextStyle(fontSize: 32, color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text(profile.name, style: Theme.of(context).textTheme.titleLarge)),
          Center(
            child: Text(profile.email, style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 16),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.local_hospital_outlined),
            title: Text(profile.company?.name ?? ''),
            subtitle: Text(
              [if (profile.planName != null) 'Plan ${profile.planName}', profile.subscriptionLabel].whereType<String>().join(' · '),
            ),
            trailing: profile.companies.length > 1 ? const Text('Cambiar') : null,
            onTap: profile.companies.length > 1 ? () => _switchCompany(context) : null,
          ),
          if (!profile.allowsWrite)
            ListTile(
              leading: Icon(Icons.info_outline, color: toneColor(context, 'warning')),
              title: const Text('Suscripción vencida: puedes consultar, pero no registrar cambios hasta renovarla.'),
            ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notificaciones'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Cambiar contraseña'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PasswordScreen())),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: scheme.error),
            title: Text('Cerrar sesión', style: TextStyle(color: scheme.error)),
            onTap: () => _logout(context),
          ),
        ],
      ),
    );
  }
}

class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  ApiException? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text != _confirm.text) {
      setState(() => _error = ApiException(422, '', fieldErrors: {'password': 'Las contraseñas nuevas no coinciden.'}));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final json = await context.session.api.put('/me/password', {
        'current_password': _current.text,
        'password': _password.text,
        'password_confirmation': _confirm.text,
      });
      if (!mounted) return;
      showDone(context, json['message'] as String? ?? 'Contraseña actualizada.');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cambiar contraseña')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _current,
            obscureText: true,
            decoration: InputDecoration(labelText: 'Contraseña actual', errorText: _error?.field('current_password')),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Nueva contraseña',
              helperText: 'Mínimo 8 caracteres.',
              errorText: _error?.field('password'),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Repite la nueva contraseña'),
          ),
          const SizedBox(height: 8),
          Text('Por seguridad, se cerrará tu sesión en los demás dispositivos.', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: _saving
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
