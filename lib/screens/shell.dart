import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import '../ui/sections.dart';
import 'agenda_screens.dart';
import 'consultation_screens.dart';
import 'finance_screens.dart';
import 'home_screen.dart';
import 'hospital_screens.dart';
import 'inventory_screens.dart';
import 'lab_screens.dart';
import 'notifications_screen.dart';
import 'pet_screens.dart';
import 'profile_screen.dart';
import 'reception_screens.dart';
import 'vaccine_screens.dart';

/// Secciones de la app. Cada una sabe si el usuario puede usarla, con las
/// mismas reglas de plan + permiso que la web.
enum Section {
  home('Inicio', Icons.home_outlined, Icons.home),
  agenda('Agenda', Icons.calendar_month_outlined, Icons.calendar_month),
  waiting('Sala de espera', Icons.weekend_outlined, Icons.weekend),
  patients('Pacientes', Icons.pets_outlined, Icons.pets),
  clients('Propietarios', Icons.people_outline, Icons.people),
  consultations('Consultas', Icons.medical_services_outlined, Icons.medical_services),
  vaccines('Vacunación', Icons.vaccines_outlined, Icons.vaccines),
  hospital('Hospitalización', Icons.local_hospital_outlined, Icons.local_hospital),
  lab('Laboratorio', Icons.biotech_outlined, Icons.biotech),
  inventory('Inventario', Icons.inventory_2_outlined, Icons.inventory_2),
  summary('Resumen económico', Icons.insights_outlined, Icons.insights),
  receivables('Cuentas por cobrar', Icons.request_quote_outlined, Icons.request_quote),
  notifications('Notificaciones', Icons.notifications_outlined, Icons.notifications),
  profile('Mi perfil', Icons.person_outline, Icons.person);

  const Section(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  bool allowedFor(Profile p) => switch (this) {
    Section.agenda => p.canUse('agenda', 'appointments.view'),
    Section.waiting => p.canUse('agenda', 'appointments.view'),
    Section.patients => p.can('pets.view'),
    Section.clients => p.can('clients.view'),
    Section.consultations => p.canUse('consultas', 'consultations.view'),
    Section.vaccines => p.canUse('vacunas', 'vaccinations.view'),
    Section.hospital => p.canUse('hospitalizacion', 'hospitalizations.view'),
    Section.lab => labVisible(p),
    Section.inventory => p.canUse('inventario', 'products.view'),
    Section.summary => summaryVisible(p),
    Section.receivables => receivablesVisible(p),
    _ => true,
  };

  Widget screen() => switch (this) {
    Section.home => const HomeScreen(),
    Section.agenda => const AgendaScreen(),
    Section.waiting => const WaitingRoomScreen(),
    Section.patients => const PetSearchScreen(),
    Section.clients => const ClientSearchScreen(),
    Section.consultations => const ConsultationsScreen(),
    Section.vaccines => const VaccinesScreen(),
    Section.hospital => const HospitalScreen(),
    Section.lab => const LabScreen(),
    Section.inventory => const InventoryScreen(),
    Section.summary => const SummaryScreen(),
    Section.receivables => const ReceivablesScreen(),
    Section.notifications => const NotificationsScreen(),
    Section.profile => const ProfileScreen(),
  };
}

/// Grupos del drawer, en el orden en que se muestran: las mismas secciones y
/// colores que el menú de la web (Reportes va en Principal; Agenda, pacientes
/// y propietarios, en Clínica).
const _groups = <(NavGroup, List<Section>)>[
  (NavGroup.principal, [Section.home, Section.summary]),
  (
    NavGroup.clinica,
    [
      Section.agenda,
      Section.waiting,
      Section.patients,
      Section.clients,
      Section.consultations,
      Section.vaccines,
      Section.hospital,
      Section.lab,
    ],
  ),
  (NavGroup.ventas, [Section.receivables]),
  (NavGroup.inventario, [Section.inventory]),
  (NavGroup.cuenta, [Section.notifications, Section.profile]),
];

/// La sección del menú (y su color) a la que pertenece cada pantalla.
NavGroup groupOf(Section section) => _groups.firstWhere((g) => g.$2.contains(section)).$1;

/// Las de la barra inferior; el resto se abre desde el drawer.
const _bottom = [Section.home, Section.agenda, Section.patients];

/// Lleva a una sección: dentro del shell la cambia; fuera, la abre encima.
void openSection(BuildContext context, Section section) {
  final shell = context.findAncestorStateOfType<AppShellState>();
  if (shell != null && shell.sections.contains(section)) {
    shell.select(section);
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => section.screen()));
}

