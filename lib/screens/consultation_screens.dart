import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'hospital_screens.dart' show admitPatient;
import 'lab_screens.dart';
import 'reception_screens.dart';
import 'shell.dart';

/// Abre la consulta en la pantalla que corresponde: el formulario si sigue
/// abierta y quien mira puede editarla; si no, el expediente.
Future<void> openConsultation(BuildContext context, Map<String, dynamic> consultation) {
  final canEdit = context.read<Session>().profile!.can('consultations.edit');
  final id = consultation['id'] as int;
  final route = consultation.flag('is_open') && canEdit
      ? MaterialPageRoute<void>(
          builder: (_) => ConsultationEditor(id: id, initial: consultation),
        )
      : MaterialPageRoute<void>(builder: (_) => ConsultationScreen(id: id));
  return Navigator.of(context).push(route);
}

/// Primer número de un texto libre: «14 comp.» → 14, «1,5 ml» → 1.5.
num? leadingNumber(String? text) {
  final match = RegExp(r'\d+([.,]\d+)?').firstMatch(text ?? '');
  return match == null ? null : num.tryParse(match.group(0)!.replaceAll(',', '.'));
}

// ── Listado: borradores y revisiones ────────────────────────────────────────

/// Consultas (§4): las que quedaron en curso para retomarlas y las
/// revisiones pendientes (vencidas o de hoy) para agendarlas.
class ConsultationsScreen extends StatefulWidget {
  const ConsultationsScreen({super.key});

  @override
  State<ConsultationsScreen> createState() => _ConsultationsScreenState();
}

class _ConsultationsScreenState extends State<ConsultationsScreen> {
  bool _mine = false;
  int _version = 0;

  Future<void> _open(int id) async {
    try {
      final detail = await context.session.api.get('/consultations/$id');
      if (!mounted) return;
      await openConsultation(context, detail);
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => _version++);
  }

