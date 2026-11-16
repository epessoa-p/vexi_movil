import 'package:flutter/material.dart';

/// Secciones del menú con su color: las mismas de la web
/// (vexi_web/app/Support/Navigation.php). El usuario aprende que «verde es
/// Clínica» o «naranja es Ventas» y se ubica igual en la web y en la app.
enum NavGroup {
  principal('Principal', Icons.space_dashboard_outlined, Color(0xFF2563EB)),
  clinica('Clínica', Icons.monitor_heart_outlined, Color(0xFF059669)),
  ventas('Ventas y caja', Icons.payments_outlined, Color(0xFFEA580C)),
  finanzas('Finanzas', Icons.account_balance_outlined, Color(0xFFCA8A04)),
  comisiones('Comisiones', Icons.how_to_reg_outlined, Color(0xFF4F46E5)),
  inventario('Inventario', Icons.inventory_2_outlined, Color(0xFF7C3AED)),
  compras('Compras', Icons.shopping_bag_outlined, Color(0xFF0D9488)),
  cuenta('Cuenta', Icons.tune, Color(0xFF475569));

  const NavGroup(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  /// El color para texto: más oscuro en tema claro y más claro en oscuro, legible en ambos.
  Color ink(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? Color.lerp(color, Colors.white, .35)! : Color.lerp(color, Colors.black, .18)!;

  /// Fondo suave del color de la sección.
  Color soft(BuildContext context, [double alpha = .12]) => color.withValues(alpha: alpha);
}
