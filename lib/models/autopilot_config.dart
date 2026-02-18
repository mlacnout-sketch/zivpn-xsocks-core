class AutoPilotConfig {
  final int checkIntervalSeconds;
  final int connectionTimeoutSeconds;
  final int maxFailCount;
  final int airplaneModeDelaySeconds;
  final int recoveryWaitSeconds;
  final bool enableStabilizer;
  final bool autoReset; // Added back
  final int stabilizerSizeMb;

  const AutoPilotConfig({
    this.checkIntervalSeconds = 15,
    this.connectionTimeoutSeconds = 5,
    this.maxFailCount = 3,
    this.airplaneModeDelaySeconds = 2,
    this.recoveryWaitSeconds = 10,
    this.enableStabilizer = false,
    this.autoReset = false, // Default false
    this.stabilizerSizeMb = 1,
  });

  AutoPilotConfig copyWith({
    int? checkIntervalSeconds,
    int? connectionTimeoutSeconds,
    int? maxFailCount,
    int? airplaneModeDelaySeconds,
    int? recoveryWaitSeconds,
    bool? enableStabilizer,
    bool? autoReset,
    int? stabilizerSizeMb,
  }) {
    return AutoPilotConfig(
      checkIntervalSeconds: checkIntervalSeconds ?? this.checkIntervalSeconds,
      connectionTimeoutSeconds:
          connectionTimeoutSeconds ?? this.connectionTimeoutSeconds,
      maxFailCount: maxFailCount ?? this.maxFailCount,
      airplaneModeDelaySeconds:
          airplaneModeDelaySeconds ?? this.airplaneModeDelaySeconds,
      recoveryWaitSeconds: recoveryWaitSeconds ?? this.recoveryWaitSeconds,
      enableStabilizer: enableStabilizer ?? this.enableStabilizer,
      autoReset: autoReset ?? this.autoReset,
      stabilizerSizeMb: stabilizerSizeMb ?? this.stabilizerSizeMb,
    );
  }
}
