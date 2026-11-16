import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'pet_screens.dart';
import 'reception_screens.dart' show PetPickerScreen;
import 'shell.dart';

/// Estados clínicos, en el orden en que se eligen (los mismos de la web).
const stayConditions = {
  'stable': ('Estable', 'success'),
  'improving': ('Mejorando', 'primary'),
  'observation': ('En observación', 'warning'),
  'critical': ('Crítico', 'danger'),
};

/// Fecha y hora local como la espera la API («2026-11-12 14:30»).
String apiDateTime(DateTime d) => DateFormat('yyyy-MM-dd HH:mm').format(d);

/// ¿Puede el usuario ver hospitalización? (plan + permiso).
bool hospitalVisible(Profile p) => p.canUse('hospitalizacion', 'hospitalizations.view');

/// Interna a un paciente: si no viene [pet], primero se elige. Al terminar
/// abre la internación. Devuelve su id.
Future<int?> admitPatient(BuildContext context, {Map<String, dynamic>? pet, int? consultationId}) async {
  final navigator = Navigator.of(context);
  pet ??= await navigator.push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const PetPickerScreen()));
  if (pet == null) return null;
  final id = await navigator.push<int>(
    MaterialPageRoute(
      builder: (_) => AdmitScreen(pet: pet!, consultationId: consultationId),
    ),
  );
  if (id != null) await navigator.push(MaterialPageRoute(builder: (_) => StayScreen(id: id)));
  return id;
}

/// Hospitalización (§17.6): internados, con los críticos primero.
class HospitalScreen extends StatefulWidget {
  const HospitalScreen({super.key});

  @override
  State<HospitalScreen> createState() => _HospitalScreenState();
}

class _HospitalScreenState extends State<HospitalScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();

  @override
  Widget build(BuildContext context) {
    final canAdmit = context.watch<Session>().profile!.can('hospitalizations.create');

    return Scaffold(
      appBar: AppBar(leading: shellMenuButton(context), title: const Text('Internados')),
      floatingActionButton: canAdmit
          ? FloatingActionButton.extended(
              onPressed: () async {
                await admitPatient(context);
                _loader.currentState?.reload();
              },
              icon: const Icon(Icons.add),
              label: const Text('Ingresar'),
            )
          : null,
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => context.session.api.get('/hospitalizations'),
        builder: (context, data, reload) {
          final items = data.list('data');
          if (items.isEmpty) {
            return ListView(
              children: const [EmptyState(icon: Icons.bed_outlined, message: 'No hay pacientes internados.')],
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final h in items)
                StayTile(
                  stay: h,
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StayScreen(id: h['id'] as int)));
                    reload();
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Una internación en una lista: paciente, espacio, día y estado.
class StayTile extends StatelessWidget {
  const StayTile({super.key, required this.stay, this.onTap, this.showPet = true});

  final Map<String, dynamic> stay;
  final VoidCallback? onTap;
  final bool showPet;

  @override
  Widget build(BuildContext context) {
    final h = stay;
    final active = h.str('status') == 'active';
    final badge = active ? h.obj('condition_badge') : h.obj('status_badge');
    final pet = h.obj('pet');
    final days = h.integer('days') ?? 0;

    return ListTile(
      leading: showPet
          ? PetAvatar(name: pet?.str('name') ?? '?', photoUrl: pet?.str('photo_url'))
          : const CircleAvatar(child: Icon(Icons.local_hospital_outlined)),
      title: Text(showPet ? pet?.str('name') ?? '' : '${h.str('code')} · ${fmtDate(h.date('admitted_at'))}'),
      subtitle: Text(
        [
          active
              ? [h.str('kennel'), 'día $days'].whereType<String>().join(' · ')
              : '$days ${days == 1 ? 'día' : 'días'}${h.date('discharged_at') != null ? ' · hasta ${fmtDate(h.date('discharged_at'))}' : ''}',
          h.str('reason'),
        ].whereType<String>().join('\n'),
      ),
      isThreeLine: h.str('reason') != null,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          StatusChip(badge?.str('label') ?? '', tone: badge?.str('color')),
          if (active && (h.integer('overdue_doses') ?? 0) > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${h.integer('overdue_doses')} tomas atrasadas',
              style: TextStyle(color: toneColor(context, 'danger'), fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}

/// Pestaña «Internaciones» de la ficha: todas, de la más reciente a la más antigua.
class PetStaysTab extends StatelessWidget {
  const PetStaysTab({super.key, required this.pet, required this.reload});

  final Map<String, dynamic> pet;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final canAdmit = context.watch<Session>().profile!.can('hospitalizations.create');
    final interned = pet.integer('active_hospitalization_id') != null;

    return Loader<Map<String, dynamic>>(
      load: () => context.session.api.get('/hospitalizations', query: {'pet_id': '${pet['id']}'}),
      builder: (context, data, reloadList) {
        final items = data.list('data');
        Future<void> refresh() async {
          await reload();
          await reloadList();
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (canAdmit && !interned)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () async {
                    await admitPatient(context, pet: pet);
                    await refresh();
                  },
                  icon: const Icon(Icons.local_hospital_outlined),
                  label: const Text('Internar'),
                ),
              ),
            if (items.isEmpty)
              const EmptyState(icon: Icons.bed_outlined, message: 'Nunca estuvo internado.')
            else ...[
              const SectionTitle('Internaciones'),
              for (final h in items)
                StayTile(
                  stay: h,
                  showPet: false,
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StayScreen(id: h['id'] as int)));
                    await refresh();
                  },
                ),
            ],
          ],
        );
      },
    );
  }
}

