enum AutoPilotStatus {
  idle,
  running,
  monitoring,
  checking,
  recovering,
  resetting,
  stabilizing,
  error,
  stopped,
}

class AutoPilotState {
  final AutoPilotStatus status;
  final int failCount;
  final String? message;
  final DateTime? lastCheck;
  final bool hasInternet;
  final int? networkScore;

  const AutoPilotState({
    this.status = AutoPilotStatus.idle,
    this.failCount = 0,
    this.message,
    this.lastCheck,
    this.hasInternet = false,
    this.networkScore,
  });

  AutoPilotState copyWith({
    AutoPilotStatus? status,
    int? failCount,
    String? message,
    DateTime? lastCheck,
    bool? hasInternet,
    int? networkScore,
  }) {
    return AutoPilotState(
      status: status ?? this.status,
      failCount: failCount ?? this.failCount,
      message: message ?? this.message,
      lastCheck: lastCheck ?? this.lastCheck,
      hasInternet: hasInternet ?? this.hasInternet,
      networkScore: networkScore ?? this.networkScore,
    );
  }
}
