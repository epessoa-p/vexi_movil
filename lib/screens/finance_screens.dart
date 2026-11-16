import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'shell.dart';

/// Para el dueño (§17.13 y §17.9): el resumen económico del período y el
/// cobro de deudas (quién debe, cuánto y registrar abonos).

bool summaryVisible(Profile p) => p.canUse('estadisticas', 'reports.finance') && p.has('pos');

bool receivablesVisible(Profile p) => p.canUse('pos', 'sales.view');

// ── Piezas ──────────────────────────────────────────────────────────────────

/// «↑ 12 %» con el color de si es bueno o malo; «nuevo» cuando antes no había nada.
class DeltaChip extends StatelessWidget {
  const DeltaChip(this.delta, {super.key});

  final Map<String, dynamic>? delta;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    if (d == null) return const SizedBox.shrink();
    final pct = d.number('pct');
    final direction = d.str('direction');
    final color = toneColor(context, switch (d.str('tone')) {
      'good' => 'success',
      'bad' => 'danger',
      _ => null,
    });
    final (icon, label) = switch (direction) {
      'flat' => (Icons.drag_handle, 'igual'),
      _ when pct == null => (Icons.fiber_new_outlined, 'nuevo'),
      'up' => (Icons.arrow_upward, '${fmtNumber(pct.abs())} %'),
      _ => (Icons.arrow_downward, '${fmtNumber(pct.abs())} %'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, this.delta, this.tone});

  final String label;
  final String value;
  final Map<String, dynamic>? delta;
  final String? tone;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: tone == null ? null : toneColor(context, tone)),
              ),
            ),
            const SizedBox(height: 6),
            delta == null ? const SizedBox(height: 22) : DeltaChip(delta),
          ],
        ),
      ),
    );
  }
}

/// Dos tarjetas por fila, del mismo alto.
class _KpiGrid extends StatelessWidget {
  const _KpiGrid(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i += 2)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: children[i]),
                    const SizedBox(width: 8),
                    Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox.shrink()),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Barras de ingresos por día o por mes. Mantener pulsado muestra el importe.
class _IncomeChart extends StatelessWidget {
  const _IncomeChart({required this.labels, required this.values});

  final List<String> labels;
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = values.fold<double>(0, math.max);
    final small = Theme.of(context).textTheme.bodySmall;
    final gap = values.length > 20 ? 2.0 : 4.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Máximo ${money(context, top)}', style: small),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Tooltip(
                    message: '${labels[i]}: ${money(context, values[i])}',
                    triggerMode: TooltipTriggerMode.tap,
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: gap / 2),
                      height: top <= 0 ? 2 : math.max(2, values[i] / top * 120),
                      decoration: BoxDecoration(
                        color: values[i] > 0 ? scheme.primary : scheme.outlineVariant,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        if (labels.isNotEmpty)
          Row(
            children: [
              Text(labels.first, style: small),
              const Spacer(),
              if (labels.length > 2) Text(labels[labels.length ~/ 2], style: small),
              const Spacer(),
              Text(labels.last, style: small),
            ],
          ),
      ],
    );
  }
}

/// Filas con su barra proporcional: lo más vendido, métodos de pago, gastos.
class _ShareList extends StatelessWidget {
  const _ShareList(this.rows, {this.withQuantity = false});

