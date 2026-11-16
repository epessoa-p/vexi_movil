import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'shell.dart';

/// Inventario (§17.7): buscar productos (también con la cámara), stock,
/// vencimientos, conteo físico, entradas, salidas y kardex.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  String _term = '';
  String? _status;
  int _version = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _scan({required bool count}) async {
    await scanProducts(context, count: count);
    if (mounted) setState(() => _version++); // el stock pudo cambiar
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final symbol = profile.company?.currencySymbol ?? '';
    final canMove = profile.can('inventory.create');

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: shellMenuButton(context),
          title: const Text('Inventario'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Productos'),
              Tab(text: 'Vencimientos'),
            ],
          ),
        ),
        floatingActionButton: canMove
            ? FloatingActionButton.extended(
                onPressed: () => _scan(count: true),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Contar'),
              )
            : null,
        body: TabBarView(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SearchBar(
                    controller: _query,
                    hintText: 'Nombre, código o marca',
                    leading: const Icon(Icons.search),
                    trailing: [
                      IconButton(
                        tooltip: 'Escanear código de barras',
                        onPressed: () => _scan(count: false),
                        icon: const Icon(Icons.qr_code_scanner),
                      ),
                    ],
                    elevation: const WidgetStatePropertyAll(0),
                    onChanged: (v) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _term = v.trim()));
                    },
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (final f in const {null: 'Todos', 'low': 'Stock bajo', 'out': 'Agotados'}.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(f.value),
                            selected: _status == f.key,
                            onSelected: (_) => setState(() => _status = f.key),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Loader<Map<String, dynamic>>(
                    key: ValueKey('$_term-$_status-$_version'),
                    load: () => context.session.api.get('/products', query: {'q': _term, 'status': _status}),
                    builder: (context, data, reload) {
                      final items = data.list('data');
                      if (items.isEmpty) {
                        return ListView(
                          children: const [EmptyState(icon: Icons.inventory_2_outlined, message: 'No hay productos con ese filtro.')],
                        );
                      }
                      final total = data.obj('meta')?.integer('total') ?? items.length;
                      return ListView(
                        padding: const EdgeInsets.only(bottom: 88),
                        children: [
                          for (final p in items)
                            _ProductTile(
                              product: p,
                              symbol: symbol,
                              onTap: () async {
                                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductScreen(id: p['id'] as int)));
                                reload();
                              },
                            ),
                          if (total > items.length)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Mostrando ${items.length} de $total. Afina la búsqueda para encontrar el resto.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
            const _ExpiringTab(),
          ],
        ),
      ),
    );
  }
}

/// Escanea y abre el producto. Con [count], abre directo el conteo y, al
/// guardar con «Guardar y escanear otro», vuelve a la cámara.
Future<void> scanProducts(BuildContext context, {required bool count}) async {
  final navigator = Navigator.of(context);
  final api = context.session.api;
  while (true) {
    final code = await navigator.push<String>(
      MaterialPageRoute(builder: (_) => BarcodeScanScreen(title: count ? 'Contar: escanea el producto' : 'Buscar por código')),
    );
    if (code == null || !context.mounted) return;

    final Map<String, dynamic> product;
    try {
      product = await api.get('/products/lookup', query: {'code': code});
    } catch (e) {
      if (!context.mounted) return;
      showError(context, e);
      continue; // de vuelta a la cámara para probar con otro
    }
    if (!context.mounted) return;

    if (!count) {
      await navigator.push(MaterialPageRoute(builder: (_) => ProductScreen(id: product['id'] as int)));
      return;
    }
    final next = await navigator.push<String>(
      MaterialPageRoute(
        builder: (_) => StockMoveScreen(product: product, operation: 'adjustment', chained: true),
      ),
    );
    if (next != 'next') return;
  }
}

