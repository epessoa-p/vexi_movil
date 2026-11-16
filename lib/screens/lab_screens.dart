import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'consultation_screens.dart';
import 'reception_screens.dart';
import 'shell.dart';

// ── Piezas ──────────────────────────────────────────────────────────────────

/// Ícono por categoría del estudio (las etiquetas vienen del servidor).
IconData labIcon(String? category) => switch (category) {
  'Hematología' => Icons.bloodtype_outlined,
  'Bioquímica' => Icons.science_outlined,
  'Orina' => Icons.water_drop_outlined,
  'Parasitología' => Icons.bug_report_outlined,
  'Imagen' => Icons.image_search_outlined,
  _ => Icons.biotech_outlined,
};

/// «Bajo» / «Alto» con el color de alerta; nada si está en rango.
String? flagLabel(String? flag) => switch (flag) {
  'low' => 'Bajo',
  'high' => 'Alto',
  _ => null,
};

/// Un estudio en un listado.
class LabTile extends StatelessWidget {
  const LabTile({super.key, required this.lab, required this.onTap, this.showPet = true});

  final Map<String, dynamic> lab;
  final VoidCallback onTap;
  final bool showPet;

  @override
  Widget build(BuildContext context) {
    final pet = lab.obj('pet');
    final out = lab.integer('out_of_range') ?? 0;
    final badge = lab.obj('status_badge') ?? {};

    return ListTile(
      onTap: onTap,
      leading: showPet && pet != null
          ? PetAvatar(name: pet.str('name') ?? '?', photoUrl: pet.str('photo_url'))
          : CircleAvatar(child: Icon(labIcon(lab.str('category')), size: 20)),
      title: Text(
        [if (showPet) pet?.str('name'), lab.str('study')].whereType<String>().join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          fmtDate(lab.date('requested_at')),
          lab.str('requester'),
          lab.str('external_lab'),
          if (showPet) pet?.obj('owner')?.str('name'),
        ].whereType<String>().join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          StatusChip(badge.str('label') ?? '', tone: badge.str('color')),
          if (out > 0) ...[
            const SizedBox(height: 4),
            Text(
              out == 1 ? '1 fuera de rango' : '$out fuera de rango',
              style: TextStyle(color: toneColor(context, 'danger'), fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Sección Laboratorio ─────────────────────────────────────────────────────

/// Estudios de la veterinaria: pendientes (solicitados y en proceso),
/// completados por entregar y todos, con búsqueda por paciente.
class LabScreen extends StatefulWidget {
  const LabScreen({super.key});

  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> {
  String _term = '';
  bool _mine = false;
  int _version = 0;

  Future<void> _open(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LabRequestScreen(id: id)));
    if (mounted) setState(() => _version++);
  }

  Future<void> _request() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LabRequestForm()));
    if (created == true && mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;

    Widget list(String key, Map<String, String?> query, String empty, String Function(int) count) => PagedList(
      key: ValueKey('$key-$_term-$_mine-$_version'),
      path: '/lab',
      term: _term,
      query: {...query, 'mine': _mine ? '1' : null},
      empty: _term.isEmpty ? empty : 'No encontramos estudios de «$_term».',
      count: count,
      itemBuilder: (context, l) => LabTile(lab: l, onTap: () => _open(l['id'] as int)),
    );

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: shellMenuButton(context),
          title: const Text('Laboratorio'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(label: const Text('Míos'), selected: _mine, onSelected: (v) => setState(() => _mine = v)),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Pendientes'),
              Tab(text: 'Completados'),
              Tab(text: 'Todos'),
            ],
          ),
        ),
        floatingActionButton: profile.can('lab_requests.create')
            ? FloatingActionButton.extended(onPressed: _request, icon: const Icon(Icons.add), label: const Text('Solicitar'))
            : null,
        body: Column(
          children: [
            SearchField(hint: 'Mascota o propietario', onChanged: (v) => setState(() => _term = v)),
            Expanded(
              child: TabBarView(
                children: [
                  list(
                    'open',
                    {'status': 'open'},
                    'No hay estudios pendientes.',
                    (n) => n == 1 ? '1 estudio pendiente' : '$n estudios pendientes',
                  ),
                  list(
                    'completed',
                    {'status': 'completed'},
                    'No hay resultados por entregar.',
                    (n) => n == 1 ? '1 estudio por entregar' : '$n estudios por entregar',
                  ),
                  list('all', {}, 'Todavía no hay estudios.', (n) => n == 1 ? '1 estudio' : '$n estudios'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Estudios de una mascota (pestaña de la ficha), con «Solicitar estudio».
class PetLabTab extends StatefulWidget {
  const PetLabTab({super.key, required this.pet});

  final Map<String, dynamic> pet;

  @override
  State<PetLabTab> createState() => _PetLabTabState();
}

class _PetLabTabState extends State<PetLabTab> {
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final petId = widget.pet['id'] as int;

    return Column(
      children: [
        if (profile.can('lab_requests.create'))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () async {
                final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => LabRequestForm(pet: widget.pet)));
                if (created == true && mounted) setState(() => _version++);
              },
              icon: const Icon(Icons.biotech_outlined),
              label: const Text('Solicitar estudio'),
            ),
          ),
        Expanded(
          child: PagedList(
            key: ValueKey('pet-lab-$_version'),
            path: '/lab',
            term: '',
            query: {'pet_id': '$petId'},
            empty: 'Sin estudios de laboratorio.',
            count: (n) => n == 1 ? '1 estudio' : '$n estudios',
            itemBuilder: (context, l) => LabTile(
              lab: l,
              showPet: false,
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LabRequestScreen(id: l['id'] as int)));
                if (mounted) setState(() => _version++);
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ── Detalle ─────────────────────────────────────────────────────────────────

/// Un estudio: resultados con alertas de rango, fotos e informes adjuntos,
/// avance (en proceso, entregado, anulado) e informe en PDF para compartir.
class LabRequestScreen extends StatefulWidget {
  const LabRequestScreen({super.key, required this.id});

  final int id;

  @override
  State<LabRequestScreen> createState() => _LabRequestScreenState();
}

class _LabRequestScreenState extends State<LabRequestScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  Map<String, dynamic>? _current;

  /// Archivos ya descargados (miniaturas y vista completa), por id.
  final _files = <int, Future<Uint8List>>{};
  String? _busy;

  Future<Uint8List> _file(Map<String, dynamic> a) =>
      _files.putIfAbsent(a['id'] as int, () => context.session.api.download(a.str('path')!).then(Uint8List.fromList));

  Future<void> _run(String key, Future<void> Function() action, {String? done}) async {
    setState(() => _busy = key);
    try {
      await action();
      if (mounted && done != null) showDone(context, done);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _transition(String action, {String? done}) => _run(action, () async {
    await context.session.api.post('/lab/${widget.id}/$action');
    _loader.currentState?.reload();
  }, done: done);

  Future<void> _cancel() async {
    final reason = await showDialog<String>(context: context, builder: (_) => const _CancelDialog());
    if (reason == null || !mounted) return;
    await _run('cancel', () async {
      await context.session.api.post('/lab/${widget.id}/cancel', {'cancel_reason': reason});
      _loader.currentState?.reload();
    }, done: 'Estudio anulado.');
  }

  Future<void> _editResults() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => LabResultsEditor(lab: _current!)));
    if (saved == true) _loader.currentState?.reload();
  }

  /// Foto del informe del laboratorio externo (o de la placa), de la cámara o la galería.
  Future<void> _attach() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Fotografiar informe'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    // Más resolución que la foto de la mascota: el texto del informe tiene que leerse.
    final photo = await ImagePicker().pickImage(source: source, maxWidth: 2400, maxHeight: 2400, imageQuality: 85);
    if (photo == null || !mounted) return;
    final api = context.session.api;
    await _run('attach', () async {
      await api.upload('/lab/${widget.id}/attachments', 'files[]', await photo.readAsBytes(), photo.name);
      _loader.currentState?.reload();
    }, done: 'Archivo adjuntado.');
  }

  Future<void> _detach(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Quitar este archivo?'),
        content: Text(a.str('name') ?? ''),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Quitar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run('detach', () async {
      await context.session.api.delete(a.str('path')!);
      _loader.currentState?.reload();
    });
  }

  Future<void> _openFile(Map<String, dynamic> a) async {
    if (a.flag('is_image')) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _ImageViewer(title: a.str('name') ?? '', bytes: _file(a)),
        ),
      );
      return;
    }
    // Un PDF se abre con lo que el teléfono tenga (visor, WhatsApp, Drive…).
    await _run('file-${a['id']}', () async {
      final bytes = await _file(a);
      await _share(bytes, a.str('name') ?? 'archivo.pdf', a.str('mime_type') ?? 'application/pdf');
    });
  }

  Future<void> _shareReport() => _run('report', () async {
    final c = _current!;
    final bytes = await context.session.api.download('/lab/${widget.id}/report.pdf');
    final pet = c.obj('pet')?.str('name') ?? 'paciente';
    await _share(Uint8List.fromList(bytes), 'Informe-${c.str('code')}-$pet.pdf', 'application/pdf', text: '${c.str('study')} de $pet');
  });

  Future<void> _share(Uint8List bytes, String name, String mime, {String? text}) => SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: mime, name: name)],
      fileNameOverrides: [name],
      text: text,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final c = _current;
    final canResults = profile.can('lab_results.edit') && (c?.flag('editable') ?? false);
    final canStatus = profile.can('lab_requests.edit');
    final actions = [for (final a in (c?['actions'] as List? ?? const [])) '$a'];

    return Scaffold(
      appBar: AppBar(
        title: Text(c?.str('code') ?? 'Estudio'),
        actions: [
          if (c != null && c.flag('report_available'))
            IconButton(
              tooltip: 'Compartir informe (PDF)',
              onPressed: _busy == null ? _shareReport : null,
              icon: _busy == 'report'
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.share_outlined),
            ),
          if (canStatus && actions.contains('cancel'))
            PopupMenuButton<String>(
              tooltip: 'Más acciones',
              onSelected: (_) => _cancel(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'cancel',
                  child: ListTile(
                    leading: Icon(Icons.block, color: Theme.of(context).colorScheme.error),
                    title: const Text('Anular estudio'),
                  ),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: canResults && c != null
          ? FloatingActionButton.extended(
              onPressed: _busy == null ? _attach : null,
              icon: _busy == 'attach'
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_a_photo_outlined),
              label: const Text('Adjuntar foto'),
            )
          : null,
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () async {
          final data = await context.session.api.get('/lab/${widget.id}');
          if (mounted) setState(() => _current = data);
          return data;
        },
        builder: (context, l, reload) {
          final pet = l.obj('pet') ?? {};
          final badge = l.obj('status_badge') ?? {};
          final results = l.list('results');
          final attachments = l.list('attachments');
          final out = l.integer('out_of_range') ?? 0;
          final consultation = l.obj('consultation');
          final muted = Theme.of(context).colorScheme.onSurfaceVariant;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Row(
                children: [
                  PetAvatar(name: pet.str('name') ?? '?', photoUrl: pet.str('photo_url'), radius: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.str('study') ?? '', style: Theme.of(context).textTheme.titleLarge),
                        Text(
                          [pet.str('name'), pet.str('species'), pet.obj('owner')?.str('name')].whereType<String>().join(' · '),
                          style: TextStyle(color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  StatusChip(badge.str('label') ?? '', tone: badge.str('color')),
                  if (l.str('category') != null) StatusChip(l.str('category')!),
                ],
              ),
              if (l.str('status') == 'cancelled') ...[
                const SizedBox(height: 12),
                _Banner(icon: Icons.block, tone: 'dark', text: 'Anulado: ${l.str('cancel_reason') ?? ''}'),
              ],
              if (out > 0) ...[
                const SizedBox(height: 12),
                _Banner(
                  icon: Icons.warning_amber,
                  tone: 'danger',
                  text: out == 1 ? '1 valor fuera del rango de referencia.' : '$out valores fuera del rango de referencia.',
                ),
              ],
              if (canResults || (canStatus && (actions.contains('start') || actions.contains('deliver')))) ...[
                const SizedBox(height: 12),
                if (canResults)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: _busy == null ? _editResults : null,
                    icon: const Icon(Icons.edit_note),
                    label: Text(results.isEmpty && (l.str('result_notes') ?? '').isEmpty ? 'Cargar resultados' : 'Editar resultados'),
                  ),
                if (canStatus && actions.contains('start')) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    onPressed: _busy == null ? () => _transition('start', done: 'Estudio en proceso.') : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Marcar en proceso'),
                  ),
                ],
                if (canStatus && actions.contains('deliver'))
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: _busy == null ? () => _transition('deliver', done: 'Resultados entregados.') : null,
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Marcar entregado al propietario'),
                  ),
              ],
              if (results.isNotEmpty) ...[
                const SectionTitle('Resultados'),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [for (final r in results) _ResultTile(result: r)]),
                ),
              ] else if (!canResults && (l.str('result_notes') ?? '').isEmpty && l.str('status') != 'cancelled') ...[
                const SizedBox(height: 16),
                const EmptyState(icon: Icons.hourglass_empty, message: 'Todavía no hay resultados.'),
              ],
              if ((l.str('result_notes') ?? '').isNotEmpty) ...[const SectionTitle('Observaciones'), Text(l.str('result_notes')!)],
              if (l.str('result_date') != null) ...[
                const SizedBox(height: 8),
                Text(
                  ['Resultado del ${fmtDate(l.date('result_date'))}', l.obj('responsible')?.str('name')].whereType<String>().join(' · '),
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ],
              if (attachments.isNotEmpty || canResults) ...[
                const SectionTitle('Documentos e imágenes'),
                if (attachments.isEmpty)
                  Text('Fotografía el informe del laboratorio externo o la placa con «Adjuntar foto».', style: TextStyle(color: muted))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final a in attachments)
                        _AttachmentThumb(
                          attachment: a,
                          bytes: a.flag('is_image') ? _file(a) : null,
                          loading: _busy == 'file-${a['id']}',
                          onTap: () => _openFile(a),
                          onRemove: canResults && _busy == null ? () => _detach(a) : null,
                        ),
                    ],
                  ),
              ],
              const SectionTitle('Solicitud'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      Fact('Fecha', fmtDate(l.date('requested_at'))),
                      Fact('Solicitó', l.str('requester') ?? '—'),
                      if (l.str('external_lab') != null) Fact('Laboratorio', l.str('external_lab')!),
                    ],
                  ),
                ),
              ),
              if (consultation != null && profile.canUse('consultas', 'consultations.view')) ...[
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.medical_services_outlined),
                    title: Text('Consulta del ${fmtDate(consultation.date('started_at'))}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConsultationScreen(id: consultation['id'] as int))),
                  ),
                ),
              ],
              if ((l.str('notes') ?? '').isNotEmpty) ...[const SectionTitle('Indicaciones de la solicitud'), Text(l.str('notes')!)],
              const SectionTitle('Seguimiento'),
              for (final t in l.list('timeline'))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.check_circle_outline, color: toneColor(context, 'success')),
                  title: Text(t.str('label') ?? ''),
                  trailing: Text(fmtDateTime(t.date('at'))),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.tone, required this.text});

  final IconData icon;
  final String tone;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(context, tone);
    return Card(
      color: color.withValues(alpha: .12),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          text,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final flag = flagLabel(result.str('flag'));
    final color = flag != null ? toneColor(context, 'danger') : null;
    final value = [result.str('value') ?? '—', result.str('unit')].whereType<String>().join(' ');

    return ListTile(
      dense: true,
      title: Text(result.str('name') ?? ''),
      subtitle: result.str('reference') == null ? null : Text('Ref. ${result.str('reference')}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: color),
          ),
          if (flag != null) ...[const SizedBox(width: 8), StatusChip(flag, tone: 'danger')],
        ],
      ),
    );
  }
}

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({required this.attachment, required this.onTap, this.bytes, this.onRemove, this.loading = false});

  final Map<String, dynamic> attachment;
  final Future<Uint8List>? bytes;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const size = 104.0;

    final Widget content = bytes != null
        ? FutureBuilder<Uint8List>(
            future: bytes,
            builder: (context, snap) => snap.hasData
                ? Image.memory(snap.data!, fit: BoxFit.cover, width: size, height: size)
                : Center(
                    child: snap.hasError
                        ? Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant)
                        : const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
          )
        : Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                loading
                    ? const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.picture_as_pdf_outlined, size: 32, color: toneColor(context, 'danger')),
                const SizedBox(height: 6),
                Text(
                  attachment.str('name') ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          );

    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: Material(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: onTap, child: content),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 2,
              right: 2,
              child: IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                tooltip: 'Quitar',
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.title, required this.bytes});

  final String title;
  final Future<Uint8List> bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(title)),
      body: FutureBuilder<Uint8List>(
        future: bytes,
        builder: (context, snap) => snap.hasData
            ? InteractiveViewer(maxScale: 6, child: Center(child: Image.memory(snap.data!)))
            : Center(
                child: snap.hasError
                    ? const Text('No se pudo abrir la imagen.', style: TextStyle(color: Colors.white))
                    : const CircularProgressIndicator(),
              ),
      ),
    );
  }
}