/// Una internación: tomas por aplicar, tratamientos y evolución, más las
/// acciones del día: estado clínico, espacio, tratamiento nuevo y alta.
class StayScreen extends StatefulWidget {
  const StayScreen({super.key, required this.id});

  final int id;

  @override
  State<StayScreen> createState() => _StayScreenState();
}

class _StayScreenState extends State<StayScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  Map<String, dynamic>? _stay;
  int? _busy;

  ApiClient get _api => context.session.api;

  void _reload() => _loader.currentState?.reload();

  Future<void> _give(Map<String, dynamic> dose) async {
    setState(() => _busy = dose['id'] as int);
    try {
      await _api.post('/doses/${dose['id']}/give');
      if (mounted) showDone(context, 'Toma de ${dose.str('medication')} registrada.');
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _skip(Map<String, dynamic> dose) async {
    final reason = await askText(context, title: 'Omitir toma', label: '¿Por qué se omite?', action: 'Omitir');
    if (reason == null || !mounted) return;

    setState(() => _busy = dose['id'] as int);
    try {
      await _api.post('/doses/${dose['id']}/skip', {'notes': reason});
      if (mounted) showDone(context, 'Toma omitida.');
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Ejecuta una acción que devuelve la internación actualizada.
  Future<void> _act(Future<Map<String, dynamic>> Function() call, String done) async {
    try {
      await call();
      if (!mounted) return;
      showDone(context, done);
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _changeCondition() async {
    final result = await showModalBottomSheet<(String, String?)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ConditionSheet(current: _stay?.str('condition')),
    );
    if (result == null || !mounted) return;
    final (condition, note) = result;
    await _act(
      () => _api.post('/hospitalizations/${widget.id}/records', {'type': 'evolution', 'condition': condition, 'notes': note}),
      'Estado: ${stayConditions[condition]?.$1}.',
    );
  }

  Future<void> _moveKennel() async {
    final options = _api.get('/hospitalizations/options', query: {'hospitalization_id': '${widget.id}'});
    final kennelId = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => _KennelSheet(options: options, current: _stay?.integer('kennel_id')),
    );
    if (kennelId == null || !mounted) return;
    await _act(
      () => _api.post('/hospitalizations/${widget.id}/kennel', {'kennel_id': kennelId == 0 ? null : kennelId}),
      'Ubicación actualizada.',
    );
  }

  Future<void> _stopTreatment(Map<String, dynamic> t) async {
    final ok = await confirm(
      context,
      title: '¿Suspender ${t.str('medication')}?',
      message: 'Las tomas que faltan se anulan. Las ya aplicadas quedan en el historial.',
      action: 'Suspender',
    );
    if (!ok || !mounted) return;
    await _act(() => _api.post('/hospitalizations/${widget.id}/treatments/${t['id']}/stop'), 'Tratamiento suspendido.');
  }

  Future<void> _cancel() async {
    final reason = await askText(
      context,
      title: 'Anular el ingreso',
      label: 'Motivo',
      action: 'Anular',
      hint: 'Solo para un ingreso cargado por error. Si el paciente estuvo internado, corresponde darle el alta.',
    );
    if (reason == null || !mounted) return;
    await _act(() => _api.post('/hospitalizations/${widget.id}/cancel', {'cancel_reason': reason}), 'Internación anulada.');
  }

  Future<void> _open(Widget screen) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => screen));
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final canEdit = profile.can('hospitalizations.edit');
    final canAdmit = profile.can('hospitalizations.create');
    final actions = [for (final a in (_stay?['actions'] as List? ?? [])) '$a'];
    bool allowed(String a) => actions.contains(a) && (['discharge', 'cancel'].contains(a) ? canAdmit : canEdit);
    final menu = [
      if (allowed('record')) ('condition', 'Cambiar estado clínico', Icons.monitor_heart_outlined),
      if (allowed('kennel')) ('kennel', 'Mover de espacio', Icons.swap_horiz),
      if (allowed('treat')) ('treat', 'Indicar tratamiento', Icons.medication_outlined),
      if (allowed('discharge')) ('discharge', 'Dar el alta', Icons.logout),
      if (allowed('cancel')) ('cancel', 'Anular ingreso', Icons.block),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_stay?.str('code') ?? 'Internación'),
        actions: [
          if (menu.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Acciones',
              onSelected: (v) => switch (v) {
                'condition' => _changeCondition(),
                'kennel' => _moveKennel(),
                'treat' => _open(TreatmentScreen(stayId: widget.id)),
                'discharge' => _open(DischargeScreen(stay: _stay!)),
                'cancel' => _cancel(),
                _ => null,
              },
              itemBuilder: (context) => [
                for (final (value, label, icon) in menu)
                  PopupMenuItem(
                    value: value,
                    child: ListTile(
                      leading: Icon(icon, color: value == 'cancel' ? Theme.of(context).colorScheme.error : null),
                      title: Text(label),
                    ),
                  ),
              ],
            ),
        ],
      ),
      floatingActionButton: allowed('record')
          ? FloatingActionButton.extended(
              onPressed: () => _open(RecordScreen(stayId: widget.id, condition: _stay?.str('condition'))),
              icon: const Icon(Icons.edit_note),
              label: const Text('Registrar'),
            )
          : null,
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () async {
          final h = await _api.get('/hospitalizations/${widget.id}');
          if (mounted) setState(() => _stay = h);
          return h;
        },
        builder: (context, h, reload) {
          final pet = h.obj('pet') ?? {};
          final doses = h.list('doses');
          final pending = doses.where((d) => d.str('status') == 'pending').toList();
          final done = doses.where((d) => d.str('status') != 'pending').toList().reversed.toList();
          final active = h.str('status') == 'active';
          final badge = active ? h.obj('condition_badge') : h.obj('status_badge');
          final treatments = h.list('treatments');

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              ListTile(
                leading: PetAvatar(name: pet.str('name') ?? '?', photoUrl: pet.str('photo_url')),
                title: Text(pet.str('name') ?? ''),
                subtitle: Text(
                  [
                    h.str('kennel') ?? (active ? 'Sin espacio asignado' : null),
                    'día ${h.integer('days')}',
                    h.str('veterinarian'),
                  ].whereType<String>().join(' · '),
                ),
                trailing: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: allowed('record') ? _changeCondition : null,
                  child: StatusChip(badge?.str('label') ?? '', tone: badge?.str('color')),
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PetScreen(id: pet['id'] as int))),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ingreso: ${fmtDateTime(h.date('admitted_at'))}', style: Theme.of(context).textTheme.bodySmall),
                    if (h.str('reason') != null) Text('Motivo: ${h.str('reason')}'),
                    if (h.str('admission_diagnosis') != null) Text('Diagnóstico de ingreso: ${h.str('admission_diagnosis')}'),
                  ],
                ),
              ),
              if (!active) ...[const SizedBox(height: 12), _ClosedCard(stay: h)],
              if (active) ...[
                const SectionTitle('Tomas por aplicar'),
                if (pending.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.check_circle_outline),
                    title: Text('No hay tomas pendientes en las próximas 12 horas.'),
                  ),
                for (final d in pending)
                  _DoseTile(
                    dose: d,
                    busy: _busy == d['id'],
                    enabled: canEdit && _busy == null,
                    onGive: () => _give(d),
                    onSkip: () => _skip(d),
                  ),
              ],
              if (done.isNotEmpty) ...[
                const SectionTitle('Últimas 24 horas'),
                for (final d in done)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      d.str('status') == 'given' ? Icons.check_circle : Icons.remove_circle_outline,
                      color: toneColor(context, d.str('status') == 'given' ? 'success' : 'warning'),
                    ),
                    title: Text('${d.str('medication')} · ${d.str('dose')}'),
                    subtitle: Text(
                      '${d.str('status_label')} ${fmtTime(d.date('done_at'))}'
                      '${d.str('done_by') != null ? ' por ${d.str('done_by')}' : ''}'
                      '${d.str('notes') != null ? ' · ${d.str('notes')}' : ''}',
                    ),
                  ),
              ],
              SectionTitle(
                'Tratamientos',
                trailing: allowed('treat')
                    ? TextButton.icon(
                        onPressed: () => _open(TreatmentScreen(stayId: widget.id)),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Indicar'),
                      )
                    : null,
              ),
              if (treatments.isEmpty) const ListTile(title: Text('Sin tratamientos indicados.')),
              for (final t in treatments)
                ListTile(
                  leading: Icon(Icons.medication_outlined, color: t.flag('active') ? null : Theme.of(context).disabledColor),
                  title: Text('${t.str('medication')} · ${t.str('dose')}'),
                  subtitle: Text(
                    [
                      t.str('route'),
                      'cada ${t.integer('frequency_hours')} h',
                      t.flag('active') ? 'hasta ${fmtDateTime(t.date('ends_at'))}' : 'suspendido',
                      t.str('instructions'),
                    ].whereType<String>().join(' · '),
                  ),
                  trailing: t.flag('active') && allowed('treat')
                      ? IconButton(tooltip: 'Suspender', onPressed: () => _stopTreatment(t), icon: const Icon(Icons.stop_circle_outlined))
                      : null,
                ),
              const SectionTitle('Evolución y cuidados'),
              if (h.list('records').isEmpty) const ListTile(title: Text('Sin registros todavía.')),
              for (final r in h.list('records'))
                ListTile(
                  leading: const Icon(Icons.timeline),
                  title: Text('${r.str('type_label')} · ${fmtDateTime(r.date('recorded_at'))}'),
                  subtitle: Text(
                    [
                      if (r.str('condition') != null) 'Estado: ${r.str('condition')}',
                      if (r.number('temperature') != null) '${fmtNumber(r.number('temperature'))} °C',
                      if (r.integer('heart_rate') != null) '${r.integer('heart_rate')} lpm',
                      if (r.integer('respiratory_rate') != null) '${r.integer('respiratory_rate')} rpm',
                      if (r.number('weight') != null) '${fmtNumber(r.number('weight'))} kg',
                      r.str('notes'),
                      r.str('recorded_by'),
                    ].whereType<String>().join(' · '),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Resultado de una internación cerrada: alta, fallecimiento o anulación.
class _ClosedCard extends StatelessWidget {
  const _ClosedCard({required this.stay});

  final Map<String, dynamic> stay;

  @override
  Widget build(BuildContext context) {
    final h = stay;
    final status = h.str('status');
    final tone = switch (status) {
      'discharged' => 'success',
      'deceased' => 'dark',
      _ => 'secondary',
    };
    final lines = <(String, String?)>[
      if (status == 'cancelled') ('Motivo de la anulación', h.str('cancel_reason')),
      ('Diagnóstico final', h.str('final_diagnosis')),
      ('Tratamiento en casa', h.str('home_treatment')),
      ('Indicaciones', h.str('discharge_instructions')),
      ('Resumen', h.str('summary')),
    ].where((l) => l.$2 != null && l.$2!.isNotEmpty).toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: toneColor(context, tone).withValues(alpha: .08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                h.obj('status_badge')?.str('label'),
                if (h.date('discharged_at') != null) fmtDateTime(h.date('discharged_at')),
                h.str('discharged_by'),
              ].whereType<String>().join(' · '),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            for (final (label, value) in lines) ...[const SizedBox(height: 8), Fact(label, value!)],
          ],
        ),
      ),
    );
  }
}