  Future<void> _schedule(Map<String, dynamic> c) async {
    final saved = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) =>
            AppointmentFormScreen(pet: c.obj('pet'), reason: 'Revisión: ${c.str('primary_diagnosis') ?? c.str('reason') ?? ''}'.trim()),
      ),
    );
    if (saved != null && mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final canSchedule = profile.canUse('agenda', 'appointments.create');

    Widget tile(Map<String, dynamic> c, {required bool review}) {
      final pet = c.obj('pet') ?? {};
      return ListTile(
        onTap: () => _open(c['id'] as int),
        leading: PetAvatar(name: pet.str('name') ?? '?', photoUrl: pet.str('photo_url')),
        title: Text(
          [pet.str('name'), c.str('primary_diagnosis') ?? c.str('reason')].whereType<String>().join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            review ? 'Revisión ${fmtDate(c.date('next_review_at'))}' : 'Abierta ${fmtAgo(c.date('started_at'))}',
            c.str('veterinarian'),
            pet.obj('owner')?.str('name'),
          ].whereType<String>().join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: review && canSchedule
            ? IconButton.filledTonal(tooltip: 'Agendar revisión', onPressed: () => _schedule(c), icon: const Icon(Icons.event_outlined))
            : const Icon(Icons.chevron_right),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: shellMenuButton(context),
          title: const Text('Consultas'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'En curso'),
              Tab(text: 'Revisiones'),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(label: const Text('Mías'), selected: _mine, onSelected: (v) => setState(() => _mine = v)),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            PagedList(
              key: ValueKey('open-$_mine-$_version'),
              path: '/consultations',
              term: '',
              query: {'status': 'in_progress', 'mine': _mine ? '1' : null},
              empty: 'No hay consultas en curso.',
              count: (n) => n == 1 ? '1 consulta en curso' : '$n consultas en curso',
              itemBuilder: (context, c) => tile(c, review: false),
            ),
            PagedList(
              key: ValueKey('review-$_mine-$_version'),
              path: '/consultations',
              term: '',
              query: {'review': 'due', 'mine': _mine ? '1' : null},
              empty: 'No hay revisiones pendientes.',
              count: (n) => n == 1 ? '1 revisión pendiente' : '$n revisiones pendientes',
              itemBuilder: (context, c) => tile(c, review: true),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Expediente ──────────────────────────────────────────────────────────────

/// Expediente de una consulta (§17.3): evaluación, signos vitales,
/// diagnósticos, receta (compartir en PDF, dispensar), procedimientos,
/// insumos y seguimiento.
class ConsultationScreen extends StatefulWidget {
  const ConsultationScreen({super.key, required this.id});

  final int id;

  @override
  State<ConsultationScreen> createState() => _ConsultationScreenState();
}

class _ConsultationScreenState extends State<ConsultationScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  Map<String, dynamic>? _current;
  bool _sharing = false;
  int? _dispensing;

  Future<void> _followup() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FollowupSheet(consultationId: widget.id),
    );
    if (saved == true) _loader.currentState?.reload();
  }

  /// Descarga la receta en PDF y abre el menú del teléfono para enviarla (WhatsApp, correo…).
  Future<void> _share() async {
    final c = _current;
    if (c == null) return;
    setState(() => _sharing = true);
    try {
      final bytes = await context.session.api.download('/consultations/${widget.id}/prescription.pdf');
      final pet = c.obj('pet')?.str('name') ?? 'paciente';
      final name = 'Receta-${c.str('prescription_number') ?? widget.id}-$pet.pdf';
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(Uint8List.fromList(bytes), mimeType: 'application/pdf', name: name)],
          fileNameOverrides: [name],
          text: 'Receta de $pet',
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e is ApiException ? e : 'No se pudo compartir la receta.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Entrega un medicamento vinculado al inventario y lo descuenta del stock.
  Future<void> _dispense(Map<String, dynamic> item) async {
    final quantity = await showDialog<num>(
      context: context,
      builder: (_) => _QuantityDialog(title: 'Dispensar ${item.str('medication')}', initial: leadingNumber(item.str('quantity')) ?? 1),
    );
    if (quantity == null || !mounted) return;

    setState(() => _dispensing = item['id'] as int);
    try {
      await context.session.api.post('/consultations/${widget.id}/prescription/${item['id']}/dispense', {'quantity': quantity});
      if (mounted) showDone(context, 'Dispensado: ${item.str('medication')}.');
      _loader.currentState?.reload();
    } on ApiException catch (e) {
      if (mounted) showError(context, e.field('quantity') ?? e.message);
    } finally {
      if (mounted) setState(() => _dispensing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final canEdit = profile.can('consultations.edit');
    final canDispense = profile.has('inventario') && (profile.can('inventory.create') || profile.can('consultations.edit'));
    final open = _current?.flag('is_open') ?? false;
    final hasPrescription = (_current?.list('prescription') ?? const []).isNotEmpty || (_current?.str('instructions') ?? '').isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Consulta'),
        actions: [
          if (_current != null && hasPrescription)
            IconButton(
              tooltip: 'Compartir receta (PDF)',
              onPressed: _sharing ? null : _share,
              icon: _sharing
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.share_outlined),
            ),
        ],
      ),
      floatingActionButton: canEdit && _current != null && !open
          ? FloatingActionButton.extended(onPressed: _followup, icon: const Icon(Icons.timeline), label: const Text('Seguimiento'))
          : null,
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () async {
          final data = await context.session.api.get('/consultations/${widget.id}');
          if (mounted) setState(() => _current = data);
          return data;
        },
        builder: (context, c, reload) {
          final vitals = c.obj('vitals') ?? {};
          final vitalFacts = {
            'Temperatura': vitals.number('temperature') == null ? null : '${fmtNumber(vitals.number('temperature'))} °C',
            'Peso': vitals.number('weight') == null ? null : '${fmtNumber(vitals.number('weight'))} kg',
            'Frec. cardíaca': vitals.integer('heart_rate') == null ? null : '${vitals.integer('heart_rate')} lpm',
            'Frec. respiratoria': vitals.integer('respiratory_rate') == null ? null : '${vitals.integer('respiratory_rate')} rpm',
            'Hidratación': vitals.str('hydration'),
            'Condición corporal': vitals.integer('body_condition') == null ? null : '${vitals.integer('body_condition')}/9',
            'Mucosas': vitals.str('mucous_membranes'),
          }..removeWhere((_, v) => v == null);
          final text = {
            'Motivo': c.str('reason'),
            'Anamnesis': c.str('anamnesis'),
            'Examen físico': c.str('physical_exam'),
            'Notas clínicas': c.str('clinical_notes'),
          }..removeWhere((_, v) => v == null || v.isEmpty);
          final currency = profile.company?.currencySymbol ?? '';

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text(fmtDayLong(c.date('started_at') ?? DateTime.now()), style: Theme.of(context).textTheme.titleLarge),
              Text([c.obj('pet')?.str('name'), c.str('veterinarian')].whereType<String>().join(' · ')),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: StatusChip(c.obj('status_badge')?.str('label') ?? '', tone: c.obj('status_badge')?.str('color')),
              ),
              if (c.flag('is_open') && canEdit) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ConsultationEditor(id: widget.id, initial: c),
                      ),
                    );
                    reload();
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Continuar consulta'),
                ),
              ],
              for (final t in text.entries) ...[SectionTitle(t.key), Text(t.value!)],
              if (vitalFacts.isNotEmpty) ...[
                const SectionTitle('Signos vitales'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(spacing: 24, runSpacing: 12, children: [for (final f in vitalFacts.entries) Fact(f.key, f.value!)]),
                  ),
                ),
              ],
              if (c.list('diagnoses').isNotEmpty) ...[
                const SectionTitle('Diagnósticos'),
                for (final d in c.list('diagnoses'))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.medical_information_outlined),
                    title: Text(d.str('description') ?? ''),
                    subtitle: Text([d.str('type_label'), d.str('notes')].whereType<String>().join(' · ')),
                  ),
              ],
              if (c.list('prescription').isNotEmpty) ...[
                SectionTitle(
                  'Receta ${c.str('prescription_number') ?? ''}'.trim(),
                  trailing: TextButton.icon(
                    onPressed: _sharing ? null : _share,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('Compartir'),
                  ),
                ),
                for (final p in c.list('prescription'))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.medication_outlined),
                    title: Text([p.str('medication'), p.str('presentation')].whereType<String>().join(' · ')),
                    subtitle: Text(
                      [
                        [p.str('dose'), p.str('route'), p.str('frequency'), p.str('duration')].whereType<String>().join(' · '),
                        if (p.str('quantity') != null) 'Cantidad: ${p.str('quantity')}',
                        p.str('instructions'),
                      ].whereType<String>().where((s) => s.isNotEmpty).join('\n'),
                    ),
                    trailing: p.str('dispensed_at') != null
                        ? StatusChip('Entregado ${fmtNumber(p.number('dispensed_quantity'))}', tone: 'success')
                        : (canDispense && !c.flag('is_open') && p['product_id'] != null)
                        ? OutlinedButton(
                            onPressed: _dispensing == null ? () => _dispense(p) : null,
                            child: _dispensing == p['id']
                                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Dispensar'),
                          )
                        : null,
                  ),
              ],
              if (c.list('procedures').isNotEmpty) ...[
                const SectionTitle('Procedimientos'),
                for (final p in c.list('procedures'))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.healing_outlined),
                    title: Text(p.str('name') ?? ''),
                    subtitle: Text(
                      [
                        p.str('description'),
                        p.str('materials') == null ? null : 'Materiales: ${p.str('materials')}',
                        p.str('performed_by'),
                      ].whereType<String>().join('\n'),
                    ),
                    trailing: (p.number('cost') ?? 0) > 0 ? Text('$currency ${fmtNumber(p.number('cost'))}'.trim()) : null,
                  ),
              ],
              if (c.list('supplies').isNotEmpty) ...[
                const SectionTitle('Insumos usados'),
                for (final s in c.list('supplies'))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(s.str('product') ?? ''),
                    subtitle: s.str('notes') == null ? null : Text(s.str('notes')!),
                    trailing: Text('${fmtNumber(s.number('quantity'))} ${s.str('unit') ?? ''}'.trim()),
                  ),
              ],
              if ((c.str('instructions') ?? '').isNotEmpty) ...[const SectionTitle('Indicaciones'), Text(c.str('instructions')!)],
              if ((c.str('recommendations') ?? '').isNotEmpty) ...[const SectionTitle('Recomendaciones'), Text(c.str('recommendations')!)],
              if (c.str('next_review_at') != null) ...[const SectionTitle('Próxima revisión'), Text(fmtDate(c.date('next_review_at')))],
              ConsultationLabSection(consultation: c, onChanged: reload),
              if (c.list('followups').isNotEmpty) ...[
                const SectionTitle('Seguimiento'),
                for (final f in c.list('followups'))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.timeline),
                    title: Text(f.str('status_label') ?? ''),
                    subtitle: Text(
                      [
                        [fmtDateTime(f.date('recorded_at')), f.str('recorded_by')].whereType<String>().join(' · '),
                        f.str('notes'),
                      ].whereType<String>().join('\n'),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Seguimiento de una consulta finalizada: cómo evoluciona el tratamiento.
class _FollowupSheet extends StatefulWidget {
  const _FollowupSheet({required this.consultationId});

  final int consultationId;

  @override
  State<_FollowupSheet> createState() => _FollowupSheetState();
}

class _FollowupSheetState extends State<_FollowupSheet> {
  final _notes = TextEditingController();
  String _status = 'improving';
  bool _saving = false;
  ApiException? _error;

  static const _statuses = {
    'in_course': 'En curso',
    'improving': 'Mejorando',
    'unchanged': 'Sin cambios',
    'worsening': 'Empeorando',
    'resolved': 'Resuelto',
  };

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.session.api.post('/consultations/${widget.consultationId}/followups', {
        'treatment_status': _status,
        'notes': _notes.text.trim(),
      });
      if (!mounted) return;
      showDone(context, 'Seguimiento registrado.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Nuevo seguimiento', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _statuses.entries)
                ChoiceChip(label: Text(s.value), selected: _status == s.key, onSelected: (_) => setState(() => _status = s.key)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 4,
            autofocus: true,
            decoration: InputDecoration(labelText: '¿Cómo sigue el paciente?', errorText: _error?.field('notes')),
          ),
          if (_error != null && _error!.fieldErrors.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: _saving
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Guardar seguimiento'),
          ),
        ],
      ),
    );
  }
}

