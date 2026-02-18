class Account {
  final String name;
  final String ip;
  final String auth;
  final String obfs;
  int usage;

  Account({
    required this.name,
    required this.ip,
    required this.auth,
    this.obfs = "hu``hqb`c",
    this.usage = 0,
  });

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      name: json['name'] ?? '',
      ip: json['ip'] ?? '',
      auth: json['auth'] ?? '',
      obfs: json['obfs'] ?? "hu``hqb`c",
      usage: json['usage'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'ip': ip, 'auth': auth, 'obfs': obfs, 'usage': usage};
  }
}