class _CancelDialog extends StatefulWidget {
  const _CancelDialog();

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Anular estudio'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Para corregir un estudio cerrado se anula y se solicita de nuevo.'),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLength: 255,
            decoration: const InputDecoration(labelText: 'Motivo'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
        FilledButton(
          onPressed: _reason.text.trim().isEmpty ? null : () => Navigator.pop(context, _reason.text.trim()),
          child: const Text('Anular'),
        ),
      ],
    );
  }
}

// ── Cargar resultados ───────────────────────────────────────────────────────

class _ResultRow {
  _ResultRow(Map<String, dynamic> row)
    : fixed = (row.str('name') ?? '').isNotEmpty,
      name = TextEditingController(text: row.str('name')),
      value = TextEditingController(text: row.str('value')),
      unit = TextEditingController(text: row.str('unit')),
      referenceMin = row.number('reference_min'),
      referenceMax = row.number('reference_max'),
      referenceText = row.str('reference_text');

  /// Las filas del estudio traen el nombre; las agregadas se escriben.
  final bool fixed;
  final TextEditingController name;
  final TextEditingController value;
  final TextEditingController unit;
  final double? referenceMin;
  final double? referenceMax;
  final String? referenceText;

  /// La misma regla que el servidor: solo valores numéricos con referencia.
  String? get flag {
    final v = double.tryParse(value.text.trim().replaceAll(',', '.'));
    if (v == null || (referenceMin == null && referenceMax == null)) return null;
    if (referenceMin != null && v < referenceMin!) return 'low';
    if (referenceMax != null && v > referenceMax!) return 'high';
    return 'normal';
  }