// ── Formulario de la consulta ───────────────────────────────────────────────

class _DiagnosisRow {
  _DiagnosisRow({this.type = 'primary', String? description, String? notes})
    : description = TextEditingController(text: description),
      notes = TextEditingController(text: notes);

  String type;
  final TextEditingController description;
  final TextEditingController notes;

  void dispose() {
    description.dispose();
    notes.dispose();
  }
}

class _PrescriptionRow {
  _PrescriptionRow([Map<String, dynamic>? data])
    : route = data?.str('route') ?? 'oral',
      productId = data?.integer('product_id'),
      fields = {
        for (final key in ['medication', 'presentation', 'dose', 'frequency', 'duration', 'quantity', 'instructions'])
          key: TextEditingController(text: data?.str(key)),
      };

  String route;
  int? productId;
  final Map<String, TextEditingController> fields;

  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
  }
}

class _ProcedureRow {
  _ProcedureRow([Map<String, dynamic>? data])
    : performedBy = data?.integer('performed_by'),
      fields = {
        for (final key in ['name', 'description', 'materials', 'medications']) key: TextEditingController(text: data?.str(key)),
        'cost': TextEditingController(
          text: data?.number('cost') == null || data!.number('cost') == 0 ? '' : fmtNumber(data.number('cost')).replaceAll('.', ''),
        ),
      };