class _ConditionSheet extends StatefulWidget {
  const _ConditionSheet({required this.current});

  final String? current;

  @override
  State<_ConditionSheet> createState() => _ConditionSheetState();
}

class _ConditionSheetState extends State<_ConditionSheet> {
  late String? _picked = widget.current;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Estado clínico', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ConditionPicker(value: _picked, onChanged: (c) => setState(() => _picked = c)),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Observación (opcional)'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _picked == null || _picked == widget.current
                ? null
                : () => Navigator.pop(context, (_picked!, _note.text.trim().isEmpty ? null : _note.text.trim())),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

/// Elegir el estado clínico, cada uno con su color.
class ConditionPicker extends StatelessWidget {
  const ConditionPicker({super.key, required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final MapEntry(key: key, value: (label, tone)) in stayConditions.entries)
          ChoiceChip(
            label: Text(label),
            selected: value == key,
            avatar: Icon(Icons.circle, size: 12, color: toneColor(context, tone)),
            showCheckmark: false,
            selectedColor: toneColor(context, tone).withValues(alpha: .18),
            onSelected: (_) => onChanged(key),
          ),
      ],
    );
  }
}

/// Elegir espacio libre. Devuelve su id, o 0 para dejarlo sin espacio.
class _KennelSheet extends StatelessWidget {
  const _KennelSheet({required this.options, required this.current});

