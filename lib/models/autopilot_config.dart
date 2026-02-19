class AutoPilotConfig {
  final int checkIntervalSeconds;
  final int connectionTimeoutSeconds;
  final int maxFailCount;
  final int airplaneModeDelaySeconds;
  final int recoveryWaitSeconds;
  final bool autoHealthCheck;
  final bool enablePingStabilizer;
  final int stabilizerSizeMb;
  final int maxConsecutiveResets;
  final String pingDestination;

  bool get autoReset => autoHealthCheck;

  const AutoPilotConfig({
    this.checkIntervalSeconds = 15,
    this.connectionTimeoutSeconds = 5,
    this.maxFailCount = 3,
    this.airplaneModeDelaySeconds = 3,
    this.recoveryWaitSeconds = 10,
    this.autoHealthCheck = false,
    this.enablePingStabilizer = false,
    this.stabilizerSizeMb = 1,
    this.maxConsecutiveResets = 5,
    this.pingDestination = 'http://connectivitycheck.gstatic.com/generate_204',
  });

  AutoPilotConfig copyWith({
    int? checkIntervalSeconds,
    int? connectionTimeoutSeconds,
    int? maxFailCount,
    int? airplaneModeDelaySeconds,
    int? recoveryWaitSeconds,
    bool? autoHealthCheck,
    bool? enablePingStabilizer,
    int? stabilizerSizeMb,
    int? maxConsecutiveResets,
    String? pingDestination,
  }) {
    return AutoPilotConfig(
      checkIntervalSeconds: checkIntervalSeconds ?? this.checkIntervalSeconds,
      connectionTimeoutSeconds:
          connectionTimeoutSeconds ?? this.connectionTimeoutSeconds,
      maxFailCount: maxFailCount ?? this.maxFailCount,
      airplaneModeDelaySeconds:
          airplaneModeDelaySeconds ?? this.airplaneModeDelaySeconds,
      recoveryWaitSeconds: recoveryWaitSeconds ?? this.recoveryWaitSeconds,
      autoHealthCheck: autoHealthCheck ?? this.autoHealthCheck,
      enablePingStabilizer: enablePingStabilizer ?? this.enablePingStabilizer,
      stabilizerSizeMb: stabilizerSizeMb ?? this.stabilizerSizeMb,
      maxConsecutiveResets: maxConsecutiveResets ?? this.maxConsecutiveResets,
      pingDestination: pingDestination ?? this.pingDestination,
    );
  }
}
