import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'consultation_screens.dart' show SuggestField;
import 'pet_screens.dart';
import 'shell.dart';

/// Vacunación (§17.5): atrasadas y próximas, de vacunas y desparasitaciones.
class VaccinesScreen extends StatelessWidget {
  const VaccinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: shellMenuButton(context),
          title: const Text('Vacunación'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Atrasadas'),
              Tab(text: 'Próximas'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _DueList(tab: 'overdue'),
            _DueList(tab: 'upcoming'),
          ],
        ),
      ),
    );
  }
}

class _DueList extends StatelessWidget {
  const _DueList({required this.tab});

  final String tab;

  @override
  Widget build(BuildContext context) {
    return Loader<Map<String, dynamic>>(
      load: () => context.session.api.get('/vaccinations/due', query: {'tab': tab}),
      builder: (context, data, reload) {
        final items = data.list('data');
        if (items.isEmpty) {
          return ListView(
            children: [
              EmptyState(
                icon: Icons.verified_outlined,
                message: tab == 'overdue'
                    ? 'No hay vacunas ni desparasitaciones atrasadas.'
                    : 'Nada programado en los próximos ${data.integer('days')} días.',
              ),
            ],
          );
        }
        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                tab == 'upcoming'
                    ? 'Próximos ${data.integer('days')} días. Toca el ícono de WhatsApp para recordarle al propietario.'
                    : 'Toca el ícono de WhatsApp para recordarle al propietario.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            for (final item in items)
              HealthTile(
                item: item,
                showPet: true,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PetScreen(id: item.obj('pet')!['id'] as int))),
              ),
          ],
        );
      },
    );
  }
}

/// Pestaña «Salud» de la ficha: registrar, ver el detalle de cada aplicación,
/// recordar la próxima por WhatsApp y compartir el carnet.
class PetHealthTab extends StatefulWidget {
  const PetHealthTab({super.key, required this.pet, required this.reload});

  final Map<String, dynamic> pet;
  final Future<void> Function() reload;

  @override
  State<PetHealthTab> createState() => _PetHealthTabState();
}

class _PetHealthTabState extends State<PetHealthTab> {
  bool _sharing = false;

  int get _petId => widget.pet['id'] as int;
  String get _petName => widget.pet.str('name') ?? '';

  Future<void> _open(Widget form) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => form));
    if (saved == true) widget.reload();
  }

  Future<void> _details(Map<String, dynamic> item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => HealthRecordSheet(item: item),
    );
    if (!mounted || action == null) return;
    final isDeworming = item.str('kind') == 'deworming';
    if (action == 'edit') {
      await _open(
        isDeworming
            ? DewormScreen(petId: _petId, petName: _petName, record: item)
            : VaccinateScreen(petId: _petId, petName: _petName, record: item),
      );
    } else if (action == 'delete') {
      await _delete(item, isDeworming);
    }
  }

  Future<void> _delete(Map<String, dynamic> item, bool isDeworming) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isDeworming ? '¿Eliminar esta desparasitación?' : '¿Eliminar esta vacuna?'),
        content: Text(
          '${item.str('name')} del ${fmtDate(item.date('applied_at'))}.\n\n'
          'Si se descontó del inventario, vuelve al stock. No se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.session.api.delete(isDeworming ? '/dewormings/${item['id']}' : '/vaccinations/${item['id']}');
      if (!mounted) return;
      showDone(context, 'Registro eliminado.');
      widget.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _shareCard() async {
    setState(() => _sharing = true);
    try {
      await shareHealthCard(context, _petId, _petName);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final canCreate = profile.can('vaccinations.create');
    final health = widget.pet.obj('health') ?? {};
    final vaccines = health.list('vaccinations');
    final dewormings = health.list('dewormings');
    final pending = [...vaccines, ...dewormings].where((x) => x.flag('pending')).toList()
      ..sort((a, b) => (a.date('next_due_at') ?? DateTime(9999)).compareTo(b.date('next_due_at') ?? DateTime(9999)));

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            children: [
              if (canCreate)
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        onPressed: () => _open(VaccinateScreen(petId: _petId, petName: _petName)),
                        icon: const Icon(Icons.vaccines),
                        label: const Text('Vacunar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        onPressed: () => _open(DewormScreen(petId: _petId, petName: _petName)),
                        icon: const Icon(Icons.bug_report_outlined),
                        label: const Text('Desparasitar'),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                onPressed: _sharing ? null : _shareCard,
                icon: _sharing
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.ios_share),
                label: const Text('Compartir carnet sanitario (PDF)'),
              ),
            ],
          ),
        ),
        if (pending.isNotEmpty) ...[
          const SectionTitle('Pendientes'),
          for (final p in pending) HealthTile(item: p, onTap: () => _details(p), showApplied: false),
        ],
        const SectionTitle('Vacunas'),
        if (vaccines.isEmpty) const ListTile(title: Text('Sin vacunas registradas.')),
        for (final v in vaccines) HealthTile(item: v, onTap: () => _details(v), showReminder: false),
        const SectionTitle('Desparasitaciones'),
        if (dewormings.isEmpty) const ListTile(title: Text('Sin desparasitaciones registradas.')),
        for (final d in dewormings) HealthTile(item: d, onTap: () => _details(d), showReminder: false),
      ],
    );
  }
}

