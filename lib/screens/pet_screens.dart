import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'agenda_screens.dart';
import 'consultation_screens.dart';
import 'hospital_screens.dart';
import 'lab_screens.dart';
import 'reception_screens.dart';
import 'vaccine_screens.dart';
import 'shell.dart';

/// Buscar mascotas (§17.3) por nombre, microchip o propietario.
class PetSearchScreen extends StatefulWidget {
  const PetSearchScreen({super.key});

  @override
  State<PetSearchScreen> createState() => _PetSearchScreenState();
}

class _PetSearchScreenState extends State<PetSearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  String _term = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _term = value.trim()));
  }

  int _version = 0;

  /// Recepción: propietario nuevo (con su mascota) o mascota de un propietario ya registrado.
  Future<void> _register() async {
    final profile = context.read<Session>().profile!;
    final choice = profile.can('clients.create') && profile.can('pets.create')
        ? await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.person_add_alt),
                    title: const Text('Propietario nuevo'),
                    subtitle: const Text('Primera visita: registra al dueño y luego su mascota'),
                    onTap: () => Navigator.pop(context, 'client'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.pets),
                    title: const Text('Mascota de un propietario registrado'),
                    onTap: () => Navigator.pop(context, 'pet'),
                  ),
                ],
              ),
            ),
          )
        : (profile.can('clients.create') ? 'client' : 'pet');
    if (choice == null || !mounted) return;

    final navigator = Navigator.of(context);
    if (choice == 'client') {
      final client = await navigator.push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const ClientFormScreen(offerPet: true)));
      if (client != null) await navigator.push(MaterialPageRoute(builder: (_) => ClientScreen(id: client['id'] as int)));
    } else {
      final client = await navigator.push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const ClientSearchScreen(pick: true)));
      if (client == null) return;
      final pet = await navigator.push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => PetFormScreen(client: client)));
      if (pet != null) await navigator.push(MaterialPageRoute(builder: (_) => PetScreen(id: pet['id'] as int)));
    }
    if (mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;

    return Scaffold(
      floatingActionButton: profile.can('pets.create') || profile.can('clients.create')
          ? FloatingActionButton.extended(onPressed: _register, icon: const Icon(Icons.add), label: const Text('Registrar'))
          : null,
      appBar: AppBar(leading: shellMenuButton(context), title: const Text('Pacientes')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              controller: _query,
              hintText: 'Nombre, microchip o propietario',
              leading: const Icon(Icons.search),
              trailing: [
                if (_query.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Limpiar',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _query.clear();
                      _changed('');
                    },
                  ),
              ],
              onChanged: _changed,
              elevation: const WidgetStatePropertyAll(0),
            ),
          ),
          Expanded(
            child: _PetList(key: ValueKey('$_term-$_version'), term: _term),
          ),
        ],
      ),
    );
  }
}

class _PetList extends StatefulWidget {
  const _PetList({super.key, required this.term});

  final String term;

  @override
  State<_PetList> createState() => _PetListState();
}

class _PetListState extends State<_PetList> {
  final List<Map<String, dynamic>> _items = [];
  int _page = 0;
  int _lastPage = 1;
  int _total = 0;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    if (_loading || _page >= _lastPage) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final json = await context.session.api.get('/pets', query: {'q': widget.term, 'page': '${_page + 1}'});
      final meta = json.obj('meta') ?? {};
      setState(() {
        _items.addAll(json.list('data'));
        _page = meta.integer('current_page') ?? _page + 1;
        _lastPage = meta.integer('last_page') ?? _page;
        _total = meta.integer('total') ?? _items.length;
      });
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      if (_error != null) return ErrorState(error: _error!, onRetry: _more);
      return EmptyState(
        icon: Icons.search_off,
        message: widget.term.isEmpty ? 'Todavía no hay pacientes registrados.' : 'No encontramos pacientes con «${widget.term}».',
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels > n.metrics.maxScrollExtent - 200) _more();
        return false;
      },
      child: ListView.builder(
        itemCount: _items.length + 1,
        itemBuilder: (context, i) {
          if (i == _items.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _loading
                    ? const CircularProgressIndicator()
                    : Text(
                        _total == 1 ? '1 paciente' : '$_total pacientes',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
              ),
            );
          }
          final p = _items[i];
          return ListTile(
            leading: PetAvatar(name: p.str('name') ?? '?', photoUrl: p.str('photo_url')),
            title: Row(
              children: [
                Flexible(child: Text(p.str('name') ?? '', overflow: TextOverflow.ellipsis)),
                if (p.flag('has_clinical_warnings')) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Tiene alergias o condiciones',
                    child: Icon(Icons.warning_amber, size: 18, color: toneColor(context, 'warning')),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              [
                [p.str('species'), p.str('breed')].whereType<String>().join(' · '),
                p.obj('owner')?.str('name'),
              ].whereType<String>().where((s) => s.isNotEmpty).join('\n'),
            ),
            isThreeLine: p.obj('owner')?.str('name') != null,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PetScreen(id: p['id'] as int))),
          );
        },
      ),
    );
  }
}

