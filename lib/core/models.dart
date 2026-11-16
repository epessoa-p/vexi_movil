/// Perfil de `GET /me`: con él la app decide qué mostrar. El servidor igual
/// revalida cada petición; esto solo evita ofrecer lo que no se puede usar.
class Profile {
  Profile({
    required this.userId,
    required this.name,
    required this.email,
    required this.isSuperAdmin,
    required this.companies,
    this.company,
    this.permissions = const {},
    this.features = const {},
    this.planName,
    this.subscriptionStatus,
    this.subscriptionLabel,
    this.allowsWrite = true,
  });

  final int userId;
  final String name;
  final String email;
  final bool isSuperAdmin;
  final List<CompanyRef> companies;
  final CompanyInfo? company;
  final Set<String> permissions;
  final Set<String> features;
  final String? planName;
  final String? subscriptionStatus;
  final String? subscriptionLabel;
  final bool allowsWrite;

  factory Profile.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    final plan = json['plan'] as Map<String, dynamic>?;
    final sub = json['subscription'] as Map<String, dynamic>?;
    final company = json['company'] as Map<String, dynamic>?;

    return Profile(
      userId: user['id'] as int,
      name: user['name'] as String,
      email: user['email'] as String,
      isSuperAdmin: json['is_super_admin'] == true,
      companies: [for (final c in (json['companies'] as List? ?? [])) CompanyRef(c['id'] as int, c['name'] as String)],
      company: company == null ? null : CompanyInfo.fromJson(company),
      permissions: {for (final p in (json['permissions'] as List? ?? [])) '$p'},
      features: {for (final f in (plan?['features'] as List? ?? [])) '$f'},
      planName: plan?['name'] as String?,
      subscriptionStatus: sub?['status'] as String?,
      subscriptionLabel: sub?['label'] as String?,
      allowsWrite: sub?['allows_write'] != false,
    );
  }

  bool can(String permission) => isSuperAdmin || permissions.contains(permission);

  bool has(String module) => isSuperAdmin || features.contains(module);

  /// Módulo del plan + permiso: lo que la web exige para entrar.
  bool canUse(String module, String permission) => has(module) && can(permission);
}

class CompanyRef {
  const CompanyRef(this.id, this.name);

  final int id;
  final String name;
}

class CompanyInfo {
  CompanyInfo({required this.id, required this.name, this.currencySymbol, this.phone, this.address, this.logoUrl});

  final int id;
  final String name;
  final String? currencySymbol;
  final String? phone;
  final String? address;
  final String? logoUrl;

  factory CompanyInfo.fromJson(Map<String, dynamic> json) => CompanyInfo(
    id: json['id'] as int,
    name: json['name'] as String,
    currencySymbol: json['currency_symbol'] as String?,
    phone: json['phone'] as String?,
    address: json['address'] as String?,
    logoUrl: json['logo_url'] as String?,
  );
}

/// Atajos para leer el JSON de la API sin repetir casts.
extension JsonRead on Map<String, dynamic> {
  String? str(String key) => this[key]?.toString();

  int? integer(String key) => this[key] is int ? this[key] as int : int.tryParse('${this[key]}');

  double? number(String key) => this[key] is num ? (this[key] as num).toDouble() : double.tryParse('${this[key]}');

  bool flag(String key) => this[key] == true;

  DateTime? date(String key) => this[key] == null ? null : DateTime.tryParse('${this[key]}')?.toLocal();

  Map<String, dynamic>? obj(String key) => this[key] is Map ? Map<String, dynamic>.from(this[key] as Map) : null;

  List<Map<String, dynamic>> list(String key) => [
    for (final item in (this[key] as List? ?? const [])) Map<String, dynamic>.from(item as Map),
  ];
}
