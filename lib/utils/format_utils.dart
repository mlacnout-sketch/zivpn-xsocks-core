class FormatUtils {
  static String formatBytes(int bytes, {bool asSpeed = false}) {
    final suffix = asSpeed ? "/s" : "";

    if (bytes < 1024) {
      return "$bytes B$suffix";
    } else if (bytes < 1024 * 1024) {
      return "${(bytes / 1024).toStringAsFixed(1)} KB$suffix";
    } else if (bytes < 1024 * 1024 * 1024) {
      return "${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB$suffix";
    } else {
      return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB$suffix";
    }
  }
}