  final List<Map<String, dynamic>> rows;
  final bool withQuantity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = rows.map((r) => r.number('value') ?? 0).fold<double>(0, math.max);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(r.str('label') ?? '', maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Text(money(context, r.number('value')), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: top <= 0 ? 0 : (r.number('value') ?? 0) / top,
                              minHeight: 6,
                              backgroundColor: scheme.surfaceContainerHighest,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 92,
                          child: Text(
                            [
                              '${fmtNumber(r.number('share')?.round())} %',
                              if (withQuantity && r.number('quantity') != null) '${fmtNumber(r.number('quantity'))} u.',
                            ].join(' · '),
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.bodySmall,
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
}

IconData _insightIcon(String? key) => switch (key) {
  'graph-up-arrow' => Icons.trending_up,
  'graph-down-arrow' => Icons.trending_down,
  'dash-lg' => Icons.trending_flat,
  'exclamation-triangle' => Icons.warning_amber_rounded,
  'piggy-bank' => Icons.savings_outlined,
  'trophy' => Icons.emoji_events_outlined,
  'receipt' => Icons.receipt_long_outlined,
  'clipboard2-pulse' => Icons.monitor_heart_outlined,
  'hourglass' => Icons.hourglass_empty,
  _ => Icons.payments_outlined,
};

// ── Resumen económico ───────────────────────────────────────────────────────

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  String _preset = 'this_month';
  int? _branchId;
  List<Map<String, dynamic>> _branches = const [];

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;

    return Scaffold(
      appBar: AppBar(
        leading: shellMenuButton(context),
        title: const Text('Resumen económico'),
        actions: [
          if (_branches.isNotEmpty)
            PopupMenuButton<int?>(
              tooltip: 'Sucursal',
              icon: const Icon(Icons.store_outlined),
              initialValue: _branchId,
              onSelected: (id) => setState(() => _branchId = id),
              itemBuilder: (_) => [
                const PopupMenuItem<int?>(value: null, child: Text('Todas las sucursales')),
                for (final b in _branches) PopupMenuItem<int?>(value: b['id'] as int, child: Text(b.str('name') ?? '')),
              ],
            ),
        ],
      ),
      body: Loader<Map<String, dynamic>>(
        key: ValueKey('$_preset-$_branchId'),
        load: () async {
          final data = await context.session.api.get('/reports/summary', query: {'preset': _preset, 'branch_id': _branchId?.toString()});
          final branches = data.list('branches');
          if (mounted && branches.length != _branches.length) setState(() => _branches = branches);
          return data;
        },
        builder: (context, data, reload) => _SummaryBody(
          data: data,
          profile: profile,
          preset: _preset,
          branchName: _branches.where((b) => b['id'] == _branchId).firstOrNull?.str('name'),
          onPreset: (p) => setState(() => _preset = p),
        ),
      ),
    );
  }
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({required this.data, required this.profile, required this.preset, required this.onPreset, this.branchName});

  final Map<String, dynamic> data;
  final Profile profile;
  final String preset;
  final String? branchName;
  final ValueChanged<String> onPreset;

  @override
  Widget build(BuildContext context) {
    final period = data.obj('period') ?? const {};
    final totals = data.obj('totals') ?? const {};
    final deltas = data.obj('deltas') ?? const {};
    final sales = data.obj('sales') ?? const {};
    final salesDeltas = sales.obj('deltas') ?? const {};
    final clinic = data.obj('clinic');
    final chart = data.obj('chart') ?? const {};
    final withExpenses = data.flag('with_expenses');
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final profit = totals.number('profit') ?? 0;
    final receivable = data.number('receivable') ?? 0;
    final overdue = data.number('receivable_overdue') ?? 0;
    final insights = data.list('insights');
    final previous = period.str('previous_label');

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              for (final p in data.list('presets'))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(p.str('label') ?? ''),
                    selected: preset == p.str('key'),
                    onSelected: (_) => onPreset(p.str('key')!),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            [period.str('label'), ?branchName, if (previous != null) 'comparado con $previous'].whereType<String>().join(' · '),
            style: muted,
          ),
        ),
        if (insights.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .5),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (final i in insights)
                      ListTile(
                        dense: true,
                        leading: Icon(_insightIcon(i.str('icon')), color: Theme.of(context).colorScheme.primary),
                        title: Text(i.str('text') ?? '', style: Theme.of(context).textTheme.bodyMedium),
                      ),
                  ],
                ),
              ),
            ),
          ),
        const SectionTitle('Dinero'),
        _KpiGrid([
          _Kpi(label: 'Ingresos', value: money(context, totals.number('income')), delta: deltas.obj('income')),
          _Kpi(label: 'Utilidad estimada', value: money(context, profit), delta: deltas.obj('profit'), tone: profit < 0 ? 'danger' : null),
          _Kpi(label: 'Costo de lo vendido', value: money(context, totals.number('cost')), delta: deltas.obj('cost')),
          if (withExpenses) _Kpi(label: 'Gastos', value: money(context, totals.number('expenses')), delta: deltas.obj('expenses')),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _IncomeChart(
                labels: [for (final l in (chart['labels'] as List? ?? const [])) '$l'],
                values: [for (final v in (chart['income'] as List? ?? const [])) (v as num).toDouble()],
              ),
            ),
          ),
        ),
        const SectionTitle('Ventas'),
        _KpiGrid([
          _Kpi(label: 'Vendido', value: money(context, sales.number('total')), delta: salesDeltas.obj('total')),
          _Kpi(label: 'Ventas', value: fmtNumber(sales.number('count')), delta: salesDeltas.obj('count')),
          _Kpi(label: 'Ticket promedio', value: money(context, sales.number('ticket')), delta: salesDeltas.obj('ticket')),
          if (clinic != null) _Kpi(label: 'Consultas', value: fmtNumber(clinic.number('count')), delta: clinic.obj('deltas')?.obj('count')),
        ]),
        if (clinic != null) ...[
          const SizedBox(height: 8),
          _KpiGrid([
            _Kpi(label: 'Pacientes atendidos', value: fmtNumber(clinic.number('patients')), delta: clinic.obj('deltas')?.obj('patients')),
            _Kpi(label: 'Vacunas aplicadas', value: fmtNumber(clinic.number('vaccines')), delta: clinic.obj('deltas')?.obj('vaccines')),
          ]),
        ],
        if (sales.list('top').isNotEmpty) ...[
          const SectionTitle('Lo más vendido'),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _ShareList(sales.list('top'), withQuantity: true)),
        ],
        if (data.list('by_method').isNotEmpty) ...[
          const SectionTitle('Cómo te pagaron'),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _ShareList(data.list('by_method'))),
        ],
        if (withExpenses && data.list('expenses_by_category').isNotEmpty) ...[
          const SectionTitle('En qué se gastó'),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _ShareList(data.list('expenses_by_category'))),
        ],
        const SectionTitle('Cuentas'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.request_quote_outlined, color: receivable > 0 ? toneColor(context, 'warning') : null),
                  title: const Text('Te deben'),
                  subtitle: overdue > 0
                      ? Text('${money(context, overdue)} vencido', style: TextStyle(color: toneColor(context, 'danger')))
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        money(context, receivable),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (receivablesVisible(profile)) const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: receivablesVisible(profile) ? () => openSection(context, Section.receivables) : null,
                ),
                if (data.number('payable') != null)
                  ListTile(
                    leading: const Icon(Icons.local_shipping_outlined),
                    title: const Text('Debes a proveedores'),
                    trailing: Text(
                      money(context, data.number('payable')),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Text(
            'Ingresos: lo cobrado menos lo devuelto. Utilidad: ingresos menos el costo de lo vendido y los gastos. '
            'Los reportes detallados y el Excel están en la web.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

// ── Cuentas por cobrar ──────────────────────────────────────────────────────

class ReceivablesScreen extends StatefulWidget {
  const ReceivablesScreen({super.key});

  @override
  State<ReceivablesScreen> createState() => _ReceivablesScreenState();
}

class _ReceivablesScreenState extends State<ReceivablesScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  String _term = '';
  bool _overdue = false;
  int _version = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _open(Map<String, dynamic> client) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientDebtScreen(clientId: client['id'] as int, name: client.str('name')),
      ),
    );
    if (mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: shellMenuButton(context),
          title: const Text('Cuentas por cobrar'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Deudores'),
              Tab(text: 'Cobros recientes'),
            ],
          ),
        ),
        body: Loader<Map<String, dynamic>>(
          key: ValueKey('$_term-$_overdue-$_version'),
          load: () => context.session.api.get('/receivables', query: {'q': _term, 'overdue': _overdue ? '1' : null}),
          builder: (context, data, reload) => TabBarView(
            children: [
              ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _pair([
                      _Kpi(label: 'Te deben', value: money(context, data.number('total')), tone: 'warning'),
                      _Kpi(
                        label: 'Vencido',
                        value: money(context, data.number('overdue_total')),
                        tone: (data.number('overdue_total') ?? 0) > 0 ? 'danger' : null,
                      ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: SearchBar(
                      controller: _query,
                      hintText: 'Buscar cliente',
                      leading: const Icon(Icons.search),
                      elevation: const WidgetStatePropertyAll(0),
                      onChanged: (v) {
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _term = v.trim()));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FilterChip(
                        label: const Text('Solo vencidas'),
                        selected: _overdue,
                        onSelected: (v) => setState(() => _overdue = v),
                      ),
                    ),
                  ),
                  if (data.list('data').isEmpty)
                    EmptyState(
                      icon: Icons.verified_outlined,
                      message: _term.isNotEmpty || _overdue
                          ? 'Nadie debe con ese filtro.'
                          : 'Nadie te debe. ¡Todas las cuentas están al día!',
                    )
                  else
                    for (final d in data.list('data')) _DebtorTile(debtor: d, onTap: () => _open(d.obj('client')!)),
                ],
              ),
              _Collections(items: data.list('collections')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dos tarjetas lado a lado, del mismo alto.
Widget _pair(List<Widget> children) => IntrinsicHeight(
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: children[0]),
      const SizedBox(width: 8),
      Expanded(child: children[1]),
    ],
  ),
);