/// Descarga el carnet en PDF y abre el menú del teléfono para enviarlo.
Future<void> shareHealthCard(BuildContext context, int petId, String petName) async {
  try {
    final bytes = await context.session.api.download('/pets/$petId/health-card.pdf');
    final name = 'Carnet-${petName.isEmpty ? petId : petName}.pdf';
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(Uint8List.fromList(bytes), mimeType: 'application/pdf', name: name)],
        fileNameOverrides: [name],
        text: 'Carnet sanitario de $petName',
      ),
    );
  } catch (e) {
    if (context.mounted) showError(context, e is ApiException ? e : 'No se pudo compartir el carnet.');
  }
}

/// Vacuna o desparasitación con su próxima dosis resaltada si está atrasada.
/// Si está pendiente y el propietario tiene WhatsApp, muestra el botón para recordarle.
class HealthTile extends StatelessWidget {
  const HealthTile({super.key, required this.item, this.showPet = false, this.showApplied = true, this.showReminder = true, this.onTap});

  final Map<String, dynamic> item;
  final bool showPet;
  final bool showApplied;
  final bool showReminder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final next = item.date('next_due_at');
    final today = DateUtils.dateOnly(DateTime.now());
    final overdue = next != null && next.isBefore(today) && item['pending'] != false;
    final pet = item.obj('pet');
    final reminder = showReminder ? item.str('whatsapp_reminder') : null;
    final isDeworming = item.str('kind') == 'deworming';

    return ListTile(
      onTap: onTap,
      leading: Icon(isDeworming ? Icons.bug_report_outlined : Icons.vaccines_outlined),
      title: Text(showPet && pet != null ? '${pet.str('name')} · ${item.str('name')}' : item.str('name') ?? ''),
      subtitle: Text(
        [
          if (showPet && pet?.obj('owner') != null) pet!.obj('owner')!.str('name'),
          if (!showPet && isDeworming && item.str('product') != null) item.str('product'),
          if (!showPet && showApplied)
            'Aplicada ${fmtDate(item.date('applied_at'))}${item.integer('dose_number') != null ? ' · dosis ${item.integer('dose_number')}' : ''}',
        ].whereType<String>().join('\n'),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (next != null)
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(overdue ? 'Atrasada' : 'Próxima', style: Theme.of(context).textTheme.bodySmall),
                Text(
                  fmtDate(next),
                  style: TextStyle(fontWeight: FontWeight.w600, color: overdue ? toneColor(context, 'danger') : null),
                ),
              ],
            ),
          if (reminder != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: IconButton(
                tooltip: 'Recordar por WhatsApp',
                color: toneColor(context, 'success'),
                onPressed: () => openExternal(context, reminder),
                icon: const Icon(Icons.chat_outlined),
              ),
            ),
        ],
      ),
    );
  }
}

