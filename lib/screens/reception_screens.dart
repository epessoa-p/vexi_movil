import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'agenda_screens.dart';
import 'finance_screens.dart';
import 'pet_screens.dart';
import 'shell.dart';

// ── Piezas compartidas ──────────────────────────────────────────────────────

/// Hora «de pared» de la veterinaria: «2026-11-12T09:00:00-04:00» → 09:00,
/// sin convertir a la zona del teléfono (así se edita lo que se agendó).
DateTime? wallTime(String? iso) => iso == null || iso.length < 19 ? null : DateTime.tryParse(iso.substring(0, 19));

String hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Campo de búsqueda que avisa medio segundo después de dejar de escribir.
class SearchField extends StatefulWidget {
  const SearchField({super.key, required this.hint, required this.onChanged, this.autofocus = false});

  final String hint;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => widget.onChanged(value.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SearchBar(
        controller: _controller,
        autoFocus: widget.autofocus,
        hintText: widget.hint,
        leading: const Icon(Icons.search),
        trailing: [
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Limpiar',
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                _changed('');
              },
            ),
        ],
        onChanged: _changed,
        elevation: const WidgetStatePropertyAll(0),
      ),
    );
  }
}

/// Lista paginada de la API (`data` + `meta`), que pide más al llegar al final.
class PagedList extends StatefulWidget {
  const PagedList({
    super.key,
    required this.path,
    required this.term,
    required this.itemBuilder,
    required this.empty,
    required this.count,
    this.query = const {},
  });

  final String path;
  final String term;

  /// Filtros extra (`status`, `mine`…); los vacíos no se envían.
  final Map<String, String?> query;
  final Widget Function(BuildContext context, Map<String, dynamic> item) itemBuilder;
  final String empty;
  final String Function(int total) count;

  @override
  State<PagedList> createState() => _PagedListState();
}

class _PagedListState extends State<PagedList> {
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
      final json = await context.session.api.get(widget.path, query: {...widget.query, 'q': widget.term, 'page': '${_page + 1}'});
      final meta = json.obj('meta') ?? {};
      if (!mounted) return;
      setState(() {
        _items.addAll(json.list('data'));
        _page = meta.integer('current_page') ?? _page + 1;
        _lastPage = meta.integer('last_page') ?? _page;
        _total = meta.integer('total') ?? _items.length;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      if (_error != null) {
        return ListView(
          children: [ErrorState(error: _error!, onRetry: _more)],
        );
      }
      return ListView(
        children: [EmptyState(icon: Icons.search_off, message: widget.empty)],
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels > n.metrics.maxScrollExtent - 200) _more();
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: _items.length + 1,
        itemBuilder: (context, i) {
          if (i < _items.length) return widget.itemBuilder(context, _items[i]);
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : Text(widget.count(_total), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          );
        },
      ),
    );
  }
}

/// Botón ancho de guardar con su indicador de «guardando».
class SaveButton extends StatelessWidget {
  const SaveButton({super.key, required this.label, required this.saving, required this.onPressed, this.outlined = false});

  final String label;
  final bool saving;
  final VoidCallback onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final child = saving ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(label);
    final style = ButtonStyle(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)));
    return outlined
        ? OutlinedButton(onPressed: saving ? null : onPressed, style: style, child: child)
        : FilledButton(onPressed: saving ? null : onPressed, style: style, child: child);
  }
}

/// Mensaje general de un error que no es de un campo concreto.
class FormErrorText extends StatelessWidget {
  const FormErrorText(this.error, {super.key});

  final ApiException? error;

  @override
  Widget build(BuildContext context) {
    final e = error;
    if (e == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        e.fieldErrors.isEmpty ? e.message : 'Revisa los campos marcados.',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

/// Selector de fecha u hora con aspecto de campo.
class PickerField extends StatelessWidget {
  const PickerField({super.key, required this.label, required this.value, required this.icon, required this.onTap, this.error});

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: Icon(icon), errorText: error, errorMaxLines: 3),
        child: Text(value),
      ),
    );
  }
}

// ── Propietarios ────────────────────────────────────────────────────────────

/// Propietarios: búsqueda y alta. Con [pick] devuelve el elegido.
class ClientSearchScreen extends StatefulWidget {
  const ClientSearchScreen({super.key, this.pick = false});

  final bool pick;

  @override
  State<ClientSearchScreen> createState() => _ClientSearchScreenState();
}

class _ClientSearchScreenState extends State<ClientSearchScreen> {
  String _term = '';
  int _version = 0;