class _DebtorTile extends StatelessWidget {
  const _DebtorTile({required this.debtor, required this.onTap});

  final Map<String, dynamic> debtor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final client = debtor.obj('client') ?? const {};
    final overdue = debtor.number('overdue_balance') ?? 0;
    final count = debtor.integer('sales_count') ?? 0;
    final reminder = debtor.str('whatsapp_reminder');

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: toneColor(context, overdue > 0 ? 'danger' : 'warning').withValues(alpha: .14),
        child: Text(
          (client.str('name') ?? '?').characters.first.toUpperCase(),
          style: TextStyle(color: toneColor(context, overdue > 0 ? 'danger' : 'warning'), fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(client.str('name') ?? 'Sin cliente'),
      subtitle: Text(
        [
          count == 1 ? '1 venta' : '$count ventas',
          'desde ${fmtShortDate(debtor.date('oldest'))}',
          if (overdue > 0) '${money(context, overdue)} vencido',
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            money(context, debtor.number('balance')),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: overdue > 0 ? toneColor(context, 'danger') : null),
          ),
          if (reminder != null)
            IconButton(
              tooltip: 'Recordar por WhatsApp',
              icon: Icon(Icons.chat_outlined, color: toneColor(context, 'success')),
              onPressed: () => openExternal(context, reminder),
            ),
        ],
      ),
    );
  }
}