  final Future<Map<String, dynamic>> options;
  final int? current;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: options,
      builder: (context, snap) {
        if (snap.hasError) return Padding(padding: const EdgeInsets.all(24), child: Text('${snap.error}'));
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final kennels = snap.data!.list('kennels');
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Mover a', style: Theme.of(context).textTheme.titleLarge),
              ),
              if (kennels.where((k) => k['id'] != current).isEmpty) const ListTile(title: Text('No hay otros espacios libres.')),
              for (final k in kennels)
                ListTile(
                  leading: const Icon(Icons.bed_outlined),
                  title: Text(k.str('name') ?? ''),
                  trailing: k['id'] == current ? const Text('Actual') : null,
                  enabled: k['id'] != current,
                  onTap: () => Navigator.pop(context, k['id'] as int),
                ),
              if (current != null)
                ListTile(
                  leading: const Icon(Icons.not_interested),
                  title: const Text('Sin espacio asignado'),
                  onTap: () => Navigator.pop(context, 0),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DoseTile extends StatelessWidget {
  const _DoseTile({required this.dose, required this.busy, required this.enabled, required this.onGive, required this.onSkip});

  final Map<String, dynamic> dose;
  final bool busy;
  final bool enabled;
  final VoidCallback onGive;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final overdue = dose.flag('overdue');
    final danger = toneColor(context, 'danger');

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      color: overdue ? danger.withValues(alpha: .08) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(fmtTime(dose.date('scheduled_at')), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(width: 8),
                if (overdue) StatusChip('Atrasada', tone: 'danger'),
              ],
            ),
            const SizedBox(height: 4),
            Text('${dose.str('medication')} · ${dose.str('dose')}', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (dose.str('route') != null) Text(dose.str('route')!, style: Theme.of(context).textTheme.bodySmall),
            if (enabled || busy)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: enabled ? onSkip : null, child: const Text('Omitir')),
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    onPressed: enabled ? onGive : null,
                    icon: busy
                        ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: const Text('Aplicada'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ── Formularios ─────────────────────────────────────────────────────────────

Widget _formError(BuildContext context, ApiException? error) => error != null && error.fieldErrors.isEmpty
    ? Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(error.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      )
    : const SizedBox.shrink();

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saving, required this.label, required this.onPressed, this.color});