  int? performedBy;
  final Map<String, TextEditingController> fields;

  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
  }
}

class _SupplyRow {
  _SupplyRow({required this.productId, num? quantity, String? notes})
    : quantity = TextEditingController(text: quantity == null ? '1' : fmtNumber(quantity).replaceAll('.', '')),
      notes = TextEditingController(text: notes);

  int productId;
  final TextEditingController quantity;
  final TextEditingController notes;

  void dispose() {
    quantity.dispose();
    notes.dispose();
  }
}

/// Registrar la consulta (§17.4). Guarda borradores y la finaliza con las
/// mismas reglas que la web: para cerrarla hace falta un diagnóstico principal.
class ConsultationEditor extends StatefulWidget {
  const ConsultationEditor({super.key, required this.id, required this.initial});

  final int id;

  /// Detalle de la consulta tal como lo devuelve la API (con `form`).
  final Map<String, dynamic> initial;

  @override
  State<ConsultationEditor> createState() => _ConsultationEditorState();
}

class _ConsultationEditorState extends State<ConsultationEditor> {
  static const _textKeys = ['reason', 'anamnesis', 'physical_exam', 'clinical_notes', 'instructions', 'recommendations'];
  static const _numberKeys = ['temperature', 'weight', 'heart_rate', 'respiratory_rate'];

  final _text = <String, TextEditingController>{};
  final _numbers = <String, TextEditingController>{};
  final _diagnoses = <_DiagnosisRow>[];
  final _prescription = <_PrescriptionRow>[];
  final _procedures = <_ProcedureRow>[];
  final _supplies = <_SupplyRow>[];

  /// Nombres de productos ya conocidos (de los insumos guardados y del catálogo).
  final _productNames = <int, String>{};
  String? _hydration;
  String? _mucous;
  String? _bodyCondition;
  DateTime? _nextReview;