  String? get reference => switch ((referenceMin, referenceMax)) {
    (final double min, final double max) => '${fmtNumber(min)} – ${fmtNumber(max)}',
    (final double min, null) => '≥ ${fmtNumber(min)}',
    (null, final double max) => '≤ ${fmtNumber(max)}',
    _ => referenceText,
  };

  Map<String, dynamic> toJson() => {
    'name': name.text.trim(),
    'value': value.text.trim().isEmpty ? null : value.text.trim(),
    'unit': unit.text.trim().isEmpty ? null : unit.text.trim(),
    'reference_min': referenceMin,
    'reference_max': referenceMax,
    'reference_text': referenceText,
  };

  void dispose() {
    name.dispose();
    value.dispose();
    unit.dispose();
  }
}

/// Carga de resultados: una fila por parámetro del estudio (con su
/// referencia), observaciones, fecha y responsable. «Completar» cierra el
/// estudio y avisa a quien lo solicitó.
class LabResultsEditor extends StatefulWidget {
  const LabResultsEditor({super.key, required this.lab});

  /// El detalle de `GET /lab/{id}` (trae `rows`).
  final Map<String, dynamic> lab;

  @override
  State<LabResultsEditor> createState() => _LabResultsEditorState();
}

class _LabResultsEditorState extends State<LabResultsEditor> {
  late final List<_ResultRow> _rows = [for (final r in widget.lab.list('rows')) _ResultRow(r)];
  late final _notes = TextEditingController(text: widget.lab.str('result_notes'));
  late DateTime _date = widget.lab.date('result_date') ?? DateTime.now();
  int? _responsible;
  List<Map<String, dynamic>> _professionals = const [];
  ApiException? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _responsible = widget.lab.obj('responsible')?.integer('id') ?? context.read<Session>().profile?.userId;
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final options = await context.session.api.get('/lab/options');
      if (mounted) setState(() => _professionals = options.list('professionals'));
    } catch (_) {
      // Sin la lista, el servidor usa a quien completa.
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save({required bool finish}) async {
    if (finish) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Completar el estudio?'),
          content: const Text('Los resultados quedan cerrados y ya no se pueden editar. Se avisa a quien lo solicitó.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Completar')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.session.api.put('/lab/${widget.lab['id']}/results', {
        'results': [
          for (final r in _rows)
            if (r.name.text.trim().isNotEmpty) r.toJson(),
        ],
        'result_notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'result_date': isoDate(_date),
        'responsible_id': _responsible,
        'finish': finish,
      });
      if (!mounted) return;
      showDone(context, finish ? 'Estudio completado.' : 'Resultados guardados.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: Text(widget.lab.str('study') ?? 'Resultados')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            [widget.lab.obj('pet')?.str('name'), widget.lab.str('code')].whereType<String>().join(' · '),
            style: TextStyle(color: muted),
          ),
          const SectionTitle('Valores'),
          if (_rows.isEmpty)
            Text('Este estudio no tiene parámetros: describe el resultado en observaciones o agrega uno.', style: TextStyle(color: muted)),
          for (final (i, r) in _rows.indexed) _rowEditor(i, r),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _rows.add(_ResultRow(const {}))),
              icon: const Icon(Icons.add),
              label: const Text('Agregar parámetro'),
            ),
          ),
          if (_error?.field('results') != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!.field('results')!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SectionTitle('Informe'),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'Observaciones', errorText: _error?.field('result_notes')),
          ),
          const SizedBox(height: 12),
          PickerField(
            label: 'Fecha del resultado',
            value: fmtDate(_date),
            icon: Icons.event,
            error: _error?.field('result_date'),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          if (_professionals.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _professionals.any((p) => p['id'] == _responsible) ? _responsible : null,
              decoration: InputDecoration(labelText: 'Responsable', errorText: _error?.field('responsible_id')),
              items: [for (final p in _professionals) DropdownMenuItem(value: p['id'] as int, child: Text(p.str('name') ?? ''))],
              onChanged: (v) => setState(() => _responsible = v),
            ),
          ],
          const SizedBox(height: 20),
          FormErrorText(_error),
          SaveButton(label: 'Completar estudio', saving: _saving, onPressed: () => _save(finish: true)),
          const SizedBox(height: 8),
          SaveButton(label: 'Guardar borrador', saving: _saving, outlined: true, onPressed: () => _save(finish: false)),
        ],
      ),
    );
  }

  Widget _rowEditor(int i, _ResultRow r) {
    final flag = flagLabel(r.flag);
    final danger = toneColor(context, 'danger');
    final error = _error?.field('results.$i.name') ?? _error?.field('results.$i.value');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: r.fixed
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.name.text, style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (r.reference != null)
                          Text(
                            'Ref. ${r.reference}',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      TextField(
                        controller: r.name,
                        decoration: const InputDecoration(labelText: 'Parámetro', isDense: true),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: r.unit,
                        decoration: const InputDecoration(labelText: 'Unidad', isDense: true),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: TextField(
              controller: r.value,
              keyboardType: TextInputType.text,
              onChanged: (_) => setState(() {}),
              style: flag != null ? TextStyle(color: danger, fontWeight: FontWeight.w700) : null,
              decoration: InputDecoration(
                labelText: 'Valor',
                isDense: true,
                suffixText: r.fixed ? r.unit.text : null,
                helperText: flag,
                helperStyle: TextStyle(color: danger, fontWeight: FontWeight.w600),
                errorText: error,
              ),
            ),
          ),
          if (!r.fixed)
            IconButton(
              tooltip: 'Quitar parámetro',
              onPressed: () => setState(() => _rows.removeAt(i).dispose()),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }
}

// ── Solicitar ───────────────────────────────────────────────────────────────

/// Solicitar uno o varios estudios para una mascota (uno por tipo elegido),
/// opcionalmente ligados a una consulta. Devuelve true si se creó alguno.
class LabRequestForm extends StatefulWidget {
  const LabRequestForm({super.key, this.pet, this.consultationId});

  /// Mascota ya elegida (desde la ficha o la consulta): al menos `id` y `name`.
  final Map<String, dynamic>? pet;
  final int? consultationId;

  @override
  State<LabRequestForm> createState() => _LabRequestFormState();
}

class _LabRequestFormState extends State<LabRequestForm> {
  late Map<String, dynamic>? _pet = widget.pet;
  final _selected = <int>{};
  final _externalLab = TextEditingController();
  final _notes = TextEditingController();
  ApiException? _error;
  bool _saving = false;

  @override
  void dispose() {
    _externalLab.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickPet() async {
    final pet = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const PetPickerScreen()));
    if (pet != null) setState(() => _pet = pet);
  }

  Future<void> _submit() async {
    if (_pet == null) {
      showError(context, 'Elige el paciente.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await context.session.api.post('/lab', {
        'pet_id': _pet!['id'],
        'consultation_id': widget.consultationId,
        'study_types': _selected.toList(),
        'external_lab': _externalLab.text.trim().isEmpty ? null : _externalLab.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (!mounted) return;
      final items = created.list('data');
      if (items.length == 1) {
        await Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => LabRequestScreen(id: items.single['id'] as int)), result: true);
        return;
      }
      showDone(context, '${items.length} estudios solicitados.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Solicitar estudio')),
      body: Loader<Map<String, dynamic>>(
        load: () => context.session.api.get('/lab/options'),
        builder: (context, options, reload) {
          final types = options.list('study_types');
          final byCategory = <String, List<Map<String, dynamic>>>{};
          for (final t in types) {
            byCategory.putIfAbsent(t.str('category_label') ?? 'Otros', () => []).add(t);
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (widget.pet == null)
                PickerField(
                  label: 'Paciente',
                  value: _pet == null ? 'Elegir…' : [_pet!.str('name'), _pet!.obj('owner')?.str('name')].whereType<String>().join(' · '),
                  icon: Icons.pets,
                  error: _error?.field('pet_id') ?? _error?.field('client_id'),
                  onTap: _pickPet,
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: PetAvatar(name: _pet!.str('name') ?? '?', photoUrl: _pet!.str('photo_url')),
                  title: Text(_pet!.str('name') ?? ''),
                  subtitle: widget.consultationId != null ? const Text('Ligado a la consulta') : null,
                ),
              SectionTitle(_selected.isEmpty ? 'Estudios' : 'Estudios (${_selected.length})'),
              if (_error?.field('study_types') != null)
                Text(_error!.field('study_types')!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              if (types.isEmpty)
                Text('No hay estudios activos. Se configuran en la web (Configuración › Estudios).', style: TextStyle(color: muted)),
              for (final group in byCategory.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(labIcon(group.key), size: 18, color: muted),
                      const SizedBox(width: 6),
                      Text(
                        group.key,
                        style: TextStyle(color: muted, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                for (final t in group.value)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _selected.contains(t['id']),
                    onChanged: (v) => setState(() => v == true ? _selected.add(t['id'] as int) : _selected.remove(t['id'])),
                    title: Text(t.str('name') ?? ''),
                    subtitle: t.str('description') == null
                        ? null
                        : Text(t.str('description')!, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
              ],
              const SectionTitle('Detalles'),
              TextField(
                controller: _externalLab,
                decoration: InputDecoration(
                  labelText: 'Laboratorio externo (opcional)',
                  hintText: 'Si la muestra se envía fuera',
                  errorText: _error?.field('external_lab'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: 'Indicaciones (opcional)', errorText: _error?.field('notes')),
              ),
              const SizedBox(height: 20),
              FormErrorText(_error),
              SaveButton(
                label: _selected.length > 1 ? 'Solicitar ${_selected.length} estudios' : 'Solicitar',
                saving: _saving,
                onPressed: _selected.isEmpty ? () => showError(context, 'Elige al menos un estudio.') : _submit,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Estudios de una consulta (en el expediente), con «Solicitar».
class ConsultationLabSection extends StatelessWidget {
  const ConsultationLabSection({super.key, required this.consultation, required this.onChanged});

  final Map<String, dynamic> consultation;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final labs = consultation['lab_requests'] == null ? null : consultation.list('lab_requests');
    if (labs == null) return const SizedBox.shrink();
    final canRequest = profile.can('lab_requests.create');
    if (labs.isEmpty && !canRequest) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Laboratorio',
          trailing: canRequest
              ? TextButton.icon(
                  onPressed: () async {
                    await requestLabFor(context, consultation);
                    onChanged();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Solicitar'),
                )
              : null,
        ),
        if (labs.isEmpty) Text('Sin estudios solicitados.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        for (final l in labs)
          LabTile(
            lab: l,
            showPet: false,
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LabRequestScreen(id: l['id'] as int)));
              onChanged();
            },
          ),
      ],
    );
  }
}

/// Abre el formulario de solicitud ligado a [consultation].
Future<bool?> requestLabFor(BuildContext context, Map<String, dynamic> consultation) => Navigator.of(context).push<bool>(
  MaterialPageRoute(
    builder: (_) => LabRequestForm(pet: consultation.obj('pet'), consultationId: consultation['id'] as int),
  ),
);

/// ¿Puede el usuario ver laboratorio? (plan + permiso).
bool labVisible(Profile p) => p.canUse('laboratorio', 'lab_requests.view');