/// Cámara para leer un código de barras (o escribirlo a mano). Devuelve el código.
class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key, this.title = 'Escanear código'});

  final String title;

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish(String code) {
    if (_done || code.trim().isEmpty) return;
    _done = true;
    Navigator.of(context).pop(code.trim());
  }

  Future<void> _type() async {
    final code = await askText(context, title: 'Escribir el código', label: 'Código de barras o código interno', action: 'Buscar');
    if (code != null && mounted) _finish(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [IconButton(tooltip: 'Linterna', onPressed: _controller.toggleTorch, icon: const Icon(Icons.flashlight_on_outlined))],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final window = Rect.fromCenter(
            center: constraints.biggest.center(Offset.zero),
            width: constraints.maxWidth * .8,
            height: constraints.maxWidth * .45,
          );
          return Stack(
            children: [
              MobileScanner(
                controller: _controller,
                scanWindow: window,
                onDetect: (capture) {
                  final code = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
                  if (code != null) _finish(code);
                },
                errorBuilder: (context, error) => _ScanError(error: error, onType: _type),
              ),
              // Recuadro guía: lo de afuera se oscurece.
              IgnorePointer(
                child: CustomPaint(size: constraints.biggest, painter: _WindowPainter(window)),
              ),
              Positioned(
                left: 24,
                right: 24,
                top: window.bottom + 24,
                child: const Text(
                  'Apunta al código de barras del producto',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 24 + MediaQuery.paddingOf(context).bottom,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _type,
                  icon: const Icon(Icons.keyboard_outlined),
                  label: const Text('Escribir el código'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScanError extends StatelessWidget {
  const _ScanError({required this.error, required this.onType});

  final MobileScannerException error;
  final VoidCallback onType;

  @override
  Widget build(BuildContext context) {
    final message = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied => 'Vexi no tiene permiso para usar la cámara. Actívalo en los ajustes del teléfono.',
      MobileScannerErrorCode.unsupported => 'Este dispositivo no puede leer códigos con la cámara.',
      _ => 'No se pudo abrir la cámara.',
    };
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 48),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onType, child: const Text('Escribir el código')),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowPainter extends CustomPainter {
  _WindowPainter(this.window);

  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(window, const Radius.circular(16));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(frame)),
      Paint()..color = Colors.black54,
    );
    canvas.drawRRect(
      frame,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_WindowPainter old) => old.window != window;
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.symbol, required this.onTap});

  final Map<String, dynamic> product;
  final String symbol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final stock = p.number('stock') ?? 0;
    final min = p.number('min_stock') ?? 0;
    final tone = stock <= 0 ? 'danger' : (stock <= min ? 'warning' : 'success');

    return ListTile(
      title: Text(p.str('name') ?? ''),
      subtitle: Text(
        [
          p.str('presentation'),
          p.str('brand'),
          '$symbol ${fmtNumber(p.number('sale_price'))}',
        ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · '),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            fmtNumber(stock),
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: toneColor(context, tone)),
          ),
          Text(p.str('unit') ?? '', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      onTap: onTap,
    );
  }
}

class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key, required this.id});

  final int id;

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  Map<String, dynamic>? _product;

  Future<void> _move(String operation) async {
    final saved = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => StockMoveScreen(product: _product!, operation: operation),
      ),
    );
    if (saved != null) _loader.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final symbol = profile.company?.currencySymbol ?? '';
    final canMove = profile.can('inventory.create');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Producto'),
        actions: [
          if (profile.can('inventory.view'))
            IconButton(
              tooltip: 'Movimientos (kardex)',
              onPressed: _product == null
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MovementsScreen(product: _product!))),
              icon: const Icon(Icons.history),
            ),
        ],
      ),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () async {
          final p = await context.session.api.get('/products/${widget.id}');
          if (mounted) setState(() => _product = p);
          return p;
        },
        builder: (context, p, reload) {
          final stock = p.number('stock') ?? 0;
          final min = p.number('min_stock') ?? 0;
          final tone = stock <= 0 ? 'danger' : (stock <= min ? 'warning' : 'success');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(p.str('name') ?? '', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text([p.str('category'), p.str('brand'), p.str('presentation'), p.str('code')].whereType<String>().join(' · ')),
              if (p.str('barcode') != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(Icons.qr_code_2, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(p.str('barcode')!, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Stock total'),
                            Text(
                              '${fmtNumber(stock)} ${p.str('unit') ?? ''}',
                              style: Theme.of(
                                context,
                              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: toneColor(context, tone)),
                            ),
                            Text('Mínimo: ${fmtNumber(min)}', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Precio de venta'),
                            Text(
                              '$symbol ${fmtNumber(p.number('sale_price'))}',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const Text(''),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (canMove) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                        onPressed: () => _move('adjustment'),
                        icon: const Icon(Icons.fact_check_outlined, size: 18),
                        label: const Text('Contar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                        onPressed: () => _move('in'),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Entrada'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                        onPressed: () => _move('out'),
                        icon: const Icon(Icons.remove, size: 18),
                        label: const Text('Salida'),
                      ),
                    ),
                  ],
                ),
              ],
              if (p.list('by_branch').length > 1) ...[
                const SectionTitle('Por sucursal'),
                for (final b in p.list('by_branch'))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(b.str('branch') ?? ''),
                    trailing: Text(fmtNumber(b.number('quantity'))),
                  ),
              ],
              if (p.list('batches').isNotEmpty) ...[
                const SectionTitle('Lotes disponibles'),
                for (final b in p.list('batches')) BatchTile(batch: b),
              ],
              if ((p.str('description') ?? '').isNotEmpty) ...[const SectionTitle('Descripción'), Text(p.str('description')!)],
            ],
          );
        },
      ),
    );
  }
}