class _Collections extends StatelessWidget {
  const _Collections({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ListView(
        children: const [EmptyState(icon: Icons.payments_outlined, message: 'Todavía no hay abonos registrados.')],
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final p in items)
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.south_west, size: 20)),
            title: Text(p.obj('client')?.str('name') ?? 'Sin cliente'),
            subtitle: Text(
              [fmtDateTime(p.date('paid_at')), p.str('method'), p.str('sale_code'), p.str('user')].whereType<String>().join(' · '),
            ),
            trailing: Text(
              '+${money(context, p.number('amount'))}',
              style: TextStyle(fontWeight: FontWeight.w700, color: toneColor(context, 'success')),
            ),
          ),
      ],
    );
  }
}

// ── Lo que debe un cliente ──────────────────────────────────────────────────

class ClientDebtScreen extends StatefulWidget {
  const ClientDebtScreen({super.key, required this.clientId, this.name});

  final int clientId;
  final String? name;

  @override
  State<ClientDebtScreen> createState() => _ClientDebtScreenState();
}

class _ClientDebtScreenState extends State<ClientDebtScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();

  Future<void> _pay(Map<String, dynamic> sale, String? clientName) async {
    final paid = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PaymentScreen(sale: sale, clientName: clientName),
      ),
    );
    if (paid == true) _loader.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final canPay = profile.can('sales.create');

    return Scaffold(
      appBar: AppBar(title: Text(widget.name ?? 'Cuenta del cliente')),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => context.session.api.get('/clients/${widget.clientId}/receivables'),
        builder: (context, data, reload) {
          final sales = data.list('sales');
          final overdue = data.number('overdue_balance') ?? 0;
          final reminder = data.str('whatsapp_reminder');
          final client = data.obj('client') ?? const {};

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Card(
                color: toneColor(context, overdue > 0 ? 'danger' : 'warning').withValues(alpha: .1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Saldo pendiente', style: Theme.of(context).textTheme.bodySmall),
                      Text(
                        money(context, data.number('balance')),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (overdue > 0)
                        Text(
                          '${money(context, overdue)} vencido',
                          style: TextStyle(color: toneColor(context, 'danger'), fontWeight: FontWeight.w600),
                        ),
                      if (reminder != null || client.str('phone') != null) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (reminder != null)
                              FilledButton.tonalIcon(
                                onPressed: () => openExternal(context, reminder),
                                icon: const Icon(Icons.chat_outlined),
                                label: const Text('Recordar por WhatsApp'),
                              ),
                            if (client.str('phone') != null)
                              OutlinedButton.icon(
                                onPressed: () => openExternal(context, 'tel:${client.str('phone')}'),
                                icon: const Icon(Icons.call_outlined),
                                label: const Text('Llamar'),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (sales.isEmpty)
                const EmptyState(icon: Icons.verified_outlined, message: 'Este cliente no debe nada.')
              else ...[
                SectionTitle(sales.length == 1 ? '1 venta con saldo' : '${sales.length} ventas con saldo'),
                for (final s in sales)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _SaleDebtCard(sale: s, onPay: canPay ? () => _pay(s, client.str('name')) : null),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SaleDebtCard extends StatelessWidget {
  const _SaleDebtCard({required this.sale, this.onPay});

  final Map<String, dynamic> sale;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final due = sale.date('due_date');
    final items = sale.list('items');
    final payments = sale.list('payments');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    [sale.str('code'), fmtShortDate(sale.date('created_at')), sale.str('pet')].whereType<String>().join(' · '),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (sale.flag('overdue'))
                  const StatusChip('Vencida', tone: 'danger')
                else if (due != null)
                  StatusChip('Vence ${fmtShortDate(due)}', tone: 'warning'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              items
                  .map(
                    (i) => (i.number('quantity') ?? 1) == 1
                        ? i.str('description')
                        : '${i.str('description')} ×${fmtNumber(i.number('quantity'))}',
                  )
                  .join(' · '),
              style: muted,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Fact('Total', money(context, sale.number('total')))),
                Expanded(child: Fact('Pagado', money(context, sale.number('paid')))),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Saldo', style: Theme.of(context).textTheme.bodySmall),
                      Text(
                        money(context, sale.number('balance')),
                        style: TextStyle(fontWeight: FontWeight.w800, color: toneColor(context, 'danger')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (payments.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final p in payments)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    [
                      fmtShortDate(p.date('paid_at')),
                      p.str('method'),
                      p.str('kind') == 'installment' ? 'abono' : 'al vender',
                      money(context, p.number('amount')),
                    ].whereType<String>().join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
            if (onPay != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(onPressed: onPay, icon: const Icon(Icons.add_card), label: const Text('Registrar abono')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Registrar un abono ──────────────────────────────────────────────────────

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.sale, this.clientName});

  final Map<String, dynamic> sale;
  final String? clientName;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late final _amount = TextEditingController(text: _plain(widget.sale.number('balance') ?? 0));
  final _reference = TextEditingController();
  int? _methodId;
  int? _sessionId;
  bool _saving = false;
  ApiException? _error;

  double get _balance => widget.sale.number('balance') ?? 0;

  /// 300 → «300»; 150.5 → «150.50»: lo que se escribe en el campo.
  static String _plain(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save(Map<String, dynamic> options) async {
    final amount = num.tryParse(_amount.text.replaceAll(',', '.').trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = ApiException(422, 'Indica el monto.', fieldErrors: {'amount': 'Indica el monto del abono.'}));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await context.session.api.post('/sales/${widget.sale['id']}/payments', {
        'amount': amount,
        'payment_method_id': _methodId,
        'reference': _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        if (options.flag('cash_enabled')) 'cash_session_id': _sessionId,
      });
      if (!mounted) return;
      setState(() => _saving = false);
      await _done(result);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Confirmación con el saldo que queda y el recibo por WhatsApp.
  Future<void> _done(Map<String, dynamic> result) async {
    final receipt = result.str('whatsapp_receipt');
    final left = result.number('client_balance') ?? 0;
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        icon: Icon(Icons.check_circle, color: toneColor(dialog, 'success'), size: 40),
        title: Text('Abono de ${money(dialog, result.number('amount'))} registrado'),
        content: Text(
          left > 0
              ? '${widget.clientName ?? 'El cliente'} todavía debe ${money(dialog, left)}.'
              : '${widget.clientName ?? 'El cliente'} quedó al día.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(), child: const Text('Listo')),
          if (receipt != null)
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialog).pop();
                openExternal(context, receipt);
              },
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Enviar recibo'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sale;

    return Scaffold(
      appBar: AppBar(title: const Text('Registrar abono')),
      body: Loader<Map<String, dynamic>>(
        load: () => context.session.api.get('/payments/options'),
        builder: (context, options, reload) {
          final methods = options.list('methods');
          final sessions = options.list('sessions');
          final cash = options.flag('cash_enabled');
          _methodId ??= methods.firstOrNull?['id'] as int?;
          _sessionId ??= sessions.firstOrNull?['id'] as int?;
          final method = methods.where((m) => m['id'] == _methodId).firstOrNull;
          final needsReference = method?.flag('requires_reference') ?? false;
          final noCash = cash && sessions.isEmpty;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                [widget.clientName, s.str('code')].whereType<String>().join(' · '),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                'Saldo de esta venta: ${money(context, _balance)}',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              if (_error != null && _error!.fieldErrors.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              if (noCash)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Card(
                    color: toneColor(context, 'warning').withValues(alpha: .12),
                    child: const ListTile(
                      leading: Icon(Icons.point_of_sale),
                      title: Text('No hay ninguna caja abierta'),
                      subtitle: Text('Abre una caja desde la web para registrar cobros.'),
                    ),
                  ),
                ),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: Theme.of(context).textTheme.headlineSmall,
                decoration: InputDecoration(
                  labelText: 'Monto',
                  prefixText: '${context.read<Session>().profile?.company?.currencySymbol ?? ''} ',
                  errorText: _error?.field('amount'),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(label: const Text('Todo el saldo'), onPressed: () => setState(() => _amount.text = _plain(_balance))),
                  ActionChip(
                    label: const Text('La mitad'),
                    onPressed: () => setState(() => _amount.text = _plain((_balance / 2 * 100).round() / 100)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Método de pago', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in methods)
                    ChoiceChip(
                      label: Text(m.str('name') ?? ''),
                      selected: _methodId == m['id'],
                      onSelected: (_) => setState(() => _methodId = m['id'] as int),
                    ),
                ],
              ),
              if (_error?.field('payment_method_id') != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_error!.field('payment_method_id')!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _reference,
                decoration: InputDecoration(
                  labelText: needsReference ? 'Número de referencia' : 'Referencia (opcional)',
                  errorText: _error?.field('reference'),
                ),
              ),
              if (cash && sessions.length > 1) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _sessionId,
                  decoration: InputDecoration(labelText: 'Caja', errorText: _error?.field('cash_session_id')),
                  items: [for (final c in sessions) DropdownMenuItem(value: c['id'] as int, child: Text(c.str('name') ?? ''))],
                  onChanged: (id) => setState(() => _sessionId = id),
                ),
              ] else if (cash && sessions.length == 1)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Se registra en ${sessions.first.str('name')}.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              if (_error?.field('cash_session_id') != null && sessions.length <= 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_error!.field('cash_session_id')!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving || noCash || _methodId == null ? null : () => _save(options),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: _saving
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('Registrar abono'),
              ),
            ],
          );
        },
      ),
    );
  }
}