  Future<void> _create() async {
    final client = await Navigator.of(
      context,
    ).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => ClientFormScreen(offerPet: !widget.pick)));
    if (client == null || !mounted) return;
    if (widget.pick) {
      Navigator.of(context).pop(client);
      return;
    }
    setState(() => _version++);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClientScreen(id: client['id'] as int)));
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;

    return Scaffold(
      appBar: AppBar(
        leading: widget.pick ? null : shellMenuButton(context),
        title: Text(widget.pick ? 'Elegir propietario' : 'Propietarios'),
      ),
      floatingActionButton: profile.can('clients.create')
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Nuevo propietario'),
            )
          : null,
      body: Column(
        children: [
          SearchField(hint: 'Nombre, documento o teléfono', autofocus: widget.pick, onChanged: (v) => setState(() => _term = v)),
          Expanded(
            child: PagedList(
              key: ValueKey('$_term-$_version'),
              path: '/clients',
              term: _term,
              empty: _term.isEmpty ? 'Todavía no hay propietarios registrados.' : 'No encontramos propietarios con «$_term».',
              count: (n) => n == 1 ? '1 propietario' : '$n propietarios',
              itemBuilder: (context, c) => ListTile(
                leading: CircleAvatar(child: Text((c.str('name') ?? '?').characters.first.toUpperCase())),
                title: Text(c.str('name') ?? ''),
                subtitle: Text(
                  [
                    c.str('document'),
                    c.str('phone'),
                    if (c.integer('pets_count') != null) c.integer('pets_count') == 1 ? '1 mascota' : '${c.integer('pets_count')} mascotas',
                  ].whereType<String>().join(' · '),
                ),
                onTap: () async {
                  if (widget.pick) {
                    Navigator.of(context).pop(c);
                    return;
                  }
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClientScreen(id: c['id'] as int)));
                  setState(() => _version++);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ficha del propietario: contacto, saldo, mascotas.
class ClientScreen extends StatefulWidget {
  const ClientScreen({super.key, required this.id});

  final int id;

  @override
  State<ClientScreen> createState() => _ClientScreenState();
}

class _ClientScreenState extends State<ClientScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  Map<String, dynamic>? _client;

  Future<void> _edit() async {
    final saved = await Navigator.of(
      context,
    ).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => ClientFormScreen(client: _client)));
    if (saved != null) _loader.currentState?.reload();
  }

  Future<void> _addPet() async {
    final pet = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => PetFormScreen(client: _client!)));
    if (pet != null) _loader.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final currency = profile.company?.currencySymbol ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Propietario'),
        actions: [
          if (profile.can('clients.edit') && _client != null)
            IconButton(tooltip: 'Editar', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      floatingActionButton: profile.can('pets.create') && _client != null
          ? FloatingActionButton.extended(onPressed: _addPet, icon: const Icon(Icons.add), label: const Text('Registrar mascota'))
          : null,
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () async {
          final client = await context.session.api.get('/clients/${widget.id}');
          if (mounted) setState(() => _client = client);
          return client;
        },
        builder: (context, c, reload) {
          final pets = c['pets'] == null ? null : c.list('pets');
          final balance = c.number('balance');
          final details = {
            Icons.badge_outlined: c.str('document'),
            Icons.mail_outline: c.str('email'),
            Icons.place_outlined: c.str('address'),
            Icons.sticky_note_2_outlined: c.str('notes'),
          }..removeWhere((_, v) => v == null || v.isEmpty);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      c.str('name') ?? '',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (!c.flag('active')) const StatusChip('Inactivo'),
                ],
              ),
              const SizedBox(height: 12),
              OwnerCard(client: c),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                    child: Column(
                      children: [
                        for (final d in details.entries)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(d.key, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                const SizedBox(width: 10),
                                Expanded(child: Text(d.value!)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (balance != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: balance > 0 ? toneColor(context, 'warning').withValues(alpha: .12) : null,
                  child: ListTile(
                    leading: Icon(Icons.account_balance_wallet_outlined, color: balance > 0 ? toneColor(context, 'warning') : null),
                    title: Text(balance > 0 ? 'Saldo pendiente' : 'Cuenta al día'),
                    subtitle: balance > 0 ? const Text('Ver lo que debe y registrar abonos') : null,
                    trailing: balance > 0
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                fmtMoney(balance, currency),
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          )
                        : null,
                    onTap: balance > 0
                        ? () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ClientDebtScreen(clientId: widget.id, name: c.str('name')),
                              ),
                            );
                            reload();
                          }
                        : null,
                  ),
                ),
              ],
              if (pets != null) ...[
                SectionTitle(pets.length == 1 ? '1 mascota' : '${pets.length} mascotas'),
                if (pets.isEmpty)
                  const Card(
                    child: ListTile(leading: Icon(Icons.pets), title: Text('Sin mascotas registradas')),
                  )
                else
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final p in pets)
                          ListTile(
                            leading: PetAvatar(name: p.str('name') ?? '?', photoUrl: p.str('photo_url')),
                            title: Text(p.str('name') ?? ''),
                            subtitle: Text([p.str('species'), p.str('breed'), p.str('age_label')].whereType<String>().join(' · ')),
                            trailing: p.str('status') == 'active'
                                ? const Icon(Icons.chevron_right)
                                : StatusChip(p.str('status_label') ?? ''),
                            onTap: () async {
                              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PetScreen(id: p['id'] as int)));
                              reload();
                            },
                          ),
                      ],
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

/// Alta o edición de un propietario. Devuelve el propietario guardado.
class ClientFormScreen extends StatefulWidget {
  const ClientFormScreen({super.key, this.client, this.offerPet = false});

  final Map<String, dynamic>? client;

  /// Muestra «Guardar y registrar mascota» (el flujo habitual en recepción).
  final bool offerPet;