/// Ficha del paciente: datos, propietario, historial y salud.
class PetScreen extends StatefulWidget {
  const PetScreen({super.key, required this.id});

  final int id;

  @override
  State<PetScreen> createState() => _PetScreenState();
}

class _PetScreenState extends State<PetScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  Map<String, dynamic>? _pet;
  int _historyVersion = 0;
  bool _opening = false;

  /// Abre una consulta sin cita y va directo al formulario.
  Future<void> _newConsultation() async {
    final pet = _pet;
    if (pet == null) return;
    setState(() => _opening = true);
    try {
      final consultation = await context.session.api.post('/consultations', {'pet_id': pet['id'], 'client_id': pet.obj('client')?['id']});
      if (!mounted) return;
      await openConsultation(context, consultation);
      setState(() => _historyVersion++);
      _loader.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _edit() async {
    final pet = _pet!;
    final saved = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => PetFormScreen(client: pet.obj('client') ?? {}, pet: pet),
      ),
    );
    if (saved != null) _loader.currentState?.reload();
  }

  Future<void> _changePhoto() async {
    final pet = _pet;
    if (pet == null) return;
    final api = context.session.api;
    try {
      final photo = await pickPetPhoto(
        context,
        onRemove: pet.str('photo_url') == null
            ? null
            : () async {
                try {
                  await api.delete('/pets/${pet['id']}/photo');
                  _loader.currentState?.reload();
                } catch (e) {
                  if (mounted) showError(context, e);
                }
              },
      );
      if (photo == null) return;
      if (mounted) showInfo(context, 'Subiendo la foto…');
      await uploadPetPhoto(api, pet['id'] as int, photo);
      if (mounted) showDone(context, 'Foto actualizada.');
      _loader.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _schedule() async {
    final saved = await Navigator.of(
      context,
    ).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => AppointmentFormScreen(pet: _pet)));
    if (saved != null) _loader.currentState?.reload();
  }

  Future<void> _admit() async {
    await admitPatient(context, pet: _pet);
    _loader.currentState?.reload();
  }

  Future<void> _walkIn() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => WalkInScreen(pet: _pet)));
    if (saved == true) _loader.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final canEditPet = profile.can('pets.edit');
    final canSchedule = profile.canUse('agenda', 'appointments.create');
    final showHistory = profile.canUse('consultas', 'consultations.view');
    final showHealth = profile.canUse('vacunas', 'vaccinations.view');
    final showLab = labVisible(profile);
    final showStays = hospitalVisible(profile);
    final canAdmit = showStays && profile.can('hospitalizations.create');
    final interned = _pet?.integer('active_hospitalization_id') != null;
    final tabs = [
      'Ficha',
      if (showHistory) 'Historial',
      if (showHealth) 'Salud',
      if (showLab) 'Laboratorio',
      if (showStays) 'Internaciones',
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Paciente'),
          actions: [
            if (_pet != null && canSchedule)
              IconButton(tooltip: 'Agendar cita', onPressed: _schedule, icon: const Icon(Icons.event_outlined)),
            if (_pet != null && (canEditPet || canSchedule || (canAdmit && !interned)))
              PopupMenuButton<String>(
                tooltip: 'Más acciones',
                onSelected: (v) => switch (v) {
                  'edit' => _edit(),
                  'photo' => _changePhoto(),
                  'walk_in' => _walkIn(),
                  'admit' => _admit(),
                  _ => null,
                },
                itemBuilder: (context) => [
                  if (canEditPet)
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar datos')),
                    ),
                  if (canEditPet)
                    const PopupMenuItem(
                      value: 'photo',
                      child: ListTile(leading: Icon(Icons.photo_camera_outlined), title: Text('Cambiar foto')),
                    ),
                  if (canSchedule)
                    const PopupMenuItem(
                      value: 'walk_in',
                      child: ListTile(leading: Icon(Icons.directions_walk), title: Text('Llegó sin cita')),
                    ),
                  if (canAdmit && !interned)
                    const PopupMenuItem(
                      value: 'admit',
                      child: ListTile(leading: Icon(Icons.local_hospital_outlined), title: Text('Internar')),
                    ),
                ],
              ),
          ],
          bottom: tabs.length > 1
              ? TabBar(
                  isScrollable: tabs.length > 3,
                  tabAlignment: tabs.length > 3 ? TabAlignment.start : null,
                  tabs: [for (final t in tabs) Tab(text: t)],
                )
              : null,
        ),
        floatingActionButton: profile.canUse('consultas', 'consultations.create') && _pet != null
            ? FloatingActionButton.extended(
                onPressed: _opening ? null : _newConsultation,
                icon: _opening
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.medical_services_outlined),
                label: const Text('Nueva consulta'),
              )
            : null,
        body: Loader<Map<String, dynamic>>(
          key: _loader,
          load: () async {
            final pet = await context.session.api.get('/pets/${widget.id}');
            if (mounted) setState(() => _pet = pet);
            return pet;
          },
          builder: (context, pet, reload) => TabBarView(
            children: [
              _ProfileTab(pet: pet, reload: reload, onPhoto: canEditPet ? _changePhoto : null, canOpenOwner: profile.can('clients.view')),
              if (showHistory) _HistoryTab(key: ValueKey(_historyVersion), petId: widget.id),
              if (showHealth) PetHealthTab(pet: pet, reload: reload),
              if (showLab) PetLabTab(pet: pet),
              if (showStays) PetStaysTab(pet: pet, reload: reload),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.pet, required this.reload, this.onPhoto, this.canOpenOwner = false});

  final Map<String, dynamic> pet;
  final Future<void> Function() reload;
  final VoidCallback? onPhoto;
  final bool canOpenOwner;

  @override
  Widget build(BuildContext context) {
    final clinical = pet.obj('clinical') ?? {};
    final warnings = {
      'Alergias': clinical.str('allergies'),
      'Condiciones crónicas': clinical.str('chronic_conditions'),
      'Medicación habitual': clinical.str('usual_medications'),
      'Cirugías previas': clinical.str('previous_surgeries'),
    }..removeWhere((_, v) => v == null || v.isEmpty);
    final weights = pet.list('weights');
    final upcoming = pet['upcoming_appointments'] == null ? null : pet.list('upcoming_appointments');
    final client = pet.obj('client');
    final stayId = pet.integer('active_hospitalization_id');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: onPhoto,
              child: PetAvatar(name: pet.str('name') ?? '?', photoUrl: pet.str('photo_url'), radius: 34),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pet.str('name') ?? '', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text([pet.str('species'), pet.str('breed')].whereType<String>().join(' · ')),
                  Text(
                    [
                      pet.str('sex_label'),
                      pet.str('age_label'),
                      if (pet.flag('sterilized')) 'Esterilizado/a',
                    ].whereType<String>().join(' · '),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (stayId != null) ...[
          const SizedBox(height: 12),
          Card(
            color: toneColor(context, 'info').withValues(alpha: .12),
            child: ListTile(
              leading: Icon(Icons.local_hospital, color: toneColor(context, 'info')),
              title: const Text('Internado ahora'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StayScreen(id: stayId))),
            ),
          ),
        ],
        if (warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            color: toneColor(context, 'warning').withValues(alpha: .12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber, color: toneColor(context, 'warning')),
                      const SizedBox(width: 8),
                      const Text('Precauciones', style: TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  for (final w in warnings.entries) ...[
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${w.key}: ',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(text: w.value),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                Fact('Peso', pet.number('weight') == null ? '—' : '${fmtNumber(pet.number('weight'))} kg'),
                Fact('Nacimiento', fmtDate(pet.date('birth_date'))),
                Fact('Color', pet.str('color') ?? '—'),
                Fact('Tamaño', pet.str('size_label') ?? '—'),
                Fact('Microchip', pet.str('microchip') ?? '—'),
              ],
            ),
          ),
        ),
        if (client != null) ...[
          const SizedBox(height: 12),
          OwnerCard(
            client: client,
            onTap: canOpenOwner
                ? () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClientScreen(id: client['id'] as int)));
                    reload();
                  }
                : null,
          ),
        ],
        if (weights.length > 1) ...[
          const SectionTitle('Evolución del peso'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (final w in weights.take(6))
                    Row(
                      children: [
                        Expanded(child: Text(fmtDate(w.date('recorded_at')))),
                        Text('${fmtNumber(w.number('weight'))} kg', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
        if (upcoming != null) ...[
          const SectionTitle('Próximas citas'),
          if (upcoming.isEmpty)
            const Card(
              child: ListTile(leading: Icon(Icons.event_available), title: Text('Sin citas agendadas')),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [for (final a in upcoming) AppointmentTile(appointment: a, onChanged: reload, showDate: true)],
              ),
            ),
        ],
        if ((pet.str('notes') ?? '').isNotEmpty) ...[
          const SectionTitle('Notas'),
          Card(
            child: Padding(padding: const EdgeInsets.all(16), child: Text(pet.str('notes')!)),
          ),
        ],
      ],
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({super.key, required this.petId});

  final int petId;

  @override
  Widget build(BuildContext context) {
    return Loader<Map<String, dynamic>>(
      load: () => context.session.api.get('/pets/$petId/consultations'),
      builder: (context, data, reload) {
        final items = data.list('data');
        if (items.isEmpty) {
          return ListView(
            children: const [EmptyState(icon: Icons.history, message: 'Sin consultas registradas.')],
          );
        }
        final total = data.obj('meta')?.integer('total') ?? items.length;
        return ListView(
          children: [
            for (final c in items)
              ListTile(
                leading: CircleAvatar(child: Text('${c.date('started_at')?.day ?? ''}')),
                title: Text(c.str('primary_diagnosis') ?? c.str('reason') ?? 'Consulta'),
                subtitle: Text([fmtDate(c.date('started_at')), c.str('veterinarian')].whereType<String>().join(' · ')),
                trailing: StatusChip(c.obj('status_badge')?.str('label') ?? '', tone: c.obj('status_badge')?.str('color')),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConsultationScreen(id: c['id'] as int))),
              ),
            if (total > items.length)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Mostrando las ${items.length} más recientes de $total. El historial completo está en la web.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        );
      },
    );
  }
}