/// Botón ☰ para las pantallas raíz. Devuelve null fuera del shell, así una
/// pantalla abierta encima conserva su flecha de volver.
Widget? shellMenuButton(BuildContext context) {
  final shell = context.findAncestorStateOfType<AppShellState>();
  if (shell == null) return null;
  return IconButton(tooltip: 'Menú', icon: const Icon(Icons.menu), onPressed: shell.openDrawer);
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  final _scaffold = GlobalKey<ScaffoldState>();

  late final List<Section> sections;
  late final List<Section> tabs;
  Section _current = Section.home;

  /// Secciones ya abiertas: se construyen al visitarlas por primera vez.
  final _visited = <Section>{Section.home};

  @override
  void initState() {
    super.initState();
    final profile = context.read<Session>().profile!;
    sections = Section.values.where((s) => s.allowedFor(profile)).toList();
    tabs = _bottom.where(sections.contains).toList();
  }

  void openDrawer() => _scaffold.currentState?.openDrawer();

  void select(Section section) => setState(() {
    _current = section;
    _visited.add(section);
  });

  @override
  Widget build(BuildContext context) {
    final inTabs = tabs.indexOf(_current);

    return Scaffold(
      key: _scaffold,
      drawer: AppDrawer(
        sections: sections,
        current: _current,
        onSelect: (s) {
          Navigator.of(context).pop();
          select(s);
        },
      ),
      body: IndexedStack(
        index: sections.indexOf(_current),
        children: [for (final s in sections) _visited.contains(s) ? s.screen() : const SizedBox.shrink()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: inTabs >= 0 ? inTabs : tabs.length,
        onDestinationSelected: (i) => i < tabs.length ? select(tabs[i]) : openDrawer(),
        // El indicador toma el color de la sección actual, como en el drawer y la web.
        indicatorColor: groupOf(_current).soft(context, .18),
        destinations: [
          for (final s in tabs)
            NavigationDestination(
              icon: Icon(s.icon),
              selectedIcon: Icon(s.selectedIcon, color: groupOf(s).ink(context)),
              label: s.label,
            ),
          NavigationDestination(
            icon: const Icon(Icons.menu),
            selectedIcon: Icon(_current.selectedIcon, color: groupOf(_current).ink(context)),
            label: inTabs >= 0 ? 'Menú' : _current.label,
          ),
        ],
      ),
    );
  }
}

/// Menú lateral: todas las secciones permitidas, agrupadas, con la persona y
/// la veterinaria arriba y el cierre de sesión al final.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.sections, required this.current, required this.onSelect});

  final List<Section> sections;
  final Section current;
  final ValueChanged<Section> onSelect;

  Future<void> _switchCompany(BuildContext context) async {
    final session = context.read<Session>();
    Navigator.of(context).pop();
    final chosen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Cambiar de veterinaria', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final c in session.profile!.companies)
              ListTile(
                leading: const Icon(Icons.local_hospital_outlined),
                title: Text(c.name),
                trailing: c.id == session.profile!.company?.id ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, c.id),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && chosen != session.profile!.company?.id) {
      try {
        await session.chooseCompany(chosen);
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    final session = context.read<Session>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text('Tendrás que volver a ingresar tu correo y contraseña.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cerrar sesión')),
        ],
      ),
    );
    if (ok == true) await session.logout();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final scheme = Theme.of(context).colorScheme;

    return NavigationDrawer(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: scheme.primary,
                child: Text(
                  profile.name.isEmpty ? '?' : profile.name[0].toUpperCase(),
                  style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                profile.name,
                style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
              ),
              Text(profile.email, style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer)),
              const SizedBox(height: 10),
              InkWell(
                onTap: profile.companies.length > 1 ? () => _switchCompany(context) : null,
                child: Row(
                  children: [
                    CompanyLogo(url: profile.company?.logoUrl, size: 30),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        [profile.company?.name, if (profile.planName != null) 'Plan ${profile.planName}'].whereType<String>().join(' · '),
                        style: TextStyle(fontSize: 13, color: scheme.onPrimaryContainer),
                      ),
                    ),
                    if (profile.companies.length > 1) Icon(Icons.swap_horiz, size: 18, color: scheme.onPrimaryContainer),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (final (group, items) in _groups)
          if (items.any(sections.contains)) ...[
            _GroupHeader(group: group),
            for (final s in items)
              if (sections.contains(s)) _DrawerTile(section: s, group: group, selected: s == current, onTap: () => onSelect(s)),
          ],
        const Padding(padding: EdgeInsets.fromLTRB(28, 8, 28, 8), child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ListTile(
            leading: Icon(Icons.logout, color: scheme.error),
            title: Text('Cerrar sesión', style: TextStyle(color: scheme.error)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            onTap: () => _logout(context),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Título de una sección del drawer: ícono en su color y el nombre.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final NavGroup group;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(group.color, Colors.white, .2)!, group.color],
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: group.color.withValues(alpha: .3), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Icon(group.icon, size: 15, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              group.label.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: group.ink(context), fontWeight: FontWeight.w800, letterSpacing: .6),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una opción del drawer: ícono y texto con el color de su sección; la
/// seleccionada, con el fondo de ese color y una marca a la izquierda.
class _DrawerTile extends StatelessWidget {
  const _DrawerTile({required this.section, required this.group, required this.selected, required this.onTap});

  final Section section;
  final NavGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = group.ink(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 1, 12, 1),
      child: Material(
        color: selected ? group.soft(context, .14) : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: group.soft(context, .2),
          highlightColor: group.soft(context, .08),
          child: SizedBox(
            height: 50,
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 4,
                  height: selected ? 22 : 0,
                  margin: const EdgeInsets.only(left: 6, right: 10),
                  decoration: BoxDecoration(color: group.color, borderRadius: BorderRadius.circular(4)),
                ),
                Icon(selected ? section.selectedIcon : section.icon, color: selected ? group.color : group.color.withValues(alpha: .85)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    section.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? ink : Theme.of(context).colorScheme.onSurface,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