  @override
  State<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<ClientFormScreen> {
  static const _documentTypes = {'CI': 'Cédula de identidad', 'NIT': 'NIT', 'PASAPORTE': 'Pasaporte', 'OTRO': 'Otro'};

  late final Map<String, TextEditingController> _text;
  String? _documentType;
  bool _active = true;

  /// El botón de WhatsApp usa el campo `whatsapp`: casi siempre es el mismo teléfono.
  bool _sameWhatsapp = true;
  bool _saving = false;
  ApiException? _error;

  bool get _editing => widget.client != null;

  @override
  void initState() {
    super.initState();
    final c = widget.client ?? {};
    _text = {
      for (final key in ['first_name', 'last_name', 'document_number', 'phone', 'whatsapp', 'email', 'address', 'notes'])
        key: TextEditingController(text: c.str(key) ?? ''),
    };
    _documentType = c.str('document_type') ?? 'CI';
    _active = widget.client == null || c.flag('active');
    final whatsapp = c.str('whatsapp') ?? '';
    _sameWhatsapp = widget.client == null || (whatsapp.isNotEmpty && whatsapp == c.str('phone'));
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save({bool addPet = false}) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      for (final e in _text.entries) e.key: e.value.text.trim().isEmpty ? null : e.value.text.trim(),
      'document_type': _text['document_number']!.text.trim().isEmpty ? null : _documentType,
      if (_sameWhatsapp) 'whatsapp': _text['phone']!.text.trim().isEmpty ? null : _text['phone']!.text.trim(),
      if (_editing) 'active': _active,
    };
    try {
      final api = context.session.api;
      final saved = _editing ? await api.put('/clients/${widget.client!['id']}', body) : await api.post('/clients', body);
      if (!mounted) return;
      showDone(context, _editing ? 'Propietario actualizado.' : 'Propietario registrado.');
      if (addPet) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PetFormScreen(client: saved)));
      }
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String key, String label, {TextInputType? keyboard, int lines = 1, String? helper, TextCapitalization? caps}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: _text[key],
      keyboardType: keyboard,
      maxLines: lines,
      textCapitalization: caps ?? (keyboard == null ? TextCapitalization.sentences : TextCapitalization.none),
      decoration: InputDecoration(labelText: label, helperText: helper, errorText: _error?.field(key), errorMaxLines: 2),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final canAddPet = widget.offerPet && !_editing && context.watch<Session>().profile!.can('pets.create');

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Editar propietario' : 'Nuevo propietario')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FormErrorText(_error),
          _field('first_name', 'Nombre', caps: TextCapitalization.words),
          _field('last_name', 'Apellido (opcional)', caps: TextCapitalization.words),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _documentType,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Documento'),
                  items: [
                    for (final t in _documentTypes.entries)
                      DropdownMenuItem(
                        value: t.key,
                        child: Text(t.key == 'CI' ? 'CI' : t.value, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _documentType = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: _field('document_number', 'Número (opcional)', keyboard: TextInputType.text)),
            ],
          ),
          _field('phone', 'Teléfono', keyboard: TextInputType.phone),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Usa WhatsApp en este número'),
            value: _sameWhatsapp,
            onChanged: (v) => setState(() => _sameWhatsapp = v ?? true),
          ),
          if (!_sameWhatsapp)
            _field(
              'whatsapp',
              'WhatsApp (opcional)',
              keyboard: TextInputType.phone,
              helper: 'Para escribirle desde la app y enviarle recordatorios.',
            ),
          _field('email', 'Correo (opcional)', keyboard: TextInputType.emailAddress),
          _field('address', 'Dirección (opcional)'),
          _field('notes', 'Notas (opcional)', lines: 3),
          if (_editing)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activo'),
              subtitle: const Text('Un propietario inactivo no aparece al buscar para agendar.'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          const SizedBox(height: 8),
          if (canAddPet) ...[
            SaveButton(label: 'Guardar y registrar mascota', saving: _saving, onPressed: () => _save(addPet: true)),
            const SizedBox(height: 8),
            SaveButton(label: 'Solo guardar', saving: _saving, outlined: true, onPressed: _save),
          ] else
            SaveButton(label: _editing ? 'Guardar cambios' : 'Registrar propietario', saving: _saving, onPressed: _save),
        ],
      ),
    );
  }
}

// ── Mascotas ────────────────────────────────────────────────────────────────

/// Elegir de dónde sale la foto: cámara o galería. Devuelve null si se arrepiente.
Future<XFile?> pickPetPhoto(BuildContext context, {VoidCallback? onRemove}) async {
  final source = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Tomar foto'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Elegir de la galería'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          if (onRemove != null)
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: Text('Quitar foto', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
        ],
      ),
    ),
  );
  if (source == 'remove') {
    onRemove?.call();
    return null;
  }
  if (source is! ImageSource) return null;
  // Reducida en el teléfono: llega rápido y queda bajo el límite de 4 MB del servidor.
  return ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
}

/// Sube la foto elegida a la ficha de la mascota y devuelve la ficha actualizada.
Future<Map<String, dynamic>> uploadPetPhoto(ApiClient api, int petId, XFile photo) async =>
    api.upload('/pets/$petId/photo', 'photo', await photo.readAsBytes(), photo.name);

