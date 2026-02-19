/// PING status enumeration
enum PingStatus {
  success, // ✓ 200/204 response
  failed, // ✗ Network/DNS failure
  timeout; // ✗ Timeout exceeded

  String get emoji {
    switch (this) {
      case PingStatus.success:
        return '✓';
      case PingStatus.failed:
      case PingStatus.timeout:
        return '✗';
    }
  }

  String get displayName {
    switch (this) {
      case PingStatus.success:
        return 'Connected';
      case PingStatus.failed:
        return 'Failed';
      case PingStatus.timeout:
        return 'Timeout';
    }
  }
}

/// Latency quality classification
enum LatencyQuality {
  excellent, // 0-100 ms
  good, // 100-200 ms
  acceptable, // 200-400 ms
  slow, // 400-5000 ms
  timeout; // 5000+ ms

  String get displayName {
    switch (this) {
      case LatencyQuality.excellent:
        return 'Excellent';
      case LatencyQuality.good:
        return 'Good';
      case LatencyQuality.acceptable:
        return 'Acceptable';
      case LatencyQuality.slow:
        return 'Slow';
      case LatencyQuality.timeout:
        return 'Timeout';
    }
  }

  String get emoji {
    switch (this) {
      case LatencyQuality.excellent:
        return '⚡';
      case LatencyQuality.good:
        return '✓';
      case LatencyQuality.acceptable:
        return '⚠️';
      case LatencyQuality.slow:
        return '🐌';
      case LatencyQuality.timeout:
        return '❌';
    }
  }
}

/// PING log entry with complete connectivity check data
class PingLogEntry {
  final DateTime timestamp;
  final PingStatus status;
  final int? latencyMs; // milliseconds for successful pings
  final int? statusCode; // HTTP status code (200/204)
  final String destination;
  final String? errorMessage;

  const PingLogEntry({
    required this.timestamp,
    required this.status,
    this.latencyMs,
    this.statusCode,
    required this.destination,
    this.errorMessage,
  });

  /// Get latency quality classification
  LatencyQuality get latencyQuality {
    if (status != PingStatus.success || latencyMs == null) {
      return status == PingStatus.timeout
          ? LatencyQuality.timeout
          : LatencyQuality.excellent;
    }

    if (latencyMs! <= 100) return LatencyQuality.excellent;
    if (latencyMs! <= 200) return LatencyQuality.good;
    if (latencyMs! <= 400) return LatencyQuality.acceptable;
    if (latencyMs! <= 5000) return LatencyQuality.slow;
    return LatencyQuality.timeout;
  }

  /// Format for activity log display
  String toActivityLogFormat() {
    final quality = latencyQuality;
    switch (status) {
      case PingStatus.success:
        return '${quality.emoji} PING ${quality.displayName} ($latencyMs ms)';
      case PingStatus.failed:
        return '${status.emoji} PING FAILED: ${errorMessage?.split('\n').first ?? 'Unknown'}';
      case PingStatus.timeout:
        return '${status.emoji} PING TIMEOUT (>${latencyMs ?? 5000} ms)';
    }
  }

  /// Format for notification
  String toNotificationFormat() {
    final quality = latencyQuality;
    switch (status) {
      case PingStatus.success:
        return '${quality.emoji} Network ${quality.displayName}\n$latencyMs ms • ${destination.split('/').skip(2).join('/')}';
      case PingStatus.failed:
        return '${status.emoji} Connection Failed\n${errorMessage?.split('\n').first ?? 'DNS/Network error'}';
      case PingStatus.timeout:
        return '${status.emoji} Connection Timeout\nNo response for 5+ seconds';
    }
  }

  @override
  String toString() => toActivityLogFormat();
}
