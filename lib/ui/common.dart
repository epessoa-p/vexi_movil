import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/session.dart';

// ── Tema ────────────────────────────────────────────────────────────────────

const brand = Color(0xFF2A78D6);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: brand, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    appBarTheme: AppBarTheme(centerTitle: false, backgroundColor: scheme.surface, scrolledUnderElevation: 1),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
  );
}

/// Colores de estado: los mismos nombres que usa la web (Bootstrap).
Color toneColor(BuildContext context, String? tone) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (tone) {
    'danger' => dark ? const Color(0xFFFF8A80) : const Color(0xFFC62828),
    'warning' => dark ? const Color(0xFFFFCC80) : const Color(0xFFB26A00),
    'success' => dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
    'info' => dark ? const Color(0xFF80DEEA) : const Color(0xFF00838F),
    'primary' => Theme.of(context).colorScheme.primary,
    'dark' => Theme.of(context).colorScheme.onSurface,
    _ => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}

// ── Formatos ────────────────────────────────────────────────────────────────

final _time = DateFormat('HH:mm', 'es');
final _date = DateFormat("d 'de' MMM yyyy", 'es');
final _dayLong = DateFormat("EEEE d 'de' MMMM", 'es');
final _dateTime = DateFormat("d MMM, HH:mm", 'es');

String fmtTime(DateTime? d) => d == null ? '—' : _time.format(d);

String fmtDate(DateTime? d) => d == null ? '—' : _date.format(d);

String fmtShortDate(DateTime? d) => d == null ? '—' : DateFormat('d MMM', 'es').format(d);

String fmtDayLong(DateTime d) {
  final text = _dayLong.format(d);
  return text[0].toUpperCase() + text.substring(1);
}

String fmtDateTime(DateTime? d) => d == null ? '—' : _dateTime.format(d);

String fmtNumber(num? n) {
  if (n == null) return '—';
  return n == n.roundToDouble() ? n.toInt().toString() : NumberFormat('#,##0.##', 'es').format(n);
}

// El mismo formato que la web (Money::format), los reportes y los mensajes de WhatsApp.
final _money = NumberFormat('#,##0.00', 'en_US');

/// «Bs 1,234.50» con el símbolo de la moneda de la veterinaria.
String fmtMoney(num? n, [String? symbol]) {
  if (n == null) return '—';
  final prefix = symbol == null || symbol.isEmpty ? '' : '$symbol ';
  return '$prefix${_money.format(n)}';
}

/// Importe con la moneda de la veterinaria activa.
String money(BuildContext context, num? n) => fmtMoney(n, context.read<Session>().profile?.company?.currencySymbol);

/// «hace 5 min», «ayer», «12 nov».
String fmtAgo(DateTime? d) {
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'ahora';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  if (diff.inDays == 1) return 'ayer';
  if (diff.inDays < 7) return 'hace ${diff.inDays} días';
  return DateFormat('d MMM', 'es').format(d);
}

String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

// ── Piezas comunes ──────────────────────────────────────────────────────────

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.tone});

  final String label;
  final String? tone;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: muted),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final e = error;
    final (icon, message) = switch (e) {
      ApiException(isOffline: true) => (Icons.wifi_off, e.message),
      ApiException(code: 'permission_denied') => (Icons.lock_outline, 'Tu rol no tiene acceso a esta sección. Pídeselo al administrador.'),
      ApiException(code: 'plan_module_missing') => (Icons.workspace_premium_outlined, 'El plan de tu veterinaria no incluye este módulo.'),
      ApiException(code: 'subscription_inactive') => (Icons.block, e.message),
      ApiException() => (Icons.error_outline, e.message),
      _ => (Icons.error_outline, 'Algo salió mal. Intenta de nuevo.'),
    };
    return EmptyState(
      icon: icon,
      message: message,
      action: OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: .6,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Carga datos de la API y los muestra con «tirar para actualizar», un
/// indicador mientras carga y un error con botón de reintentar.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<Loader<T>> createState() => LoaderState<T>();
}

class LoaderState<T> extends State<Loader<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final data = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _data == null) {
      return ListView(
        children: [ErrorState(error: _error!, onRetry: reload)],
      );
    }
    return RefreshIndicator(onRefresh: reload, child: widget.builder(context, _data as T, reload));
  }
}

/// Muestra un error de una acción (guardar, confirmar…) sin salir de la pantalla.
void showError(BuildContext context, Object error) {
  final (message, kind) = switch (error) {
    ApiException(isOffline: true) => (error.message, ToastKind.offline),
    ApiException() => (error.message, ToastKind.error),
    String() => (error, ToastKind.error),
    _ => ('No se pudo completar la acción.', ToastKind.error),
  };
  showToast(context, message, kind: kind);
}

