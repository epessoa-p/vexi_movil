import 'package:flutter/material.dart';

import '../core/models.dart';
import '../ui/common.dart';
import 'agenda_screens.dart';
import 'home_screen.dart';
import 'hospital_screens.dart';
import 'lab_screens.dart';
import 'shell.dart';

/// Campana (§17.1 / §17.8): pendientes en vivo y novedades con leído / no leído.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();

  Future<void> _readAll() async {
    try {
      await context.session.api.post('/notifications/read-all');
      _loader.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _open(Map<String, dynamic> n) async {
    final api = context.session.api;
    if (!n.flag('read')) {
      api.post('/notifications/${n['id']}/read').then((_) => _loader.currentState?.reload(), onError: (_) {});
    }

    final data = n.obj('data') ?? {};
    final Widget? target = switch (n.str('type')) {
      'appointment_assigned' ||
      'appointment_rescheduled' ||
      'appointment_cancelled' ||
      'patient_arrived' when data['appointment_id'] != null => AppointmentScreen(id: data['appointment_id'] as int),
      'hospitalization' when data['hospitalization_id'] != null => StayScreen(id: data['hospitalization_id'] as int),
      'lab_completed' when data['lab_request_id'] != null => LabRequestScreen(id: data['lab_request_id'] as int),
      _ => null,
    };
    if (target != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => target));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: shellMenuButton(context),
        title: const Text('Notificaciones'),
        actions: [TextButton(onPressed: _readAll, child: const Text('Marcar leídas'))],
      ),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => context.session.api.get('/notifications'),
        builder: (context, data, reload) {
          final alerts = data.list('alerts');
          final items = data.list('data');
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (alerts.isNotEmpty) ...[const SectionTitle('Requiere atención'), for (final a in alerts) AlertTile(alert: a)],
              const SectionTitle('Novedades'),
              if (items.isEmpty)
                const EmptyState(
                  icon: Icons.notifications_off_outlined,
                  message: 'Aquí verás cuando llegue tu paciente, te asignen o cancelen una cita, o estén listos unos resultados.',
                )
              else
                for (final n in items) _NotificationTile(n: n, onTap: () => _open(n)),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.onTap});

  final Map<String, dynamic> n;
  final VoidCallback onTap;

  static IconData _icon(String? type) => switch (type) {
    'appointment_assigned' => Icons.event_available,
    'appointment_rescheduled' => Icons.update,
    'appointment_cancelled' => Icons.event_busy,
    'patient_arrived' => Icons.meeting_room_outlined,
    'lab_completed' => Icons.science_outlined,
    'payment_received' => Icons.payments_outlined,
    _ => Icons.notifications_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final unread = !n.flag('read');
    final color = toneColor(context, n.str('tone'));
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: unread ? scheme.primaryContainer.withValues(alpha: .35) : Colors.transparent,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .14),
          child: Icon(_icon(n.str('type')), color: color, size: 20),
        ),
        title: Text(n.str('title') ?? '', style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w400)),
        subtitle: Text([n.str('body'), fmtAgo(n.date('created_at'))].whereType<String>().where((s) => s.isNotEmpty).join('\n')),
        isThreeLine: n.str('body') != null,
        trailing: unread ? Icon(Icons.circle, size: 10, color: scheme.primary) : null,
      ),
    );
  }
}