/// Detalle de una aplicación. Devuelve 'edit' o 'delete' si el usuario elige esa acción.
class HealthRecordSheet extends StatelessWidget {
  const HealthRecordSheet({super.key, required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final isDeworming = item.str('kind') == 'deworming';
    final reminder = item.str('whatsapp_reminder');
    final weight = item.number('weight');
    final lines = <(IconData, String)>[
      (Icons.event_available_outlined, 'Aplicada el ${fmtDate(item.date('applied_at'))}'),
      if (item.integer('dose_number') != null) (Icons.looks_one_outlined, 'Dosis ${item.integer('dose_number')}'),
      if (item.str('product') != null) (Icons.medication_outlined, item.str('product')!),
      if (item.str('dose') != null || weight != null)
        (Icons.scale_outlined, [item.str('dose'), if (weight != null) '${fmtNumber(weight)} kg'].whereType<String>().join(' · ')),
      if (item.str('lot') != null)
        (
          Icons.qr_code_2,
          'Lote ${item.str('lot')}${item.date('lot_expires_at') != null ? ' · vence ${fmtDate(item.date('lot_expires_at'))}' : ''}',
        ),
      (Icons.person_outline, item.str('veterinarian') ?? 'Sin profesional anotado'),
      (Icons.update, item.date('next_due_at') != null ? 'Próxima: ${fmtDate(item.date('next_due_at'))}' : 'Sin próxima aplicación'),
      if (item.str('notes') != null) (Icons.sticky_note_2_outlined, item.str('notes')!),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(isDeworming ? Icons.bug_report_outlined : Icons.vaccines_outlined),
                const SizedBox(width: 12),
                Expanded(child: Text(item.str('name') ?? '', style: Theme.of(context).textTheme.titleLarge)),
              ],
            ),
            const SizedBox(height: 12),
            for (final (icon, text) in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(child: Text(text)),
                  ],
                ),
              ),
            if (reminder != null) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: toneColor(context, 'success'),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => openExternal(context, reminder),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Recordar por WhatsApp'),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (profile.can('vaccinations.delete'))
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                      onPressed: () => Navigator.pop(context, 'delete'),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Eliminar'),
                    ),
                  ),
                if (profile.can('vaccinations.delete') && profile.can('vaccinations.edit')) const SizedBox(width: 8),
                if (profile.can('vaccinations.edit'))
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'edit'),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Corregir'),
                    ),
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

enum NextDueMode { auto, date, none }

/// Próxima aplicación: la calcula el servidor, se elige una fecha o no se programa.
class NextDueField extends StatelessWidget {
  const NextDueField({
    super.key,
    required this.mode,
    required this.date,
    required this.applied,
    required this.autoHint,
    required this.onChanged,
    this.error,
  });

  final NextDueMode mode;
  final DateTime? date;
  final DateTime applied;
  final String autoHint;
  final void Function(NextDueMode mode, DateTime? date) onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Próxima aplicación', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<NextDueMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: NextDueMode.auto, label: Text('Automática')),
            ButtonSegment(value: NextDueMode.date, label: Text('Elegir fecha')),
            ButtonSegment(value: NextDueMode.none, label: Text('No programar')),
          ],
          selected: {mode},
          onSelectionChanged: (s) async {
            final picked = s.first;
            if (picked == NextDueMode.date) {
              final d = await _pick(context);
              if (d != null) onChanged(NextDueMode.date, d);
            } else {
              onChanged(picked, date);
            }
          },
        ),
        const SizedBox(height: 8),
        if (mode == NextDueMode.date)
          InkWell(
            onTap: () async {
              final d = await _pick(context);
              if (d != null) onChanged(NextDueMode.date, d);
            },
            child: InputDecorator(
              decoration: InputDecoration(labelText: 'Fecha', suffixIcon: const Icon(Icons.calendar_today_outlined), errorText: error),
              child: Text(fmtDate(date)),
            ),
          )
        else
          Text(
            mode == NextDueMode.auto ? autoHint : 'No aparecerá en pendientes ni en los recordatorios.',
            style: TextStyle(color: error != null ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        if (error != null && mode != NextDueMode.date) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
    );
  }

  Future<DateTime?> _pick(BuildContext context) {
    final first = applied.add(const Duration(days: 1));
    final initial = date != null && date!.isAfter(applied) ? date! : applied.add(const Duration(days: 30));
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: applied.add(const Duration(days: 365 * 5)),
    );
  }
}

