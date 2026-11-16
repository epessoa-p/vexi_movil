import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'agenda_screens.dart';
import 'finance_screens.dart';
import 'notifications_screen.dart';
import 'shell.dart';

/// Inicio (§17.1): saludo, resumen del día, lo que requiere atención y las
/// próximas citas. Todo en una pantalla que se lee de un vistazo.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;

    return Scaffold(
      appBar: AppBar(
        leading: shellMenuButton(context),
        title: Text(profile.company?.name ?? 'Vexi'),
        actions: [_BellButton(onReturn: () => _loader.currentState?.reload())],
      ),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => context.session.api.get('/home'),
        builder: (context, data, reload) => _HomeBody(data: data, profile: profile, reload: reload),
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({required this.onReturn});

  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Notificaciones',
      icon: const Icon(Icons.notifications_outlined),
      onPressed: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
        onReturn();
      },
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.data, required this.profile, required this.reload});

  final Map<String, dynamic> data;
  final Profile profile;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final today = data.obj('today');
    final alerts = data.list('alerts');
    final unread = data.integer('unread_notifications') ?? 0;
    final hospitalized = data.integer('hospitalized');
    final finance = data.obj('finance');
    // «Dra. Paula Rojas» → «Paula»: se saltan los títulos abreviados.
    final firstName = profile.name.split(' ').firstWhere((w) => w.isNotEmpty && !w.endsWith('.'), orElse: () => profile.name);
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${data.str('greeting')}, $firstName', style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(fmtDayLong(DateTime.now()), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        if (today != null || hospitalized != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                if (today != null) ...[
                  _Tile(value: today.integer('total') ?? 0, label: 'Citas hoy', icon: Icons.event),
                  const SizedBox(width: 8),
                  _Tile(value: today.integer('waiting') ?? 0, label: 'En espera', icon: Icons.chair_outlined, tone: 'warning'),
                  const SizedBox(width: 8),
                ],
                if (hospitalized != null)
                  _Tile(value: hospitalized, label: 'Internados', icon: Icons.local_hospital_outlined, tone: 'info'),
              ],
            ),
          ),
        if (finance != null) _FinanceCard(finance: finance, profile: profile),
        if (unread > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: Text(unread == 1 ? 'Tienes 1 novedad sin leer' : 'Tienes $unread novedades sin leer'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                  reload();
                },
              ),
            ),
          ),
        SectionTitle('Requiere atención'),
        if (alerts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: ListTile(
                leading: Icon(Icons.check_circle_outline, color: Colors.green),
                title: Text('Nada pendiente por atender'),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [for (final a in alerts) AlertTile(alert: a)]),
            ),
          ),
        if (today != null) ...[
          SectionTitle(
            'Próximas citas',
            trailing: TextButton(onPressed: () => openSection(context, Section.agenda), child: const Text('Ver agenda')),
          ),
          if (today.list('next').isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: ListTile(leading: Icon(Icons.event_available), title: Text('No hay más citas pendientes hoy')),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [for (final a in today.list('next')) AppointmentTile(appointment: a, onChanged: reload)],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Para el dueño: lo que entró hoy y en el mes, y lo que le deben.
class _FinanceCard extends StatelessWidget {
  const _FinanceCard({required this.finance, required this.profile});

  final Map<String, dynamic> finance;
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final receivable = finance.number('receivable') ?? 0;
    final overdue = finance.number('receivable_overdue') ?? 0;
    final sales = finance.integer('sales_today') ?? 0;
    final report = finance.flag('report') && summaryVisible(profile);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            InkWell(
              onTap: report ? () => openSection(context, Section.summary) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cobrado hoy', style: small),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              money(context, finance.number('today')),
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(sales == 1 ? '1 venta hoy' : '$sales ventas hoy', style: small),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Este mes', style: small),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              money(context, finance.number('month')),
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          DeltaChip(finance.obj('month_delta')),
                        ],
                      ),
                    ),
                    if (report) const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
            if (receivable > 0) ...[
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: Icon(Icons.request_quote_outlined, color: toneColor(context, overdue > 0 ? 'danger' : 'warning')),
                title: Text('Te deben ${money(context, receivable)}'),
                subtitle: overdue > 0 ? Text('${money(context, overdue)} vencido') : null,
                trailing: receivablesVisible(profile) ? const Icon(Icons.chevron_right) : null,
                onTap: receivablesVisible(profile) ? () => openSection(context, Section.receivables) : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label, required this.icon, this.tone});

  final int value;
  final String label;
  final IconData icon;
  final String? tone;

  @override
  Widget build(BuildContext context) {
    final color = tone == null ? Theme.of(context).colorScheme.primary : toneColor(context, tone);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 8),
              Text('$value', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una alerta de «requiere atención». Al tocarla lleva a la sección que la resuelve.
class AlertTile extends StatelessWidget {
  const AlertTile({super.key, required this.alert});

  final Map<String, dynamic> alert;

  static Section? sectionFor(String? key) => switch (key) {
    'waiting' || 'next_mine' || 'unconfirmed' => Section.agenda,
    'doses' => Section.hospital,
    'vaccines' => Section.vaccines,
    'out' || 'low' || 'expired' || 'expiring' => Section.inventory,
    _ => null,
  };

  static IconData iconFor(String? key) => switch (key) {
    'waiting' => Icons.chair_outlined,
    'next_mine' => Icons.schedule,
    'unconfirmed' => Icons.phone_in_talk_outlined,
    'reviews' => Icons.replay,
    'doses' => Icons.medication_outlined,
    'vaccines' => Icons.vaccines_outlined,
    'out' => Icons.remove_shopping_cart_outlined,
    'expired' => Icons.event_busy,
    'low' => Icons.trending_down,
    'expiring' => Icons.hourglass_bottom,
    _ => Icons.info_outline,
  };

  @override
  Widget build(BuildContext context) {
    final tone = alert.str('tone');
    final color = toneColor(context, tone);
    final section = sectionFor(alert.str('key'));
    final profile = context.read<Session>().profile!;
    final reachable = section != null && section.allowedFor(profile);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: .14),
        child: Icon(iconFor(alert.str('key')), color: color, size: 20),
      ),
      title: Text(alert.str('title') ?? ''),
      subtitle: alert.str('hint') == null ? null : Text(alert.str('hint')!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
            child: Text(
              '${alert.integer('count')}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          if (reachable) const Icon(Icons.chevron_right),
        ],
      ),
      onTap: reachable ? () => openSection(context, section) : null,
    );
  }
}
