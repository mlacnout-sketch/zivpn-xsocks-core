const int _kib = 1024;
const int _mib = _kib * 1024;
const int _gib = _mib * 1024;

String formatBytes(
  int bytes, {
  bool perSecond = false,
  int kbFractionDigits = 1,
  int mbFractionDigits = 2,
  int gbFractionDigits = 2,
}) {
  final safeBytes = bytes < 0 ? 0 : bytes;
  final suffix = perSecond ? '/s' : '';

  if (safeBytes < _kib) return '$safeBytes B$suffix';
  if (safeBytes < _mib) {
    return '${(safeBytes / _kib).toStringAsFixed(kbFractionDigits)} KB$suffix';
  }
  if (safeBytes < _gib) {
    return '${(safeBytes / _mib).toStringAsFixed(mbFractionDigits)} MB$suffix';
  }
  return '${(safeBytes / _gib).toStringAsFixed(gbFractionDigits)} GB$suffix';
}