  Map<String, dynamic>? _options;
  ApiException? _error;
  String? _busy; // 'save' | 'finish' | 'discard'
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _fill(widget.initial.obj('form') ?? {});
    _loadOptions();
  }

  void _fill(Map<String, dynamic> form) {
    for (final key in _textKeys) {
      _text[key] = TextEditingController(text: form.str(key))..addListener(_touch);
    }
    for (final key in _numberKeys) {
      final value = form.number(key);
      _numbers[key] = TextEditingController(text: value == null ? '' : fmtNumber(value).replaceAll('.', ''))..addListener(_touch);
    }
    _hydration = form.str('hydration');
    _mucous = form.str('mucous_membranes');
    _bodyCondition = form.str('body_condition');
    _nextReview = form.date('next_review_at');
    for (final d in form.list('diagnoses')) {
      _diagnoses.add(
        _DiagnosisRow(type: d.str('type') ?? 'primary', description: d.str('description'), notes: d.str('notes'))
          ..description.addListener(_touch),
      );
    }
    for (final p in form.list('prescription')) {
      _prescription.add(_PrescriptionRow(p)..fields.values.forEach((c) => c.addListener(_touch)));
    }
    for (final p in form.list('procedures')) {
      _procedures.add(_ProcedureRow(p)..fields.values.forEach((c) => c.addListener(_touch)));
    }
    final supplyNames = widget.initial.list('supplies');
    for (final (i, s) in form.list('supplies').indexed) {
      final id = s.integer('product_id');
      if (id == null) continue;
      if (i < supplyNames.length && supplyNames[i].str('product') != null) _productNames[id] = supplyNames[i].str('product')!;
      _supplies.add(_SupplyRow(productId: id, quantity: s.number('quantity'), notes: s.str('notes'))..quantity.addListener(_touch));
    }
  }

  Future<void> _loadOptions() async {
    try {
      final options = await context.session.api.get('/consultations/options');
      if (!mounted) return;
      setState(() {
        _options = options;
        for (final p in options.list('products')) {
          _productNames[p['id'] as int] = [p.str('name'), p.str('presentation')].whereType<String>().join(' · ');
        }
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _touch() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    for (final c in [..._text.values, ..._numbers.values]) {
      c.dispose();
    }
    for (final d in _diagnoses) {
      d.dispose();
    }
    for (final p in _prescription) {
      p.dispose();
    }
    for (final p in _procedures) {
      p.dispose();
    }
    for (final s in _supplies) {
      s.dispose();
    }
    super.dispose();
  }

  String? _value(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  num? _parse(TextEditingController c) => num.tryParse(c.text.replaceAll(',', '.').trim());

  num? _number(String key) => _parse(_numbers[key]!);

  Map<String, dynamic> _payload({required bool finish}) => {
    for (final key in _textKeys) key: _value(_text[key]!),
    'temperature': _number('temperature'),
    'weight': _number('weight'),
    'heart_rate': _number('heart_rate')?.toInt(),
    'respiratory_rate': _number('respiratory_rate')?.toInt(),
    'hydration': _hydration,
    'mucous_membranes': _mucous,
    'body_condition': _bodyCondition,
    'next_review_at': _nextReview == null ? null : isoDate(_nextReview!),
    'diagnoses': [
      for (final d in _diagnoses)
        if (_value(d.description) != null) {'type': d.type, 'description': _value(d.description), 'notes': _value(d.notes)},
    ],
    'prescription': [
      for (final p in _prescription)
        if (_value(p.fields['medication']!) != null)
          {for (final e in p.fields.entries) e.key: _value(e.value), 'route': p.route, 'product_id': p.productId},
    ],
    'procedures': [
      for (final p in _procedures)
        if (_value(p.fields['name']!) != null)
          {
            for (final key in ['name', 'description', 'materials', 'medications']) key: _value(p.fields[key]!),
            'performed_by': p.performedBy,
            'cost': _parse(p.fields['cost']!) ?? 0,
          },
    ],
    'supplies': [
      for (final s in _supplies) {'product_id': s.productId, 'quantity': _parse(s.quantity), 'notes': _value(s.notes)},
    ],
    'finish': finish,
  };

  Future<void> _save({required bool finish}) async {
    if (finish) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Finalizar la consulta?'),
          content: const Text(
            'Queda cerrada en el expediente: después solo se pueden agregar seguimientos. El peso pasa al historial y los insumos se descuentan del inventario.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Seguir editando')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Finalizar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;

    setState(() {
      _busy = finish ? 'finish' : 'save';
      _error = null;
    });
    try {
      await context.session.api.put('/consultations/${widget.id}', _payload(finish: finish));
      if (!mounted) return;
      _dirty = false;
      if (finish) {
        showDone(context, 'Consulta finalizada.');
        // Al expediente: desde ahí se comparte la receta y se dispensa.
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ConsultationScreen(id: widget.id)));
      } else {
        showDone(context, 'Borrador guardado.');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      showError(context, e.fieldErrors.isEmpty ? e : 'Revisa los campos marcados.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Guarda el borrador y abre el ingreso: motivo y diagnóstico se proponen desde la consulta.
  Future<void> _admit() async {
    await _save(finish: false);
    if (!mounted || _error != null) return;
    await admitPatient(context, pet: widget.initial.obj('pet'), consultationId: widget.id);
  }

  Future<void> _discard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Descartar el borrador?'),
        content: const Text('La consulta se elimina con todo lo cargado. Si vino de una cita, la cita queda como estaba.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = 'discard');
    try {
      await context.session.api.delete('/consultations/${widget.id}');
      if (!mounted) return;
      _dirty = false;
      showDone(context, 'Borrador descartado.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Salir sin guardar?'),
        content: const Text('Los cambios que no guardaste se perderán. La consulta sigue abierta como borrador.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Quedarme')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salir')),
        ],
      ),
    );
    return leave == true;
  }

  List<Map<String, dynamic>> _opt(String key) => _options?.list(key) ?? const [];

  List<String> _suggestions(String key) => [for (final s in (_options?[key] as List? ?? const [])) '$s'];

  /// Buscador de productos del inventario. Devuelve el elegido o null.
  Future<Map<String, dynamic>?> _pickProduct(String title) {
    final products = _opt('products');
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        var term = '';
        return StatefulBuilder(
          builder: (context, setSheet) {
            final words = term.toLowerCase().split(' ').where((w) => w.isNotEmpty);
            final shown = products
                .where((p) => words.every((w) => '${p.str('name')} ${p.str('presentation') ?? ''}'.toLowerCase().contains(w)))
                .take(50)
                .toList();
            return SizedBox(
              height: MediaQuery.sizeOf(context).height * .75,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      autofocus: true,
                      decoration: InputDecoration(labelText: title, prefixIcon: const Icon(Icons.search)),
                      onChanged: (v) => setSheet(() => term = v),
                    ),
                  ),
                  Expanded(
                    child: shown.isEmpty
                        ? const EmptyState(icon: Icons.search_off, message: 'No hay productos con ese nombre.')
                        : ListView(
                            children: [
                              for (final p in shown)
                                ListTile(
                                  leading: const Icon(Icons.inventory_2_outlined),
                                  title: Text(p.str('name') ?? ''),
                                  subtitle: Text([p.str('presentation'), p.str('unit')].whereType<String>().join(' · ')),
                                  onTap: () => Navigator.pop(context, p),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _addSupply() async {
    final product = await _pickProduct('Buscar insumo');
    if (product == null) return;
    setState(() {
      _supplies.add(_SupplyRow(productId: product['id'] as int)..quantity.addListener(_touch));
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pet = widget.initial.obj('pet') ?? {};
    final errors = _error?.fieldErrors ?? const <String, String>{};
    final profile = context.watch<Session>().profile!;
    final inventory = _opt('products').isNotEmpty;
    final canRequestLab = profile.canUse('laboratorio', 'lab_requests.create');
    final canAdmit = profile.canUse('hospitalizacion', 'hospitalizations.create');

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmLeave()) {
          _dirty = false;
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Consulta · ${pet.str('name') ?? ''}'),
          actions: [
            TextButton(onPressed: _busy == null ? () => _save(finish: false) : null, child: const Text('Guardar')),
            if (profile.can('consultations.delete') || canRequestLab || canAdmit)
              PopupMenuButton<String>(
                tooltip: 'Más acciones',
                onSelected: (v) => switch (v) {
                  'lab' => requestLabFor(context, {...widget.initial, 'id': widget.id}),
                  'admit' => _admit(),
                  _ => _discard(),
                },
                itemBuilder: (context) => [
                  if (canAdmit)
                    const PopupMenuItem(
                      value: 'admit',
                      child: ListTile(leading: Icon(Icons.local_hospital_outlined), title: Text('Internar')),
                    ),
                  if (canRequestLab)
                    const PopupMenuItem(
                      value: 'lab',
                      child: ListTile(leading: Icon(Icons.biotech_outlined), title: Text('Solicitar estudio')),
                    ),
                  if (profile.can('consultations.delete'))
                    const PopupMenuItem(
                      value: 'discard',
                      child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Descartar borrador')),
                    ),
                ],
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy == null ? () => _save(finish: true) : null,
              icon: _busy == 'finish'
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.task_alt),
              label: const Text('Finalizar consulta'),
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (_error != null && errors.isEmpty) _ErrorBanner(_error!.message),
            if (errors.isNotEmpty) _ErrorBanner('Revisa: ${errors.values.toSet().join(' ')}'),

            // ── Evaluación ──
            const SectionTitle('Evaluación clínica'),
            _textField('reason', 'Motivo de consulta', errors),
            _textField('anamnesis', 'Anamnesis', errors, lines: 3),
            _textField('physical_exam', 'Examen físico', errors, lines: 3),

            // ── Signos vitales ──
            const SectionTitle('Signos vitales'),
            Row(
              children: [
                _numberField('temperature', 'Temperatura', '°C', errors),
                const SizedBox(width: 12),
                _numberField('weight', 'Peso', 'kg', errors),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _numberField('heart_rate', 'Frec. cardíaca', 'lpm', errors, decimal: false),
                const SizedBox(width: 12),
                _numberField('respiratory_rate', 'Frec. resp.', 'rpm', errors, decimal: false),
              ],
            ),
            const SizedBox(height: 12),
            _dropdown('Hidratación', _hydration, _opt('hydration'), (v) => _hydration = v, errors['hydration']),
            const SizedBox(height: 12),
            _dropdown('Mucosas', _mucous, _opt('mucous_membranes'), (v) => _mucous = v, errors['mucous_membranes']),
            const SizedBox(height: 12),
            _dropdown(
              'Condición corporal (1–9)',
              _bodyCondition,
              _opt('body_condition'),
              (v) => _bodyCondition = v,
              errors['body_condition'],
            ),
            const SizedBox(height: 12),
            _textField('clinical_notes', 'Notas clínicas', errors, lines: 2),

            // ── Diagnósticos ──
            SectionTitle(
              'Diagnósticos',
              trailing: TextButton.icon(
                onPressed: () => setState(() {
                  _diagnoses.add(_DiagnosisRow(type: _diagnoses.isEmpty ? 'primary' : 'secondary')..description.addListener(_touch));
                  _dirty = true;
                }),
                icon: const Icon(Icons.add),
                label: const Text('Agregar'),
              ),
            ),
            if (errors['diagnoses'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(errors['diagnoses']!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (_diagnoses.isEmpty) const Text('Para finalizar hace falta al menos un diagnóstico principal.'),
            for (final (i, d) in _diagnoses.indexed) _diagnosisCard(i, d),

            // ── Tratamiento y receta ──
            SectionTitle(
              'Tratamiento y receta',
              trailing: TextButton.icon(
                onPressed: () => setState(() {
                  _prescription.add(_PrescriptionRow()..fields.values.forEach((c) => c.addListener(_touch)));
                  _dirty = true;
                }),
                icon: const Icon(Icons.add),
                label: const Text('Medicamento'),
              ),
            ),
            if (_prescription.isEmpty) const Text('Sin medicamentos recetados.'),
            for (final (i, p) in _prescription.indexed) _prescriptionCard(i, p, errors, inventory),

            // ── Procedimientos ──
            SectionTitle(
              'Procedimientos',
              trailing: TextButton.icon(
                onPressed: () => setState(() {
                  _procedures.add(_ProcedureRow({'performed_by': profile.userId})..fields.values.forEach((c) => c.addListener(_touch)));
                  _dirty = true;
                }),
                icon: const Icon(Icons.add),
                label: const Text('Procedimiento'),
              ),
            ),
            if (_procedures.isEmpty) const Text('Curaciones, suturas, limpiezas, cirugías menores…'),
            for (final (i, p) in _procedures.indexed) _procedureCard(i, p, errors),

            // ── Insumos ──
            if (inventory || _supplies.isNotEmpty) ...[
              SectionTitle(
                'Insumos usados',
                trailing: inventory
                    ? TextButton.icon(onPressed: _addSupply, icon: const Icon(Icons.add), label: const Text('Insumo'))
                    : null,
              ),
              if (_supplies.isEmpty) const Text('Lo que se usó del inventario se descuenta al finalizar.'),
              for (final (i, s) in _supplies.indexed) _supplyRow(i, s, errors),
            ],

            // ── Indicaciones ──
            const SectionTitle('Indicaciones al propietario'),
            _textField('instructions', 'Indicaciones (van en la receta)', errors, lines: 3),
            _textField('recommendations', 'Recomendaciones', errors, lines: 2),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _nextReview ?? DateTime.now().add(const Duration(days: 7)),
                  firstDate: DateUtils.dateOnly(DateTime.now()),
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                );
                if (picked != null) {
                  setState(() {
                    _nextReview = picked;
                    _dirty = true;
                  });
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Próxima revisión',
                  errorText: errors['next_review_at'],
                  suffixIcon: _nextReview == null
                      ? const Icon(Icons.calendar_today_outlined)
                      : IconButton(
                          tooltip: 'Quitar',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _nextReview = null;
                            _dirty = true;
                          }),
                        ),
                ),
                child: Text(_nextReview == null ? 'Sin revisión programada' : fmtDate(_nextReview)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textField(String key, String label, Map<String, String> errors, {int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: _text[key],
      minLines: lines,
      maxLines: lines == 1 ? 1 : 8,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(labelText: label, alignLabelWithHint: lines > 1, errorText: errors[key]),
    ),
  );

  Widget _numberField(String key, String label, String suffix, Map<String, String> errors, {bool decimal = true}) => Expanded(
    child: TextField(
      controller: _numbers[key],
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      decoration: InputDecoration(labelText: label, suffixText: suffix, errorText: errors[key], errorMaxLines: 3),
    ),
  );

  Widget _dropdown(String label, String? value, List<Map<String, dynamic>> items, void Function(String?) onChanged, String? error) {
    final keys = items.map((i) => i.str('key')).toSet();
    return DropdownButtonFormField<String>(
      initialValue: keys.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, errorText: error),
      items: [
        const DropdownMenuItem(value: null, child: Text('—')),
        for (final i in items)
          DropdownMenuItem(
            value: i.str('key'),
            child: Text(i.str('label') ?? '', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => setState(() {
        onChanged(v);
        _dirty = true;
      }),
    );
  }

  Widget _removeButton(String tooltip, VoidCallback onPressed) => IconButton(
    tooltip: tooltip,
    onPressed: () => setState(() {
      onPressed();
      _dirty = true;
    }),
    icon: const Icon(Icons.delete_outline),
  );

  Widget _diagnosisCard(int i, _DiagnosisRow d) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      for (final t
                          in _opt('diagnosis_types').isEmpty
                              ? [
                                  {'key': 'primary', 'label': 'Principal'},
                                  {'key': 'secondary', 'label': 'Secundario'},
                                  {'key': 'differential', 'label': 'Diferencial'},
                                ]
                              : _opt('diagnosis_types'))
                        ButtonSegment(
                          value: '${t['key']}',
                          label: Text('${t['label']}', style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                    selected: {d.type},
                    onSelectionChanged: (v) => setState(() {
                      d.type = v.first;
                      _dirty = true;
                    }),
                  ),
                ),
                _removeButton('Quitar diagnóstico', () => _diagnoses.removeAt(i).dispose()),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SuggestField(
                controller: d.description,
                label: 'Diagnóstico',
                suggestions: _suggestions('diagnosis_suggestions'),
                error: _error?.field('diagnoses.$i.description'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _prescriptionCard(int i, _PrescriptionRow p, Map<String, String> errors, bool inventory) {
    final f = p.fields;
    Widget field(String key, String label, {int flex = 1}) => Expanded(
      flex: flex,
      child: TextField(
        controller: f[key],
        decoration: InputDecoration(labelText: label, errorText: errors['prescription.$i.$key'], errorMaxLines: 2),
      ),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SuggestField(
                    controller: f['medication']!,
                    label: 'Medicamento',
                    suggestions: _suggestions('medication_suggestions'),
                    error: errors['prescription.$i.medication'],
                  ),
                ),
                _removeButton('Quitar medicamento', () => _prescription.removeAt(i).dispose()),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                children: [
                  if (inventory || p.productId != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: p.productId == null
                          ? TextButton.icon(
                              onPressed: () async {
                                final product = await _pickProduct('Buscar en el inventario');
                                if (product == null) return;
                                setState(() {
                                  p.productId = product['id'] as int;
                                  if (_value(f['medication']!) == null) f['medication']!.text = product.str('name') ?? '';
                                  if (_value(f['presentation']!) == null) f['presentation']!.text = product.str('presentation') ?? '';
                                  _dirty = true;
                                });
                              },
                              icon: const Icon(Icons.link, size: 18),
                              label: const Text('Vincular al inventario'),
                            )
                          : Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: InputChip(
                                avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                                label: Text(_productNames[p.productId] ?? 'Producto del inventario', overflow: TextOverflow.ellipsis),
                                tooltip: 'Se podrá dispensar y descontar del stock',
                                onDeleted: () => setState(() {
                                  p.productId = null;
                                  _dirty = true;
                                }),
                              ),
                            ),
                    ),
                  const SizedBox(height: 8),
                  Row(children: [field('presentation', 'Presentación')]),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      field('dose', 'Dosis'),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: p.route,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Vía'),
                          items: [
                            for (final r
                                in _opt('routes').isEmpty
                                    ? [
                                        {'key': p.route, 'label': p.route},
                                      ]
                                    : _opt('routes'))
                              DropdownMenuItem(
                                value: '${r['key']}',
                                child: Text('${r['label']}', overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (v) => setState(() {
                            p.route = v ?? 'oral';
                            _dirty = true;
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(children: [field('frequency', 'Frecuencia'), const SizedBox(width: 8), field('duration', 'Duración')]),
                  const SizedBox(height: 8),
                  Row(children: [field('quantity', 'Cantidad'), const SizedBox(width: 8), field('instructions', 'Indicaciones', flex: 2)]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _procedureCard(int i, _ProcedureRow p, Map<String, String> errors) {
    final professionals = _opt('professionals');
    final currency = context.read<Session>().profile!.company?.currencySymbol;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: p.fields['name'],
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(labelText: 'Procedimiento', errorText: errors['procedures.$i.name']),
                  ),
                ),
                _removeButton('Quitar procedimiento', () => _procedures.removeAt(i).dispose()),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  TextField(
                    controller: p.fields['description'],
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: p.fields['materials'],
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Materiales (opcional)'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<int>(
                          initialValue: professionals.any((u) => u['id'] == p.performedBy) ? p.performedBy : null,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: 'Realizó', errorText: errors['procedures.$i.performed_by']),
                          items: [
                            const DropdownMenuItem<int>(value: null, child: Text('—')),
                            for (final u in professionals)
                              DropdownMenuItem(
                                value: u['id'] as int,
                                child: Text(u.str('name') ?? '', overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (v) => setState(() {
                            p.performedBy = v;
                            _dirty = true;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: p.fields['cost'],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Costo',
                            prefixText: currency == null ? null : '$currency ',
                            errorText: errors['procedures.$i.cost'],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _supplyRow(int i, _SupplyRow s, Map<String, String> errors) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_productNames[s.productId] ?? 'Producto #${s.productId}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              child: TextField(
                controller: s.quantity,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Cantidad', errorText: errors['supplies.$i.quantity'], errorMaxLines: 3),
              ),
            ),
            _removeButton('Quitar insumo', () => _supplies.removeAt(i).dispose()),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
      ),
    );
  }
}

/// Campo de texto con sugerencias de lo que la veterinaria ya usó antes.
class SuggestField extends StatefulWidget {
  const SuggestField({super.key, required this.controller, required this.label, required this.suggestions, this.error});

  final TextEditingController controller;
  final String label;
  final List<String> suggestions;
  final String? error;

  @override
  State<SuggestField> createState() => _SuggestFieldState();
}

class _SuggestFieldState extends State<SuggestField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (value) {
        final term = value.text.trim().toLowerCase();
        if (term.length < 2) return const [];
        return widget.suggestions.where((s) => s.toLowerCase().contains(term) && s.toLowerCase() != term).take(6);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) => TextField(
        controller: controller,
        focusNode: focusNode,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: widget.label, errorText: widget.error),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [for (final o in options) ListTile(dense: true, title: Text(o), onTap: () => onSelected(o))],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pide una cantidad. Dueño de su controlador: se libera cuando el diálogo termina de cerrarse.
class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({required this.title, required this.initial});

  final String title;
  final num initial;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late final _controller = TextEditingController(text: fmtNumber(widget.initial).replaceAll('.', ''));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Cantidad entregada', helperText: 'Se descuenta del inventario de la sucursal.'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, num.tryParse(_controller.text.replaceAll(',', '.').trim())),
          child: const Text('Dispensar'),
        ),
      ],
    );
  }
}