/// Pide confirmar una acción. Devuelve true solo si se acepta.
Future<bool> confirm(BuildContext context, {required String title, String? message, String action = 'Aceptar'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return ok == true;
}

/// Pide un texto obligatorio (un motivo, por ejemplo). Null si se cancela.
Future<String?> askText(BuildContext context, {required String title, required String label, String action = 'Aceptar', String? hint}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(title: title, label: label, action: action, hint: hint),
    );

/// Dueño de su controlador: se libera cuando el diálogo termina de cerrarse.
class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.label, required this.action, this.hint});

  final String title;
  final String label;
  final String action;
  final String? hint;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.hint != null) ...[Text(widget.hint!), const SizedBox(height: 12)],
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: widget.label),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty ? null : () => Navigator.pop(context, _controller.text.trim()),
          child: Text(widget.action),
        ),
      ],
    );
  }
}

/// Abre un enlace fuera de la app (WhatsApp, teléfono, mapas…).
Future<void> openExternal(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!ok && context.mounted) showError(context, 'No se pudo abrir la aplicación.');
}

/// Confirma que una acción salió bien («Guardado», «Cita confirmada»…).
void showDone(BuildContext context, String message) => showToast(context, message, kind: ToastKind.success);

/// Aviso neutro, p. ej. «Subiendo la foto…».
void showInfo(BuildContext context, String message) => showToast(context, message, kind: ToastKind.info);

// ── Avisos emergentes ───────────────────────────────────────────────────────

enum ToastKind {
  success(Icons.check_circle_rounded, 'success', Duration(milliseconds: 2800)),
  info(Icons.info_rounded, 'info', Duration(milliseconds: 2800)),
  error(Icons.error_rounded, 'danger', Duration(milliseconds: 5000)),
  offline(Icons.wifi_off_rounded, 'warning', Duration(milliseconds: 5000));

  const ToastKind(this.icon, this.tone, this.duration);

  final IconData icon;
  final String tone;

  /// Los errores quedan más tiempo: hay que leerlos.
  final Duration duration;
}

OverlayEntry? _toastEntry;

/// Aviso que baja desde arriba, se va solo y se cierra al tocarlo o
/// deslizarlo hacia arriba. Uno a la vez: el nuevo reemplaza al anterior.
void showToast(BuildContext context, String message, {ToastKind kind = ToastKind.info, Duration? duration}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _toastEntry?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Toast(
      message: message,
      kind: kind,
      duration: duration ?? kind.duration,
      onDismissed: () {
        if (_toastEntry == entry) _toastEntry = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _toastEntry = entry;
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  const _Toast({required this.message, required this.kind, required this.duration, required this.onDismissed});

  final String message;
  final ToastKind kind;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 220),
  )..forward();
  late final _slide = Tween(
    begin: const Offset(0, -1.2),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn));
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, _close);
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    await _controller.reverse();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = toneColor(context, widget.kind.tone);
    final top = MediaQuery.paddingOf(context).top + 8;

    return Positioned(
      top: top,
      left: 12,
      right: 12,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SlideTransition(
              position: _slide,
              child: FadeTransition(
                opacity: _controller,
                child: Dismissible(
                  key: const ValueKey('toast'),
                  direction: DismissDirection.up,
                  onDismissed: (_) {
                    _closing = true;
                    _timer?.cancel();
                    widget.onDismissed();
                  },
                  child: Semantics(
                    liveRegion: true,
                    child: Material(
                      color: Color.alphaBlend(color.withValues(alpha: .08), scheme.surfaceContainerLowest),
                      elevation: 6,
                      shadowColor: Colors.black38,
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _close,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(left: BorderSide(color: color, width: 4)),
                          ),
                          padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(color: color.withValues(alpha: .14), shape: BoxShape.circle),
                                child: Icon(widget.kind.icon, color: color, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  widget.message,
                                  style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w500, height: 1.3),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Acceso corto a la API desde cualquier pantalla.
extension SessionContext on BuildContext {
  Session get session => read<Session>();
}

/// Logo de la veterinaria; si no subió uno, el dibujo de Vexi.
class CompanyLogo extends StatelessWidget {
  const CompanyLogo({super.key, this.url, this.size = 40});

  final String? url;
  final double size;

  static const fallback = 'assets/brand/vexi_mark.png';

  @override
  Widget build(BuildContext context) {
    final own = url != null && url!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .08),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(size * .25)),
      child: own
          ? Image.network(
              url!,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Image.asset(fallback, fit: BoxFit.contain),
            )
          : Image.asset(fallback, fit: BoxFit.contain),
    );
  }
}

/// Avatar con la inicial (o la foto) de la mascota.
class PetAvatar extends StatelessWidget {
  const PetAvatar({super.key, required this.name, this.photoUrl, this.radius = 22});

  final String name;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: radius * .8),
      ),
    );
  }
}

/// Dato corto con su etiqueta encima (peso, temperatura…).
class Fact extends StatelessWidget {
  const Fact(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