/// Valores del formulario que la API espera para la próxima fecha.
Map<String, dynamic> nextDueBody(NextDueMode mode, DateTime? date) => switch (mode) {
  NextDueMode.date when date != null => {'next_due_at': isoDate(date)},
  NextDueMode.none => {'no_next_due': true},
  _ => {},
};

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onChanged, this.error});

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
          lastDate: DateTime.now(),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_today_outlined), errorText: error),
        child: Text(fmtDate(value)),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saving, required this.label, required this.onPressed});

  final bool saving;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: saving ? null : onPressed,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      child: saving ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(label),
    );
  }
}

Widget _formError(BuildContext context, ApiException? error) => error != null && error.fieldErrors.isEmpty
    ? Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(error.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      )
    : const SizedBox.shrink();

/// Registrar o corregir una vacuna aplicada. Sin fecha elegida, la próxima
/// dosis la calcula el servidor con el protocolo de la vacuna, igual que en la web.
class VaccinateScreen extends StatefulWidget {
  const VaccinateScreen({super.key, required this.petId, required this.petName, this.record});

  final int petId;
  final String petName;

  /// La aplicación a corregir; null para registrar una nueva.
  final Map<String, dynamic>? record;

  @override
  State<VaccinateScreen> createState() => _VaccinateScreenState();
}

class _VaccinateScreenState extends State<VaccinateScreen> {
  late final _r = widget.record ?? const <String, dynamic>{};
  late final _lot = TextEditingController(text: _r.str('lot'));
  late final _notes = TextEditingController(text: _r.str('notes'));
  late int? _vaccineId = _r.integer('vaccine_id');
  late int _dose = _r.integer('dose_number') ?? 1;
  late DateTime _applied = DateUtils.dateOnly(_r.date('applied_at') ?? DateTime.now());
  late NextDueMode _nextMode = widget.record == null
      ? NextDueMode.auto
      : (_r.date('next_due_at') != null ? NextDueMode.date : NextDueMode.none);
  late DateTime? _next = _r.date('next_due_at');
  bool _saving = false;
  ApiException? _error;

  bool get _editing => widget.record != null;