/// Conteo físico (`adjustment`), entrada (`in`) o salida (`out`) de un producto.
/// Devuelve 'saved', o 'next' si se eligió «Guardar y escanear otro».
class StockMoveScreen extends StatefulWidget {
  const StockMoveScreen({super.key, required this.product, required this.operation, this.chained = false});

  final Map<String, dynamic> product;
  final String operation;

  /// Viene del conteo con la cámara: ofrece seguir con el próximo producto.
  final bool chained;

  @override
  State<StockMoveScreen> createState() => _StockMoveScreenState();
}

class _StockMoveScreenState extends State<StockMoveScreen> {
  final _quantity = TextEditingController();
  final _notes = TextEditingController();
  final _lot = TextEditingController();
  final _cost = TextEditingController();
  int? _branchId;
  int? _batchId;
  String? _reason;
  DateTime? _expires;
  String? _saving;
  ApiException? _error;

  Map<String, dynamic> get _p => widget.product;
  bool get _count => widget.operation == 'adjustment';
  bool get _in => widget.operation == 'in';
  bool get _tracked => _p.flag('track_batches');

  static const _titles = {'adjustment': 'Contar', 'in': 'Entrada', 'out': 'Salida'};

  @override
  void dispose() {
    for (final c in [_quantity, _notes, _lot, _cost]) {
      c.dispose();
    }
    super.dispose();
  }

  num? _num(TextEditingController c) => num.tryParse(c.text.replaceAll(',', '.').trim());

  List<Map<String, dynamic>> _batches() => _p.list('batches').where((b) => b['branch_id'] == _branchId).toList();

  /// Lo que dice el sistema para la sucursal (o el lote) elegido.
  num _system() {
    if (_batchId != null) return _batches().where((b) => b['id'] == _batchId).firstOrNull?.number('quantity') ?? 0;
    return _p.list('by_branch').where((b) => b['branch_id'] == _branchId).firstOrNull?.number('quantity') ?? 0;
  }