/// Alta o edición de una mascota de [client], con foto. Devuelve la ficha guardada.
class PetFormScreen extends StatefulWidget {
  const PetFormScreen({super.key, required this.client, this.pet});

  /// Propietario: al menos `id` y `name`.
  final Map<String, dynamic> client;
  final Map<String, dynamic>? pet;

  @override
  State<PetFormScreen> createState() => _PetFormScreenState();
}

class _PetFormScreenState extends State<PetFormScreen> {
  late final Map<String, TextEditingController> _text;
  int? _speciesId;
  int? _breedId;
  String _sex = 'male';
  String? _size;
  String _status = 'active';
  bool _sterilized = false;
  DateTime? _birth;
  XFile? _photo;
  Uint8List? _photoBytes;
  bool _saving = false;
  ApiException? _error;

  bool get _editing => widget.pet != null;

  @override
  void initState() {
    super.initState();
    final p = widget.pet ?? {};
    final weight = p.number('weight');
    _text = {
      'name': TextEditingController(text: p.str('name') ?? ''),
      'weight': TextEditingController(text: weight == null ? '' : fmtNumber(weight).replaceAll('.', '')),
      'color': TextEditingController(text: p.str('color') ?? ''),
      'microchip': TextEditingController(text: p.str('microchip') ?? ''),
      'notes': TextEditingController(text: p.str('notes') ?? ''),
    };
    _speciesId = p.integer('species_id');
    _breedId = p.integer('breed_id');
    _sex = p.str('sex') ?? 'male';
    _size = p.str('size');
    _status = p.str('status') ?? 'active';
    _sterilized = p.flag('sterilized');
    _birth = p.date('birth_date');
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    try {
      final file = await pickPetPhoto(context);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _photo = file;
        _photoBytes = bytes;
      });
    } catch (_) {
      if (mounted) showError(context, 'No se pudo abrir la cámara ni la galería.');
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    String? text(String key) => _text[key]!.text.trim().isEmpty ? null : _text[key]!.text.trim();
    final body = {
      'client_id': widget.client['id'],
      'name': text('name'),
      'species_id': _speciesId,
      'breed_id': _breedId,
      'sex': _sex,
      'sterilized': _sterilized,
      'birth_date': _birth == null ? null : isoDate(_birth!),
      'weight': text('weight') == null ? null : double.tryParse(text('weight')!.replaceAll(',', '.')) ?? text('weight'),
      'color': text('color'),
      'size': _size,
      'microchip': text('microchip'),
      'notes': text('notes'),
      'status': _status,
    };

    final api = context.session.api;
    Map<String, dynamic> saved;
    try {
      saved = _editing ? await api.put('/pets/${widget.pet!['id']}', body) : await api.post('/pets', body);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
      if (mounted) setState(() => _saving = false);
      return;
    }

    if (_photo != null) {
      try {
        saved = await uploadPetPhoto(api, saved['id'] as int, _photo!);
      } on ApiException catch (e) {
        if (mounted) showError(context, 'La mascota se guardó, pero la foto no: ${e.field('photo') ?? e.message}');
      }
    }
    if (!mounted) return;
    showDone(context, _editing ? 'Mascota actualizada.' : 'Mascota registrada.');
    Navigator.of(context).pop(saved);
  }

  Widget _field(String key, String label, {TextInputType? keyboard, int lines = 1, String? suffix}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: _text[key],
      keyboardType: keyboard,
      maxLines: lines,
      textCapitalization: keyboard == null ? TextCapitalization.sentences : TextCapitalization.none,
      decoration: InputDecoration(labelText: label, suffixText: suffix, errorText: _error?.field(key), errorMaxLines: 2),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Editar mascota' : 'Nueva mascota')),
      body: Loader<Map<String, dynamic>>(
        load: () => context.session.api.get('/pets/options'),
        builder: (context, options, reload) {
          final species = options.list('species');
          final breeds = species.where((s) => s['id'] == _speciesId).expand((s) => s.list('breeds')).toList();
          final sexes = options.list('sexes');
          final sizes = options.list('sizes');
          final statuses = options.list('statuses');
          final existingPhoto = widget.pet?.str('photo_url');

          if (species.isEmpty) {
            return ListView(
              children: const [EmptyState(icon: Icons.pets, message: 'No hay especies configuradas. Cárgalas desde la web.')],
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: GestureDetector(
                  onTap: _choosePhoto,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 52,
                        backgroundColor: scheme.primaryContainer,
                        foregroundImage: _photoBytes != null
                            ? MemoryImage(_photoBytes!)
                            : existingPhoto != null
                            ? NetworkImage(existingPhoto)
                            : null,
                        child: Icon(Icons.pets, size: 40, color: scheme.onPrimaryContainer),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: scheme.primary,
                          child: Icon(Icons.photo_camera, size: 18, color: scheme.onPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                child: Text(
                  'Propietario: ${widget.client.str('name') ?? ''}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              FormErrorText(_error),
              _field('name', 'Nombre'),
              DropdownButtonFormField<int>(
                initialValue: _speciesId,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'Especie', errorText: _error?.field('species_id')),
                items: [for (final s in species) DropdownMenuItem(value: s['id'] as int, child: Text(s.str('name') ?? ''))],
                onChanged: (v) => setState(() {
                  _speciesId = v;
                  _breedId = null;
                }),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                key: ValueKey('breed-$_speciesId'),
                initialValue: breeds.any((b) => b['id'] == _breedId) ? _breedId : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Raza (opcional)',
                  helperText: _speciesId == null ? 'Elige primero la especie.' : null,
                  errorText: _error?.field('breed_id'),
                ),
                items: [
                  const DropdownMenuItem<int>(value: null, child: Text('Sin raza / mestizo')),
                  for (final b in breeds)
                    DropdownMenuItem(
                      value: b['id'] as int,
                      child: Text(b.str('name') ?? '', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _speciesId == null ? null : (v) => setState(() => _breedId = v),
              ),
              const SizedBox(height: 16),
              Text('Sexo', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: [for (final s in sexes) ButtonSegment(value: s.str('key')!, label: Text(s.str('label') ?? ''))],
                selected: {_sex},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _sex = v.first),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Esterilizado/a'),
                value: _sterilized,
                onChanged: (v) => setState(() => _sterilized = v),
              ),
              PickerField(
                label: 'Fecha de nacimiento (opcional)',
                value: _birth == null ? 'Sin dato' : fmtDate(_birth),
                icon: Icons.cake_outlined,
                error: _error?.field('birth_date'),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _birth ?? DateTime.now().subtract(const Duration(days: 365)),
                    firstDate: DateTime(DateTime.now().year - 30),
                    lastDate: DateTime.now(),
                    helpText: 'Si no se sabe, una aproximada',
                  );
                  if (picked != null) setState(() => _birth = picked);
                },
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _field('weight', 'Peso', keyboard: const TextInputType.numberWithOptions(decimal: true), suffix: 'kg'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _size,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Tamaño'),
                      items: [
                        const DropdownMenuItem<String>(value: null, child: Text('—')),
                        for (final s in sizes) DropdownMenuItem(value: s.str('key'), child: Text(s.str('label') ?? '')),
                      ],
                      onChanged: (v) => setState(() => _size = v),
                    ),
                  ),
                ],
              ),
              _field('color', 'Color o señas (opcional)'),
              _field('microchip', 'Microchip (opcional)', keyboard: TextInputType.text),
              _field('notes', 'Notas (opcional)', lines: 3),
              if (_editing) ...[
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Estado'),
                  items: [for (final s in statuses) DropdownMenuItem(value: s.str('key'), child: Text(s.str('label') ?? ''))],
                  onChanged: (v) => setState(() => _status = v ?? _status),
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 8),
              SaveButton(label: _editing ? 'Guardar cambios' : 'Registrar mascota', saving: _saving, onPressed: _save),
            ],
          );
        },
      ),
    );
  }
}