  final bool saving;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: saving ? null : onPressed,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: color),
      child: saving ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(label),
    );
  }
}

/// Ingreso de un paciente: estado, espacio libre, motivo y responsable.
class AdmitScreen extends StatefulWidget {
  const AdmitScreen({super.key, required this.pet, this.consultationId});

  final Map<String, dynamic> pet;
  final int? consultationId;

  @override
  State<AdmitScreen> createState() => _AdmitScreenState();
}

class _AdmitScreenState extends State<AdmitScreen> {
  final _reason = TextEditingController();
  final _diagnosis = TextEditingController();
  final _notes = TextEditingController();
  final _rate = TextEditingController();
  String _condition = 'observation';
  int? _kennelId;
  int? _vetId;
  bool _suggested = false;
  bool _saving = false;
  ApiException? _error;

  @override
  void dispose() {
    for (final c in [_reason, _diagnosis, _notes, _rate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = ApiException(422, 'Indica el motivo.', fieldErrors: {'reason': 'Indica el motivo del ingreso.'}));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final stay = await context.session.api.post('/hospitalizations', {
        'pet_id': widget.pet['id'],
        if (widget.consultationId != null) 'consultation_id': widget.consultationId,
        'condition': _condition,
        'kennel_id': _kennelId,
        'veterinarian_id': _vetId,
        'reason': _reason.text.trim(),
        'admission_diagnosis': _diagnosis.text.trim().isEmpty ? null : _diagnosis.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'daily_rate': num.tryParse(_rate.text.replaceAll(',', '.').trim()),
      });
      if (!mounted) return;
      showDone(context, '${widget.pet.str('name')} internado.');
      Navigator.of(context).pop(stay['id'] as int);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pet = widget.pet;
    return Scaffold(
      appBar: AppBar(title: Text('Internar a ${pet.str('name') ?? ''}')),
      body: Loader<Map<String, dynamic>>(
        load: () => context.session.api.get(
          '/hospitalizations/options',
          query: {'pet_id': '${pet['id']}', if (widget.consultationId != null) 'consultation_id': '${widget.consultationId}'},
        ),
        builder: (context, options, reload) {
          final activeId = options.integer('active_hospitalization_id');
          if (activeId != null) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                EmptyState(icon: Icons.local_hospital_outlined, message: '${pet.str('name')} ya está internado.'),
                FilledButton(
                  onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => StayScreen(id: activeId))),
                  child: const Text('Ver la internación'),
                ),
              ],
            );
          }
          // Desde una consulta, motivo y diagnóstico vienen propuestos (una sola vez).
          final suggested = options.obj('suggested');
          if (!_suggested && suggested != null) {
            _suggested = true;
            _reason.text = suggested.str('reason') ?? '';
            _diagnosis.text = suggested.str('admission_diagnosis') ?? '';
          }
          final kennels = options.list('kennels');
          final vets = options.list('professionals');

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _formError(context, _error),
              if (_error?.field('pet_id') != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!.field('pet_id')!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              Text('Estado al ingresar', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ConditionPicker(value: _condition, onChanged: (c) => setState(() => _condition = c)),
              const SizedBox(height: 20),
              DropdownButtonFormField<int?>(
                initialValue: _kennelId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Espacio',
                  helperText: kennels.isEmpty ? 'No hay espacios libres: se puede asignar después.' : null,
                  errorText: _error?.field('kennel_id'),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Sin asignar')),
                  for (final k in kennels) DropdownMenuItem<int?>(value: k['id'] as int, child: Text(k.str('name') ?? '')),
                ],
                onChanged: (id) => setState(() => _kennelId = id),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _reason,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: 'Motivo del ingreso', errorText: _error?.field('reason')),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _diagnosis,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Diagnóstico de ingreso (opcional)'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int?>(
                initialValue: _vetId,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'Responsable', errorText: _error?.field('veterinarian_id')),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Yo')),
                  for (final v in vets) DropdownMenuItem<int?>(value: v['id'] as int, child: Text(v.str('name') ?? '')),
                ],
                onChanged: (id) => setState(() => _vetId = id),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _rate,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Costo por día (opcional)',
                  helperText: 'Se cobra por día o fracción al dar el alta.',
                  errorText: _error?.field('daily_rate'),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Observaciones (opcional)'),
              ),
              const SizedBox(height: 24),
              _SaveButton(saving: _saving, label: 'Internar', onPressed: _save),
            ],
          );
        },
      ),
    );
  }
}