  Future<void> _save({bool next = false}) async {
    final quantity = _num(_quantity);
    if (quantity == null) {
      setState(() => _error = ApiException(422, 'Indica la cantidad.', fieldErrors: {'quantity': 'Indica la cantidad.'}));
      return;
    }
    setState(() {
      _saving = next ? 'next' : 'saved';
      _error = null;
    });
    try {
      await context.session.api.post('/stock-movements', {
        'operation': widget.operation,
        'product_id': _p['id'],
        'branch_id': _branchId,
        'quantity': quantity,
        'reason': _reason,
        'product_batch_id': _batchId,
        if (_in) 'lot': _lot.text.trim().isEmpty ? null : _lot.text.trim(),
        if (_in) 'expires_at': _expires == null ? null : isoDate(_expires!),
        if (_in) 'unit_cost': _num(_cost),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (!mounted) return;
      final diff = quantity - _system();
      showDone(
        context,
        _count
            ? (diff == 0 ? '${_p.str('name')}: sin diferencias.' : '${_p.str('name')}: ajustado ${diff > 0 ? '+' : ''}${fmtNumber(diff)}.')
            : '${_titles[widget.operation]} registrada: ${_p.str('name')}.',
      );
      Navigator.of(context).pop(next ? 'next' : 'saved');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final unit = _p.str('unit') ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(_titles[widget.operation] ?? 'Movimiento')),
      body: Loader<Map<String, dynamic>>(
        load: () => context.session.api.get('/stock-movements/options'),
        builder: (context, options, reload) {
          final branches = options.list('branches');
          _branchId ??= branches.firstOrNull?['id'] as int?;
          final reasons = _in ? options.list('in_reasons') : options.list('out_reasons');
          final batches = _batches();
          final counted = _num(_quantity);
          final diff = counted == null ? null : counted - _system();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(_p.str('name') ?? '', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text([_p.str('presentation'), _p.str('brand'), _p.str('code')].whereType<String>().join(' · '), style: muted),
              const SizedBox(height: 16),
              if (_error != null && _error!.fieldErrors.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              if (branches.length > 1) ...[
                DropdownButtonFormField<int>(
                  initialValue: _branchId,
                  decoration: InputDecoration(labelText: 'Sucursal', errorText: _error?.field('branch_id')),
                  items: [for (final b in branches) DropdownMenuItem(value: b['id'] as int, child: Text(b.str('name') ?? ''))],
                  onChanged: (id) => setState(() {
                    _branchId = id;
                    _batchId = null;
                  }),
                ),
                const SizedBox(height: 16),
              ],
              // Con lotes: el conteo es por lote; la salida puede elegirlo (si no, sale el que vence primero).
              if (_tracked && !_in) ...[
                DropdownButtonFormField<int?>(
                  key: ValueKey('batch-$_branchId'),
                  initialValue: _batchId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _count ? 'Lote contado' : 'Lote (opcional)',
                    helperText: _count ? null : 'Si no eliges, sale el que vence primero.',
                    errorText: _error?.field('product_batch_id'),
                  ),
                  items: [
                    if (!_count) const DropdownMenuItem<int?>(value: null, child: Text('El que vence primero')),
                    for (final b in batches)
                      DropdownMenuItem<int?>(
                        value: b['id'] as int,
                        child: Text(
                          'Lote ${b.str('lot') ?? '—'} · vence ${fmtDate(b.date('expires_at'))} · ${fmtNumber(b.number('quantity'))}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) => setState(() => _batchId = id),
                ),
                if (_count && batches.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('No hay lotes con stock en esta sucursal.', style: muted),
                  ),
                const SizedBox(height: 16),
              ],
              if (_count && (!_tracked || _batchId != null))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Según el sistema: ${fmtNumber(_system())} $unit', style: muted),
                ),
              TextField(
                controller: _quantity,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: Theme.of(context).textTheme.headlineSmall,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _count ? 'Cantidad contada' : 'Cantidad',
                  suffixText: unit,
                  errorText: _error?.field('quantity'),
                ),
              ),
              if (_count && diff != null && (!_tracked || _batchId != null))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    diff == 0 ? 'Coincide con el sistema.' : 'Diferencia: ${diff > 0 ? '+' : ''}${fmtNumber(diff)} $unit',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: toneColor(context, diff == 0 ? 'success' : (diff < 0 ? 'danger' : 'warning')),
                    ),
                  ),
                ),
              if (!_count) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _reason,
                  decoration: InputDecoration(labelText: 'Motivo', errorText: _error?.field('reason')),
                  items: [for (final r in reasons) DropdownMenuItem(value: r.str('key'), child: Text(r.str('label') ?? ''))],
                  onChanged: (v) => setState(() => _reason = v),
                ),
              ],
              if (_in) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _lot,
                        decoration: InputDecoration(labelText: _tracked ? 'Lote' : 'Lote (opcional)', errorText: _error?.field('lot')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _expires ?? DateTime.now().add(const Duration(days: 365)),
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                          );
                          if (d != null) setState(() => _expires = d);
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(labelText: 'Vencimiento', errorText: _error?.field('expires_at')),
                          child: Text(_expires == null ? '—' : fmtDate(_expires)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _cost,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Costo unitario (opcional)', errorText: _error?.field('unit_cost')),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Nota (opcional)'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving == null ? () => _save() : null,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: _saving == 'saved'
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(_count ? 'Guardar conteo' : 'Registrar ${_titles[widget.operation]?.toLowerCase()}'),
              ),
              if (widget.chained) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _saving == null ? () => _save(next: true) : null,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  icon: _saving == 'next'
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.qr_code_scanner),
                  label: const Text('Guardar y escanear otro'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Kardex: entradas, salidas y ajustes con el saldo después de cada uno.
class MovementsScreen extends StatelessWidget {
  const MovementsScreen({super.key, required this.product});

  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Kardex · ${product.str('name') ?? ''}')),
      body: Loader<Map<String, dynamic>>(
        load: () => context.session.api.get('/products/${product['id']}/movements'),
        builder: (context, data, reload) {
          final items = data.list('data');
          if (items.isEmpty) {
            return ListView(
              children: const [EmptyState(icon: Icons.history, message: 'Sin movimientos todavía.')],
            );
          }
          final total = data.obj('meta')?.integer('total') ?? items.length;
          return ListView(
            children: [
              for (final m in items)
                ListTile(
                  leading: SizedBox(
                    width: 72,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: StatusChip(m.obj('type_badge')?.str('label') ?? '', tone: m.obj('type_badge')?.str('color')),
                    ),
                  ),
                  title: Text([m.str('reason'), if (m.str('lot') != null) 'lote ${m.str('lot')}'].whereType<String>().join(' · ')),
                  subtitle: Text(
                    [fmtDateTime(m.date('created_at')), m.str('branch'), m.str('user'), m.str('notes')].whereType<String>().join(' · '),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${(m.number('quantity') ?? 0) > 0 ? '+' : ''}${fmtNumber(m.number('quantity'))}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: toneColor(context, (m.number('quantity') ?? 0) >= 0 ? 'success' : 'danger'),
                        ),
                      ),
                      if (m.number('balance_after') != null)
                        Text('saldo ${fmtNumber(m.number('balance_after'))}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              if (total > items.length)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Los ${items.length} más recientes de $total. El kardex completo está en la web.',
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

class _ExpiringTab extends StatelessWidget {
  const _ExpiringTab();

  @override
  Widget build(BuildContext context) {
    return Loader<Map<String, dynamic>>(
      load: () => context.session.api.get('/products/expiring'),
      builder: (context, data, reload) {
        final expired = data.list('expired');
        final soon = data.list('expiring');
        if (expired.isEmpty && soon.isEmpty) {
          return ListView(
            children: [EmptyState(icon: Icons.event_available, message: 'Ningún lote vence en los próximos ${data.integer('days')} días.')],
          );
        }
        return ListView(
          children: [
            if (expired.isNotEmpty) ...[
              const SectionTitle('Vencidos con stock'),
              for (final b in expired) BatchTile(batch: b, showProduct: true),
            ],
            if (soon.isNotEmpty) ...[
              SectionTitle('Vencen en ${data.integer('days')} días'),
              for (final b in soon) BatchTile(batch: b, showProduct: true),
            ],
          ],
        );
      },
    );
  }
}

class BatchTile extends StatelessWidget {
  const BatchTile({super.key, required this.batch, this.showProduct = false});

  final Map<String, dynamic> batch;
  final bool showProduct;

  @override
  Widget build(BuildContext context) {
    final days = batch.integer('days_left');
    final tone = days == null ? null : (days < 0 ? 'danger' : (days <= 30 ? 'warning' : 'success'));
    final label = days == null
        ? 'Sin vencimiento'
        : days < 0
        ? 'Venció hace ${-days} d'
        : days == 0
        ? 'Vence hoy'
        : 'Vence en $days d';

    return ListTile(
      contentPadding: showProduct ? null : EdgeInsets.zero,
      title: Text(showProduct ? (batch.obj('product')?.str('name') ?? '') : 'Lote ${batch.str('lot') ?? '—'}'),
      subtitle: Text(
        [
          if (showProduct) 'Lote ${batch.str('lot') ?? '—'}',
          'Vence ${fmtDate(batch.date('expires_at'))}',
          '${fmtNumber(batch.number('quantity'))} u.',
          batch.str('branch'),
        ].whereType<String>().join(' · '),
      ),
      trailing: StatusChip(label, tone: tone),
    );
  }
}
