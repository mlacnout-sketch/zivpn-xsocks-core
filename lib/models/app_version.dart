class AppVersion {
  final String name;
  final String apkUrl;
  final int apkSize;
  final String description;
  final String? abi;

  AppVersion({
    required this.name,
    required this.apkUrl,
    required this.apkSize,
    required this.description,
    this.abi,
  });
}