/// Indicar un medicamento: dosis, vía, cada cuántas horas y hasta cuándo.
/// El servidor genera las tomas, igual que en la web.
class TreatmentScreen extends StatefulWidget {
  const TreatmentScreen({super.key, required this.stayId});

  final int stayId;

  @override
  State<TreatmentScreen> createState() => _TreatmentScreenState();
}

class _TreatmentScreenState extends State<TreatmentScreen> {
  final _medication = TextEditingController();
  final _dose = TextEditingController();
  final _instructions = TextEditingController();
  final _units = TextEditingController();
  int? _productId;
  String? _route;
  int _every = 8;
  int _days = 3;
  DateTime _start = DateTime.now();
  bool _saving = false;
  ApiException? _error;

  static const _frequencies = [4, 6, 8, 12, 24];
  static const _durations = [1, 3, 5, 7, 10];

  DateTime get _end => _start.add(Duration(days: _days));
  int get _doseCount => _end.difference(_start).inHours ~/ _every + 1;

  @override
  void dispose() {
    for (final c in [_medication, _dose, _instructions, _units]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickStart() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (time == null) return;
    setState(() => _start = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.session.api.post('/hospitalizations/${widget.stayId}/treatments', {
        'product_id': _productId,
        'medication': _medication.text.trim().isEmpty ? null : _medication.text.trim(),
        'dose': _dose.text.trim(),
        'stock_quantity': _productId == null ? null : num.tryParse(_units.text.replaceAll(',', '.').trim()),
        'route': _route,
        'frequency_hours': _every,
        'starts_at': apiDateTime(_start),
        'ends_at': apiDateTime(_end),
        'instructions': _instructions.text.trim().isEmpty ? null : _instructions.text.trim(),
      });
      if (!mounted) return;
      showDone(context, 'Tratamiento programado: $_doseCount tomas.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: const Text('Indicar tratamiento')),
      body: Loader<Map<String, dynamic>>(
        load: () => context.session.api.get('/hospitalizations/options', query: {'hospitalization_id': '${widget.stayId}'}),
        builder: (context, options, reload) {
          final products = options.list('products');
          final routes = options.list('routes');

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _formError(context, _error),
              if (products.isNotEmpty) ...[
                DropdownButtonFormField<int?>(
                  initialValue: _productId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Producto del inventario (opcional)',
                    helperText: 'Si lo eliges, cada toma aplicada descuenta stock y suma el costo.',
                    helperMaxLines: 2,
                    errorText: _error?.field('product_id'),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('No descontar del inventario')),
                    for (final p in products)
                      DropdownMenuItem<int?>(
                        value: p['id'] as int,
                        child: Text(p.str('name') ?? '', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) => setState(() {
                    _productId = id;
                    if (id != null && _medication.text.trim().isEmpty) {
                      _medication.text = products.firstWhere((p) => p['id'] == id).str('name') ?? '';
                    }
                    if (id != null && _units.text.isEmpty) _units.text = '1';
                  }),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _medication,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: 'Medicamento', errorText: _error?.field('medication')),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dose,
                      decoration: InputDecoration(labelText: 'Dosis', hintText: '100 ml, 1 comp.', errorText: _error?.field('dose')),
                    ),
                  ),
                  if (_productId != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _units,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: 'Unidades por toma', errorText: _error?.field('stock_quantity')),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _route,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'Vía', errorText: _error?.field('route')),
                items: [for (final r in routes) DropdownMenuItem(value: r.str('key'), child: Text(r.str('label') ?? ''))],
                onChanged: (v) => setState(() => _route = v),
              ),
              const SizedBox(height: 20),
              Text('Cada', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final h in _frequencies)
                    ChoiceChip(label: Text('$h h'), selected: _every == h, onSelected: (_) => setState(() => _every = h)),
                ],
              ),
              const SizedBox(height: 16),
              Text('Durante', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final d in _durations)
                    ChoiceChip(
                      label: Text('$d ${d == 1 ? 'día' : 'días'}'),
                      selected: _days == d,
                      onSelected: (_) => setState(() => _days = d),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickStart,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Primera toma',
                    suffixIcon: const Icon(Icons.schedule),
                    errorText: _error?.field('starts_at'),
                  ),
                  child: Text(fmtDateTime(_start)),
                ),
              ),
              const SizedBox(height: 8),
              Text('$_doseCount tomas, la última el ${fmtDateTime(_end)}.', style: muted),
              if (_error?.field('ends_at') != null)
                Text(_error!.field('ends_at')!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              TextField(
                controller: _instructions,
                decoration: const InputDecoration(labelText: 'Indicaciones (opcional)', hintText: 'Diluido, lento, con comida…'),
              ),
              const SizedBox(height: 24),
              _SaveButton(saving: _saving, label: 'Programar tratamiento', onPressed: _save),
            ],
          );
        },
      ),
    );
  }
}

