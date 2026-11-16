import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'consultation_screens.dart';
import 'pet_screens.dart';
import 'reception_screens.dart';
import 'shell.dart';

/// Agenda (§17.2): citas del día, con «solo mías» y saltos de día.
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  bool _mine = false;

  void _shift(int days) => setState(() => _day = _day.add(Duration(days: days)));

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _day = picked);
  }

  int _version = 0;

  Future<void> _schedule() async {
    final saved = await Navigator.of(
      context,
    ).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => AppointmentFormScreen(day: _day)));
    if (saved == null) return;
    final day = DateUtils.dateOnly(wallTime(saved.str('starts_at')) ?? _day);
    setState(() {
      _day = day;
      _version++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(_day, DateTime.now());
    final canCreate = context.watch<Session>().profile!.can('appointments.create');

    return Scaffold(
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(onPressed: _schedule, icon: const Icon(Icons.add), label: const Text('Agendar'))
          : null,
      appBar: AppBar(
        leading: shellMenuButton(context),
        title: const Text('Agenda'),
        actions: [
          if (!isToday) TextButton(onPressed: () => setState(() => _day = DateUtils.dateOnly(DateTime.now())), child: const Text('Hoy')),
          IconButton(tooltip: 'Elegir fecha', onPressed: _pick, icon: const Icon(Icons.calendar_today_outlined)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Row(
              children: [
                IconButton(tooltip: 'Día anterior', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: InkWell(
                    onTap: _pick,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        isToday ? 'Hoy · ${fmtDayLong(_day)}' : fmtDayLong(_day),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                IconButton(tooltip: 'Día siguiente', onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [FilterChip(label: const Text('Solo mis citas'), selected: _mine, onSelected: (v) => setState(() => _mine = v))],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Loader<Map<String, dynamic>>(
              key: ValueKey('${isoDate(_day)}-$_mine-$_version'),
              load: () => context.session.api.get('/appointments', query: {'date': isoDate(_day), 'mine': _mine ? '1' : null}),
              builder: (context, data, reload) {
                final items = data.list('data');
                if (items.isEmpty) {
                  return ListView(
                    children: [
                      EmptyState(icon: Icons.event_available, message: _mine ? 'No tienes citas este día.' : 'No hay citas este día.'),
                    ],
                  );
                }
                final active = items.where((a) => !['cancelled', 'no_show'].contains(a.str('status'))).length;
                return ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        active == 1 ? '1 cita' : '$active citas',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                    for (final a in items) AppointmentTile(appointment: a, onChanged: reload, showDate: false),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de una cita: hora, paciente, motivo y estado.
class AppointmentTile extends StatelessWidget {
  const AppointmentTile({super.key, required this.appointment, required this.onChanged, this.showDate = false});

  final Map<String, dynamic> appointment;
  final Future<void> Function() onChanged;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final pet = a.obj('pet') ?? {};
    final badge = a.obj('status_badge') ?? {};
    final start = a.date('starts_at');
    final muted = ['cancelled', 'no_show'].contains(a.str('status'));
    final subtitle = [a.str('reason') ?? a.str('service'), a.obj('veterinarian')?.str('name')].whereType<String>().join(' · ');

    return Opacity(
      opacity: muted ? .55 : 1,
      child: ListTile(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AppointmentScreen(id: a['id'] as int)));
          onChanged();
        },
        leading: SizedBox(
          width: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(fmtTime(start), style: const TextStyle(fontWeight: FontWeight.w700)),
              if (showDate) Text(fmtShortDate(start), style: Theme.of(context).textTheme.bodySmall),
              if (a.flag('is_walk_in')) Text('sin cita', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        // Dentro de la ficha de la mascota no se repite su nombre: va el motivo.
        title: Text(
          pet.isEmpty
              ? (a.str('reason') ?? a.str('service') ?? 'Cita')
              : '${pet.str('name')}${pet.str('species') != null ? ' · ${pet.str('species')}' : ''}',
        ),
        subtitle: Text(
          pet.isEmpty ? (a.obj('veterinarian')?.str('name') ?? 'Sin profesional asignado') : subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: StatusChip(badge.str('label') ?? '', tone: badge.str('color')),
      ),
    );
  }
}

/// Detalle de la cita con sus acciones posibles según el estado.
class AppointmentScreen extends StatefulWidget {
  const AppointmentScreen({super.key, required this.id});

  final int id;

  @override
  State<AppointmentScreen> createState() => _AppointmentScreenState();
}

class _AppointmentScreenState extends State<AppointmentScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  String? _busy;
  Map<String, dynamic>? _appointment;

  static const _active = ['pending', 'confirmed', 'waiting', 'in_progress'];

  /// Abre (o retoma) la consulta de esta cita.
  Future<void> _attend() async {
    setState(() => _busy = 'consultation');
    try {
      final consultation = await context.session.api.post('/appointments/${widget.id}/consultation');
      if (!mounted) return;
      await openConsultation(context, consultation);
      _loader.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  static const _labels = {
    'confirm': ('Confirmar', Icons.check),
    'check_in': ('Llegó', Icons.meeting_room_outlined),
    'start': ('Iniciar atención', Icons.play_arrow),
    'finish': ('Finalizar', Icons.done_all),
    'no_show': ('No asistió', Icons.person_off_outlined),
    'cancel': ('Cancelar cita', Icons.close),
  };

  Future<void> _run(String action) async {
    String? reason;
    if (action == 'cancel' || action == 'no_show') {
      final confirmed = await _confirm(action);
      if (confirmed == null) return;
      reason = confirmed;
    }
    if (!mounted) return;

    setState(() => _busy = action);
    try {
      await context.session.api.post('/appointments/${widget.id}/$action', {'cancellation_reason': ?reason});
      if (mounted) showDone(context, 'Cita actualizada: ${_labels[action]!.$1.toLowerCase()}.');
      _loader.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Devuelve el motivo (puede ser vacío) o null si se arrepintió.
  Future<String?> _confirm(String action) {
    final controller = TextEditingController();
    final cancel = action == 'cancel';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(cancel ? '¿Cancelar la cita?' : '¿Marcar que no asistió?'),
        content: cancel
            ? TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
              )
            : const Text('La cita quedará como «No asistió».'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(cancel ? 'Cancelar cita' : 'Confirmar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final canEdit = profile.can('appointments.edit');
    final canConsult = profile.canUse('consultas', 'consultations.create');

    final current = _appointment;
    final canReschedule = canEdit && current != null && _active.contains(current.str('status'));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cita'),
        actions: [
          if (canReschedule)
            IconButton(
              tooltip: 'Reprogramar',
              icon: const Icon(Icons.edit_calendar_outlined),
              onPressed: () async {
                final saved = await Navigator.of(
                  context,
                ).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => AppointmentFormScreen(appointment: current)));
                if (saved != null) _loader.currentState?.reload();
              },
            ),
        ],
      ),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () async {
          final a = await context.session.api.get('/appointments/${widget.id}');
          if (mounted) setState(() => _appointment = a);
          return a;
        },
        builder: (context, a, reload) {
          final pet = a.obj('pet') ?? {};
          final client = a.obj('client');
          final badge = a.obj('status_badge') ?? {};
          final actions = [for (final x in (a['actions'] as List? ?? [])) '$x'];
          final primary = actions.where((x) => !['cancel', 'no_show'].contains(x)).toList();
          final secondary = actions.where((x) => ['cancel', 'no_show'].contains(x)).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${fmtTime(a.date('starts_at'))} – ${fmtTime(a.date('ends_at'))}',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          StatusChip(badge.str('label') ?? '', tone: badge.str('color')),
                        ],
                      ),
                      Text(fmtDayLong(a.date('starts_at') ?? DateTime.now())),
                      const SizedBox(height: 12),
                      if (a.str('reason') != null) _Line(Icons.notes, a.str('reason')!),
                      if (a.str('service') != null) _Line(Icons.medical_services_outlined, a.str('service')!),
                      _Line(Icons.person_outline, a.obj('veterinarian')?.str('name') ?? 'Sin profesional asignado'),
                      if (a.str('notes') != null) _Line(Icons.sticky_note_2_outlined, a.str('notes')!),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: PetAvatar(name: pet.str('name') ?? '?', photoUrl: pet.str('photo_url')),
                  title: Text(pet.str('name') ?? ''),
                  subtitle: Text([pet.str('species'), pet.str('breed'), pet.str('age_label')].whereType<String>().join(' · ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PetScreen(id: pet['id'] as int))),
                ),
              ),
              if (client != null) ...[
                const SizedBox(height: 12),
                OwnerCard(
                  client: client,
                  onTap: profile.can('clients.view')
                      ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClientScreen(id: client['id'] as int)))
                      : null,
                ),
                // Mensaje prellenado, el mismo que «Enviar recordatorio» en la web; se envía a mano desde WhatsApp.
                if (a.str('whatsapp_reminder') != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => openExternal(context, a.str('whatsapp_reminder')!),
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('Enviar recordatorio por WhatsApp'),
                  ),
                ],
              ],
              if (canConsult &&
                  (a['consultation_id'] != null || ['pending', 'confirmed', 'waiting', 'in_progress'].contains(a.str('status')))) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _busy == null ? _attend : null,
                  icon: _busy == 'consultation'
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.medical_services_outlined),
                  label: Text(a['consultation_id'] != null ? 'Ver consulta' : 'Atender: abrir consulta'),
                ),
              ],
              if (canEdit && actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                for (final action in primary)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: _busy == null ? () => _run(action) : null,
                      icon: _busy == action
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(_labels[action]?.$2),
                      label: Text(_labels[action]?.$1 ?? action),
                    ),
                  ),
                Row(
                  children: [
                    for (final action in secondary)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: OutlinedButton.icon(
                            onPressed: _busy == null ? () => _run(action) : null,
                            icon: Icon(_labels[action]?.$2),
                            label: Text(_labels[action]?.$1 ?? action),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

/// Propietario con accesos para llamar o escribir por WhatsApp.
class OwnerCard extends StatelessWidget {
  const OwnerCard({super.key, required this.client, this.onTap});

  final Map<String, dynamic> client;

  /// Abre la ficha del propietario (si el usuario puede verla).
  final VoidCallback? onTap;

  Future<void> _open(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showError(context, 'No se pudo abrir la aplicación.');
  }

  @override
  Widget build(BuildContext context) {
    final phone = client.str('phone');
    final whatsapp = client.str('whatsapp_url');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              const Icon(Icons.person),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(client.str('name') ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(phone ?? 'Sin teléfono', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (phone != null)
                IconButton.filledTonal(
                  tooltip: 'Llamar',
                  onPressed: () => _open(context, Uri(scheme: 'tel', path: phone)),
                  icon: const Icon(Icons.call),
                ),
              if (whatsapp != null)
                IconButton.filledTonal(
                  tooltip: 'WhatsApp',
                  onPressed: () => _open(context, Uri.parse(whatsapp)),
                  icon: const Icon(Icons.chat),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