/// Buscar un paciente para agendarlo o registrar su llegada. Devuelve la
/// mascota con su propietario (`owner`).
class PetPickerScreen extends StatefulWidget {
  const PetPickerScreen({super.key});

  @override
  State<PetPickerScreen> createState() => _PetPickerScreenState();
}

class _PetPickerScreenState extends State<PetPickerScreen> {
  String _term = '';

  Future<void> _register() async {
    final client = await Navigator.of(
      context,
    ).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const ClientSearchScreen(pick: true)));
    if (client == null || !mounted) return;
    final pet = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => PetFormScreen(client: client)));
    if (pet == null || !mounted) return;
    Navigator.of(context).pop({
      ...pet,
      'owner': {'id': client['id'], 'name': client['name'], 'phone': client['phone']},
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;

    return Scaffold(
      appBar: AppBar(title: const Text('Elegir paciente')),
      floatingActionButton: profile.can('pets.create')
          ? FloatingActionButton.extended(onPressed: _register, icon: const Icon(Icons.add), label: const Text('Paciente nuevo'))
          : null,
      body: Column(
        children: [
          SearchField(hint: 'Mascota, microchip o propietario', autofocus: true, onChanged: (v) => setState(() => _term = v)),
          Expanded(
            child: PagedList(
              key: ValueKey(_term),
              path: '/pets',
              term: _term,
              empty: _term.isEmpty ? 'Todavía no hay pacientes registrados.' : 'No encontramos pacientes con «$_term».',
              count: (n) => n == 1 ? '1 paciente' : '$n pacientes',
              itemBuilder: (context, p) => ListTile(
                leading: PetAvatar(name: p.str('name') ?? '?', photoUrl: p.str('photo_url')),
                title: Text(p.str('name') ?? ''),
                subtitle: Text([p.str('species'), p.obj('owner')?.str('name')].whereType<String>().join(' · ')),
                onTap: () => Navigator.of(context).pop(p),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila del formulario con el paciente elegido (o el botón para elegirlo).
class _PetChoice extends StatelessWidget {
  const _PetChoice({required this.pet, required this.onTap, this.error});

  final Map<String, dynamic>? pet;
  final VoidCallback? onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final p = pet;
    final owner = p?.obj('owner') ?? p?.obj('client');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: p == null
                ? const CircleAvatar(child: Icon(Icons.pets))
                : PetAvatar(name: p.str('name') ?? '?', photoUrl: p.str('photo_url')),
            title: Text(p == null ? 'Elegir paciente' : p.str('name') ?? ''),
            subtitle: Text(
              p == null ? 'Busca por mascota o propietario' : [p.str('species'), owner?.str('name')].whereType<String>().join(' · '),
            ),
            trailing: onTap == null ? null : Icon(p == null ? Icons.search : Icons.swap_horiz),
            onTap: onTap,
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ),
      ],
    );
  }
}

// ── Agendar / reprogramar ───────────────────────────────────────────────────

/// Agendar una cita nueva o reprogramar [appointment]. Devuelve la cita guardada.
class AppointmentFormScreen extends StatefulWidget {
  const AppointmentFormScreen({super.key, this.appointment, this.pet, this.day, this.reason});

  final Map<String, dynamic>? appointment;

  /// Paciente ya elegido (al agendar desde su ficha).
  final Map<String, dynamic>? pet;

  /// Día propuesto (el que se está mirando en la agenda).
  final DateTime? day;

  /// Motivo propuesto (p. ej. «Revisión: otitis»).
  final String? reason;

  @override
  State<AppointmentFormScreen> createState() => _AppointmentFormScreenState();
}

class _AppointmentFormScreenState extends State<AppointmentFormScreen> {
  static const _durations = [15, 20, 30, 45, 60, 90, 120];

  final _reason = TextEditingController();
  final _notes = TextEditingController();
  Map<String, dynamic>? _pet;
  int? _serviceId;
  int? _vetId;
  late DateTime _date;
  late TimeOfDay _time;
  int? _duration;
  bool _confirmed = false;
  bool _saving = false;
  ApiException? _error;

  bool get _editing => widget.appointment != null;

  @override
  void initState() {
    super.initState();
    final a = widget.appointment;
    if (a != null) {
      final start = wallTime(a.str('starts_at')) ?? DateTime.now();
      final end = wallTime(a.str('ends_at'));
      _pet = {...?a.obj('pet'), 'owner': ?a.obj('client')};
      _date = DateUtils.dateOnly(start);
      _time = TimeOfDay.fromDateTime(start);
      _duration = end?.difference(start).inMinutes;
      _serviceId = a.integer('service_id');
      _vetId = a.obj('veterinarian')?.integer('id');
      _reason.text = a.str('reason') ?? '';
      _notes.text = a.str('notes') ?? '';
    } else {
      _pet = widget.pet;
      _reason.text = widget.reason ?? '';
      final now = DateTime.now();
      _date = DateUtils.dateOnly(widget.day ?? now);
      // Hoy: la próxima hora en punto. Otro día: a primera hora.
      _time = DateUtils.isSameDay(_date, now)
          ? TimeOfDay(hour: (now.hour + 1).clamp(0, 23), minute: 0)
          : const TimeOfDay(hour: 9, minute: 0);
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _choosePet() async {
    final pet = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const PetPickerScreen()));
    if (pet != null) setState(() => _pet = pet);
  }

  Future<void> _save(int defaultDuration) async {
    if (_pet == null) {
      setState(() => _error = ApiException(422, 'Elige el paciente.', fieldErrors: {'pet_id': 'Elige el paciente.'}));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final reason = _reason.text.trim();
    final notes = _notes.text.trim();
    final body = {
      if (!_editing) ...{'client_id': (_pet!.obj('owner') ?? _pet!.obj('client'))?['id'], 'pet_id': _pet!['id'], 'confirmed': _confirmed},
      'service_id': _serviceId,
      'veterinarian_id': _vetId,
      'date': isoDate(_date),
      'time': hhmm(_time),
      'duration_minutes': _duration ?? defaultDuration,
      'reason': reason.isEmpty ? null : reason,
      'notes': notes.isEmpty ? null : notes,
    };
    try {
      final api = context.session.api;
      final saved = _editing ? await api.put('/appointments/${widget.appointment!['id']}', body) : await api.post('/appointments', body);
      if (!mounted) return;
      showDone(context, _editing ? 'Cita reprogramada.' : 'Cita agendada.');
      Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Reprogramar cita' : 'Agendar cita')),
      body: Loader<Map<String, dynamic>>(
        load: () => context.session.api.get('/appointments/options'),
        builder: (context, options, reload) {
          final services = options.list('services');
          final professionals = options.list('professionals');
          final defaultDuration = options.integer('default_duration') ?? 30;
          final duration = _duration ?? defaultDuration;
          final durations = {..._durations, duration}.toList()..sort();
          final petError = _error?.field('pet_id') ?? _error?.field('client_id');

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FormErrorText(_error),
              _PetChoice(pet: _pet, onTap: _editing ? null : _choosePet, error: petError),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: services.any((s) => s['id'] == _serviceId) ? _serviceId : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'Servicio (opcional)', errorText: _error?.field('service_id')),
                items: [
                  const DropdownMenuItem<int>(value: null, child: Text('Sin servicio')),
                  for (final s in services)
                    DropdownMenuItem(
                      value: s['id'] as int,
                      child: Text(
                        '${s.str('name')} · ${s.integer('duration_minutes') ?? defaultDuration} min',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _serviceId = v;
                  final minutes = services.where((s) => s['id'] == v).firstOrNull?.integer('duration_minutes');
                  if (minutes != null) _duration = minutes;
                }),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: professionals.any((p) => p['id'] == _vetId) ? _vetId : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'Profesional', errorText: _error?.field('veterinarian_id')),
                items: [
                  const DropdownMenuItem<int>(value: null, child: Text('Sin asignar')),
                  for (final p in professionals)
                    DropdownMenuItem(
                      value: p['id'] as int,
                      child: Text(p.str('name') ?? '', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _vetId = v),
              ),
              const SizedBox(height: 16),
              PickerField(
                label: 'Fecha',
                value: fmtDayLong(_date),
                icon: Icons.calendar_today_outlined,
                error: _error?.field('date'),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime.now().subtract(const Duration(days: 30)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PickerField(
                      label: 'Hora',
                      value: hhmm(_time),
                      icon: Icons.schedule,
                      error: _error?.field('time'),
                      onTap: () async {
                        final picked = await showTimePicker(context: context, initialTime: _time);
                        if (picked != null) setState(() => _time = picked);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: duration,
                      decoration: InputDecoration(labelText: 'Duración', errorText: _error?.field('duration_minutes')),
                      items: [for (final d in durations) DropdownMenuItem(value: d, child: Text('$d min'))],
                      onChanged: (v) => setState(() => _duration = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _reason,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: 'Motivo (opcional)', errorText: _error?.field('reason')),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notes,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Notas internas (opcional)'),
              ),
              if (!_editing)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ya confirmada con el propietario'),
                  value: _confirmed,
                  onChanged: (v) => setState(() => _confirmed = v),
                ),
              const SizedBox(height: 16),
              SaveButton(label: _editing ? 'Guardar cambios' : 'Agendar', saving: _saving, onPressed: () => _save(defaultDuration)),
              if (_vetId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Si el profesional ya tiene otra cita en ese horario, te avisamos antes de guardar.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── Sala de espera ──────────────────────────────────────────────────────────

/// Sala de espera (§3.5): quién llegó y en qué orden, quién está en atención
/// y quién falta llegar hoy. Se actualiza sola cada 30 segundos.
class WaitingRoomScreen extends StatefulWidget {
  const WaitingRoomScreen({super.key});

  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  Timer? _timer;
  int? _busy;
  List<Map<String, dynamic>>? _professionals;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _loader.currentState?.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _walkIn() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const WalkInScreen()));
    if (saved == true) _loader.currentState?.reload();
  }

  Future<void> _act(int id, Future<void> Function() action, String done) async {
    setState(() => _busy = id);
    try {
      await action();
      if (mounted) showDone(context, done);
      _loader.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _assign(Map<String, dynamic> a) async {
    final api = context.session.api;
    try {
      _professionals ??= (await api.get('/appointments/options')).list('professionals');
    } catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (!mounted) return;
    final current = a.obj('veterinarian')?.integer('id');
    final chosen = await showModalBottomSheet<({int? id})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                '¿Quién atiende a ${a.obj('pet')?.str('name') ?? 'este paciente'}?',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final p in _professionals!)
              ListTile(
                leading: Icon(p.flag('is_vet') ? Icons.medical_services_outlined : Icons.person_outline),
                title: Text(p.str('name') ?? ''),
                trailing: p['id'] == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, (id: p['id'] as int)),
              ),
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('Sin asignar'),
              onTap: () => Navigator.pop(context, (id: null)),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen.id == current) return;
    await _act(a['id'] as int, () => api.post('/appointments/${a['id']}/assign', {'veterinarian_id': chosen.id}), 'Profesional asignado.');
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final canEdit = profile.can('appointments.edit');

    return Scaffold(
      appBar: AppBar(leading: shellMenuButton(context), title: const Text('Sala de espera')),
      floatingActionButton: profile.can('appointments.create')
          ? FloatingActionButton.extended(onPressed: _walkIn, icon: const Icon(Icons.directions_walk), label: const Text('Llegó sin cita'))
          : null,
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => context.session.api.get('/waiting-room'),
        builder: (context, data, reload) {
          final waiting = data.list('waiting');
          final inProgress = data.list('in_progress');
          final upcoming = data.list('upcoming');
          final done = data.integer('done_count') ?? 0;

          if (waiting.isEmpty && inProgress.isEmpty && upcoming.isEmpty) {
            return ListView(
              children: [
                EmptyState(
                  icon: Icons.weekend_outlined,
                  message: done > 0 ? 'No queda nadie por atender hoy. Atendidos o cerrados: $done.' : 'Nadie en la sala de espera.',
                ),
              ],
            );
          }

          Widget open(Map<String, dynamic> a) => ListTile(
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AppointmentScreen(id: a['id'] as int)));
              reload();
            },
            leading: PetAvatar(name: a.obj('pet')?.str('name') ?? '?', photoUrl: a.obj('pet')?.str('photo_url')),
            title: Text('${a.obj('pet')?.str('name') ?? ''}${a.flag('is_walk_in') ? ' · sin cita' : ''}'),
            subtitle: Text(
              [a.str('reason') ?? a.str('service'), a.obj('pet')?.obj('owner')?.str('name')].whereType<String>().join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          );

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              SectionTitle('En espera (${waiting.length})'),
              if (waiting.isEmpty) const ListTile(title: Text('Nadie esperando.')),
              for (final (i, a) in waiting.indexed)
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      open(a),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  StatusChip(
                                    '${i + 1}º · ${a.date('checked_in_at') == null ? 'en espera' : 'llegó ${fmtAgo(a.date('checked_in_at'))}'}',
                                    tone: 'warning',
                                  ),
                                  Text(
                                    a.obj('veterinarian')?.str('name') ?? 'Sin asignar',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: a.obj('veterinarian') == null ? toneColor(context, 'danger') : null,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (canEdit)
                              TextButton.icon(
                                onPressed: _busy == null ? () => _assign(a) : null,
                                icon: _busy == a['id']
                                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.person_add_alt, size: 18),
                                label: Text(a.obj('veterinarian') == null ? 'Asignar' : 'Cambiar'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (inProgress.isNotEmpty) ...[
                SectionTitle('En atención (${inProgress.length})'),
                for (final a in inProgress) AppointmentTile(appointment: a, onChanged: reload),
              ],
              if (upcoming.isNotEmpty) ...[
                SectionTitle('Por llegar hoy (${upcoming.length})'),
                for (final a in upcoming)
                  ListTile(
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AppointmentScreen(id: a['id'] as int)));
                      reload();
                    },
                    leading: SizedBox(
                      width: 52,
                      child: Center(
                        child: Text(fmtTime(a.date('starts_at')), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    title: Text(a.obj('pet')?.str('name') ?? ''),
                    subtitle: Text(
                      [a.obj('pet')?.obj('owner')?.str('name'), a.obj('veterinarian')?.str('name')].whereType<String>().join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: canEdit
                        ? FilledButton.tonal(
                            onPressed: _busy == null
                                ? () => _act(
                                    a['id'] as int,
                                    () => context.session.api.post('/appointments/${a['id']}/check_in'),
                                    '${a.obj('pet')?.str('name')} pasó a la sala de espera.',
                                  )
                                : null,
                            child: _busy == a['id']
                                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Llegó'),
                          )
                        : null,
                  ),
              ],
              if (done > 0)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    done == 1 ? '1 cita de hoy ya se cerró.' : '$done citas de hoy ya se cerraron.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Paciente que llega sin cita: entra directo a la sala de espera.
class WalkInScreen extends StatefulWidget {
  const WalkInScreen({super.key, this.pet});

  final Map<String, dynamic>? pet;

  @override
  State<WalkInScreen> createState() => _WalkInScreenState();
}

class _WalkInScreenState extends State<WalkInScreen> {
  final _reason = TextEditingController();
  Map<String, dynamic>? _pet;
  int? _serviceId;
  int? _vetId;
  bool _saving = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _pet = widget.pet;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_pet == null) {
      setState(() => _error = ApiException(422, 'Elige el paciente.', fieldErrors: {'pet_id': 'Elige el paciente.'}));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final reason = _reason.text.trim();
    try {
      await context.session.api.post('/waiting-room', {
        'client_id': (_pet!.obj('owner') ?? _pet!.obj('client'))?['id'],
        'pet_id': _pet!['id'],
        'service_id': _serviceId,
        'veterinarian_id': _vetId,
        'reason': reason.isEmpty ? null : reason,
      });
      if (!mounted) return;
      showDone(context, '${_pet!.str('name')} está en la sala de espera.');
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
      appBar: AppBar(title: const Text('Llegó sin cita')),
      body: Loader<Map<String, dynamic>>(
        load: () => context.session.api.get('/appointments/options'),
        builder: (context, options, reload) {
          final services = options.list('services');
          final professionals = options.list('professionals');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FormErrorText(_error),
              _PetChoice(
                pet: _pet,
                error: _error?.field('pet_id') ?? _error?.field('client_id'),
                onTap: () async {
                  final pet = await Navigator.of(
                    context,
                  ).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const PetPickerScreen()));
                  if (pet != null) setState(() => _pet = pet);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _reason,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: '¿A qué viene?', errorText: _error?.field('reason')),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _serviceId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Servicio (opcional)'),
                items: [
                  const DropdownMenuItem<int>(value: null, child: Text('Sin servicio')),
                  for (final s in services)
                    DropdownMenuItem(
                      value: s['id'] as int,
                      child: Text(s.str('name') ?? '', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _serviceId = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _vetId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Profesional',
                  helperText: 'Puedes asignarlo después desde la sala de espera.',
                  errorText: _error?.field('veterinarian_id'),
                ),
                items: [
                  const DropdownMenuItem<int>(value: null, child: Text('Sin asignar')),
                  for (final p in professionals)
                    DropdownMenuItem(
                      value: p['id'] as int,
                      child: Text(p.str('name') ?? '', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _vetId = v),
              ),
              const SizedBox(height: 24),
              SaveButton(label: 'Pasar a la sala de espera', saving: _saving, onPressed: _save),
            ],
          );
        },
      ),
    );
  }
}