/// Alta médica o fallecimiento: cierra la internación y anula las tomas pendientes.
class DischargeScreen extends StatefulWidget {
  const DischargeScreen({super.key, required this.stay});

  final Map<String, dynamic> stay;

  @override
  State<DischargeScreen> createState() => _DischargeScreenState();
}

class _DischargeScreenState extends State<DischargeScreen> {
  late final _diagnosis = TextEditingController(text: widget.stay.str('admission_diagnosis'));
  final _home = TextEditingController();
  final _instructions = TextEditingController();
  final _summary = TextEditingController();
  String _outcome = 'discharged';
  bool _saving = false;
  ApiException? _error;

  bool get _deceased => _outcome == 'deceased';

  @override
  void dispose() {
    for (final c in [_diagnosis, _home, _instructions, _summary]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    final name = widget.stay.obj('pet')?.str('name') ?? 'el paciente';
    if (_deceased) {
      final ok = await confirm(
        context,
        title: '¿Registrar el fallecimiento de $name?',
        message: 'La ficha queda como fallecido y se anulan las tomas pendientes.',
        action: 'Registrar',
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.session.api.post('/hospitalizations/${widget.stay['id']}/discharge', {
        'outcome': _outcome,
        'final_diagnosis': _diagnosis.text.trim(),
        'home_treatment': _deceased ? null : _text(_home),
        'discharge_instructions': _deceased ? null : _text(_instructions),
        'summary': _text(_summary),
      });
      if (!mounted) return;
      showDone(context, _deceased ? 'Fallecimiento registrado.' : 'Alta de $name registrada.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pet = widget.stay.obj('pet');
    return Scaffold(
      appBar: AppBar(title: Text('Alta · ${pet?.str('name') ?? ''}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _formError(context, _error),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'discharged', label: Text('Alta médica'), icon: Icon(Icons.home_outlined)),
              ButtonSegment(value: 'deceased', label: Text('Fallecimiento')),
            ],
            selected: {_outcome},
            onSelectionChanged: (s) => setState(() => _outcome = s.first),
          ),
          const SizedBox(height: 8),
          Text(
            'Se cierra la internación, se libera el espacio y se anulan las tomas que faltan.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _diagnosis,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'Diagnóstico final', errorText: _error?.field('final_diagnosis')),
          ),
          if (!_deceased) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _home,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Tratamiento en casa (opcional)', alignLabelWithHint: true),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _instructions,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Indicaciones al propietario (opcional)', alignLabelWithHint: true),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _summary,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Resumen de la internación (opcional)', alignLabelWithHint: true),
          ),
          if (_error?.field('discharged_at') != null) ...[
            const SizedBox(height: 8),
            Text(_error!.field('discharged_at')!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          _SaveButton(
            saving: _saving,
            label: _deceased ? 'Registrar fallecimiento' : 'Dar el alta',
            color: _deceased ? Theme.of(context).colorScheme.onSurface : null,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// Registrar evolución, signos vitales o cuidados; opcionalmente, el nuevo estado clínico.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.stayId, this.condition});

  final int stayId;

  /// Estado clínico actual: el registro lo cambia solo si se elige otro.
  final String? condition;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  String _type = 'evolution';
  late String? _condition = widget.condition;
  final _notes = TextEditingController();
  final _temperature = TextEditingController();
  final _heart = TextEditingController();
  final _resp = TextEditingController();
  final _weight = TextEditingController();
  bool _saving = false;
  ApiException? _error;

  static const _types = {
    'evolution': 'Evolución',
    'vitals': 'Signos vitales',
    'feeding': 'Alimentación',
    'hydration': 'Hidratación',
    'care': 'Cuidados',
    'incident': 'Incidencia',
  };

  @override
  void dispose() {
    for (final c in [_notes, _temperature, _heart, _resp, _weight]) {
      c.dispose();
    }
    super.dispose();
  }

  num? _num(TextEditingController c) => num.tryParse(c.text.replaceAll(',', '.').trim());

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.session.api.post('/hospitalizations/${widget.stayId}/records', {
        'type': _type,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'temperature': _num(_temperature),
        'heart_rate': _num(_heart)?.toInt(),
        'respiratory_rate': _num(_resp)?.toInt(),
        'weight': _num(_weight),
        if (_condition != null && _condition != widget.condition) 'condition': _condition,
      });
      if (!mounted) return;
      showDone(context, 'Registro guardado.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController c, String label, String key, String suffix) => Expanded(
    child: TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, suffixText: suffix, errorText: _error?.field(key)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final vitals = _type == 'vitals';
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo registro')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _types.entries)
                ChoiceChip(label: Text(t.value), selected: _type == t.key, onSelected: (_) => setState(() => _type = t.key)),
            ],
          ),
          const SizedBox(height: 16),
          if (vitals) ...[
            Row(
              children: [
                _field(_temperature, 'Temperatura', 'temperature', '°C'),
                const SizedBox(width: 12),
                _field(_weight, 'Peso', 'weight', 'kg'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _field(_heart, 'Frec. cardíaca', 'heart_rate', 'lpm'),
                const SizedBox(width: 12),
                _field(_resp, 'Frec. respiratoria', 'respiratory_rate', 'rpm'),
              ],
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _notes,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: vitals ? 'Observaciones (opcional)' : 'Observación',
              alignLabelWithHint: true,
              errorText: _error?.field('notes'),
            ),
          ),
          const SizedBox(height: 16),
          Text('Estado clínico', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ConditionPicker(value: _condition, onChanged: (c) => setState(() => _condition = c)),
          if (_error != null && _error!.fieldErrors.isEmpty) ...[
            const SizedBox(height: 12),
            Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          _SaveButton(saving: _saving, label: 'Guardar', onPressed: _save),
        ],
      ),
    );
  }
}