  @override
  void dispose() {
    _lot.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_vaccineId == null) {
      setState(() => _error = ApiException(422, 'Elige la vacuna.', fieldErrors: {'vaccine_id': 'Elige la vacuna.'}));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'vaccine_id': _vaccineId,
      'dose_number': _dose,
      'applied_at': isoDate(_applied),
      'lot': _lot.text.trim().isEmpty ? null : _lot.text.trim(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      if (_editing) 'lot_expires_at': _r.str('lot_expires_at'),
      ...nextDueBody(_nextMode, _next),
    };
    try {
      final api = context.session.api;
      if (_editing) {
        await api.put('/vaccinations/${_r['id']}', body);
      } else {
        await api.post('/pets/${widget.petId}/vaccinations', body);
      }
      if (!mounted) return;
      showDone(context, _editing ? 'Vacuna corregida.' : 'Vacuna registrada.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Corregir vacuna' : 'Vacunar a ${widget.petName}')),
      body: Loader<Map<String, dynamic>>(
        load: () =>
            context.session.api.get('/pets/${widget.petId}/vaccination-options', query: {if (_editing) 'vaccination_id': '${_r['id']}'}),
        builder: (context, options, reload) {
          final vaccines = options.list('vaccines');
          if (vaccines.isEmpty) {
            return ListView(
              children: const [
                EmptyState(icon: Icons.vaccines_outlined, message: 'No hay vacunas del catálogo para esta especie. Cárgalas desde la web.'),
              ],
            );
          }
          final selected = vaccines.where((v) => v['id'] == _vaccineId).firstOrNull;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _formError(context, _error),
              DropdownButtonFormField<int>(
                initialValue: selected == null ? null : _vaccineId,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'Vacuna', errorText: _error?.field('vaccine_id')),
                items: [
                  for (final v in vaccines)
                    DropdownMenuItem(
                      value: v['id'] as int,
                      child: Text(v.str('name') ?? '', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (id) => setState(() {
                  _vaccineId = id;
                  if (!_editing) _dose = vaccines.firstWhere((v) => v['id'] == id).integer('suggested_dose') ?? 1;
                }),
              ),
              if (selected != null) ...[
                const SizedBox(height: 4),
                Text(selected.str('protocol') ?? '', style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(child: Text('Número de dosis')),
                  IconButton.outlined(
                    tooltip: 'Menos',
                    onPressed: _dose > 1 ? () => setState(() => _dose--) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text('$_dose', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                  ),
                  IconButton.outlined(tooltip: 'Más', onPressed: () => setState(() => _dose++), icon: const Icon(Icons.add)),
                ],
              ),
              if (_error?.field('dose_number') != null)
                Text(_error!.field('dose_number')!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              _DateField(
                label: 'Fecha de aplicación',
                value: _applied,
                error: _error?.field('applied_at'),
                onChanged: (d) => setState(() => _applied = d),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _lot,
                decoration: InputDecoration(
                  labelText: 'Lote (opcional)',
                  helperText: _editing ? null : 'Si la vacuna está en el inventario y no anotas lote, se usa el que vence primero.',
                  helperMaxLines: 2,
                  errorText: _error?.field('lot') ?? _error?.field('lot_expires_at'),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Observaciones (opcional)'),
              ),
              const SizedBox(height: 20),
              NextDueField(
                mode: _nextMode,
                date: _next,
                applied: _applied,
                autoHint: 'Se calcula con el protocolo de la vacuna y la dosis.',
                error: _error?.field('next_due_at'),
                onChanged: (mode, date) => setState(() {
                  _nextMode = mode;
                  _next = date;
                }),
              ),
              const SizedBox(height: 24),
              _SaveButton(saving: _saving, label: _editing ? 'Guardar cambios' : 'Registrar vacuna', onPressed: _save),
            ],
          );
        },
      ),
    );
  }
}

/// Registrar o corregir una desparasitación (interna, externa o ambas). Sin
/// fecha elegida, la próxima sale del intervalo del tipo configurado en la web.
class DewormScreen extends StatefulWidget {
  const DewormScreen({super.key, required this.petId, required this.petName, this.record});

  final int petId;
  final String petName;

  /// La desparasitación a corregir; null para registrar una nueva.
  final Map<String, dynamic>? record;

  @override
  State<DewormScreen> createState() => _DewormScreenState();
}

class _DewormScreenState extends State<DewormScreen> {
  late final _r = widget.record ?? const <String, dynamic>{};
  late final _product = TextEditingController(text: _r.str('product'));
  late final _dose = TextEditingController(text: _r.str('dose'));
  late final _weight = TextEditingController(text: _r.number('weight') == null ? '' : fmtNumber(_r.number('weight')));
  late final _notes = TextEditingController(text: _r.str('notes'));
  late String _type = _r.str('type') ?? 'internal';
  int? _inventoryId;
  late DateTime _applied = DateUtils.dateOnly(_r.date('applied_at') ?? DateTime.now());
  late NextDueMode _nextMode = widget.record == null
      ? NextDueMode.auto
      : (_r.date('next_due_at') != null ? NextDueMode.date : NextDueMode.none);
  late DateTime? _next = _r.date('next_due_at');
  bool _weightFilled = false;
  bool _saving = false;
  ApiException? _error;

  bool get _editing => widget.record != null;

  @override
  void dispose() {
    for (final c in [_product, _dose, _weight, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_product.text.trim().isEmpty && _inventoryId == null) {
      setState(() => _error = ApiException(422, 'Anota el producto.', fieldErrors: {'product': 'Anota el producto que se aplicó.'}));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final weight = num.tryParse(_weight.text.replaceAll(',', '.').trim());
    final body = {
      'type': _type,
      'product': _product.text.trim().isEmpty ? null : _product.text.trim(),
      if (!_editing && _inventoryId != null) 'product_id': _inventoryId,
      'dose': _dose.text.trim().isEmpty ? null : _dose.text.trim(),
      'weight': weight,
      'applied_at': isoDate(_applied),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ...nextDueBody(_nextMode, _next),
    };
    try {
      final api = context.session.api;
      if (_editing) {
        await api.put('/dewormings/${_r['id']}', body);
      } else {
        await api.post('/pets/${widget.petId}/dewormings', body);
      }
      if (!mounted) return;
      showDone(context, _editing ? 'Desparasitación corregida.' : 'Desparasitación registrada.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Corregir desparasitación' : 'Desparasitar a ${widget.petName}')),
      body: Loader<Map<String, dynamic>>(
        load: () => context.session.api.get('/pets/${widget.petId}/deworming-options'),
        builder: (context, options, reload) {
          final types = options.list('types');
          final inventory = options.list('inventory_products');
          final interval = types.where((t) => t.str('key') == _type).firstOrNull?.integer('interval_days');
          // El peso actual de la mascota, como punto de partida (una sola vez).
          if (!_editing && !_weightFilled && options.number('last_weight') != null) {
            _weightFilled = true;
            _weight.text = fmtNumber(options.number('last_weight'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _formError(context, _error),
              Text('Tipo', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final t in types)
                    ButtonSegment(value: t.str('key')!, label: Text(t.str('key') == 'both' ? 'Ambas' : t.str('label') ?? '')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              if (_error?.field('type') != null) Text(_error!.field('type')!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              if (!_editing && inventory.isNotEmpty) ...[
                DropdownButtonFormField<int?>(
                  initialValue: _inventoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Producto del inventario (opcional)',
                    helperText: 'Si lo eliges, se descuenta una unidad del stock.',
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('No descontar del inventario')),
                    for (final p in inventory)
                      DropdownMenuItem<int?>(
                        value: p['id'] as int,
                        child: Text(p.str('name') ?? '', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) => setState(() {
                    _inventoryId = id;
                    if (id != null) _product.text = inventory.firstWhere((p) => p['id'] == id).str('name') ?? '';
                  }),
                ),
                const SizedBox(height: 16),
              ],
              SuggestField(
                controller: _product,
                label: 'Producto aplicado',
                suggestions: [for (final s in (options['product_suggestions'] as List? ?? [])) '$s'],
                error: _error?.field('product') ?? _error?.field('product_id'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dose,
                      decoration: InputDecoration(
                        labelText: 'Dosis (opcional)',
                        hintText: '1 comprimido',
                        errorText: _error?.field('dose'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _weight,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Peso (kg)', errorText: _error?.field('weight')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _DateField(
                label: 'Fecha de aplicación',
                value: _applied,
                error: _error?.field('applied_at'),
                onChanged: (d) => setState(() => _applied = d),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Observaciones (opcional)'),
              ),
              const SizedBox(height: 20),
              NextDueField(
                mode: _nextMode,
                date: _next,
                applied: _applied,
                autoHint: interval == null
                    ? 'Se calcula con el intervalo configurado para el tipo.'
                    : 'En $interval días: ${fmtDate(_applied.add(Duration(days: interval)))}.',
                error: _error?.field('next_due_at'),
                onChanged: (mode, date) => setState(() {
                  _nextMode = mode;
                  _next = date;
                }),
              ),
              const SizedBox(height: 24),
              _SaveButton(saving: _saving, label: _editing ? 'Guardar cambios' : 'Registrar desparasitación', onPressed: _save),
            ],
          );
        },
      ),
    );
  }
}
