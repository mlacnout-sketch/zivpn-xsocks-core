import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../widgets/ping_button.dart';
import '../../widgets/donation_widgets.dart';
import '../../utils/format_utils.dart';

class DashboardTab extends StatefulWidget {
  final String vpnState;
  final VoidCallback onToggle;
  final ValueNotifier<String> dl, ul;
  final ValueNotifier<String> duration;
  final ValueNotifier<int> sessionRx, sessionTx;
  final bool autoPilotActive;
  final bool isResetting;

  const DashboardTab({
    super.key,
    required this.vpnState,
    required this.onToggle,
    required this.dl,
    required this.ul,
    required this.duration,
    required this.sessionRx,
    required this.sessionTx,
    this.autoPilotActive = false,
    this.isResetting = false,
  });

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 0.0, end: 10.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );
    
    if (widget.vpnState == "connecting") {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(DashboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.vpnState != oldWidget.vpnState) {
      if (widget.vpnState == "connecting") {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isConnected = widget.vpnState == "connected";
    bool isConnecting = widget.vpnState == "connecting";
    Color statusColor = isConnected ? AppColors.primary : (isConnecting ? Colors.orange : AppColors.card);

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "ZIVPN",
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const Text("Turbo Tunnel Engine", style: TextStyle(color: Colors.grey)),
          const SiOrenBanner(), // Banner Si Oren
          const SizedBox(height: 20),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: RepaintBoundary(
                    child: GestureDetector(
                      onTap: isConnecting ? null : widget.onToggle,
                      child: AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Container(
                            width: 220,
                            height: 240,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: statusColor,
                              boxShadow: [
                                BoxShadow(
                                  color: (isConnecting ? Colors.orange : (isConnected ? AppColors.primary : Colors.black))
                                      .withValues(alpha: isConnecting ? 0.6 : 0.4),
                                  blurRadius: isConnecting ? 20 + _pulseAnimation.value : 30,
                                  spreadRadius: isConnecting ? 5 + _pulseAnimation.value : 10,
                                )
                              ],
                            ),
                            child: child,
                          );
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isConnecting)
                              const SizedBox(
                                width: 64, 
                                height: 64, 
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
                              )
                            else
                              Icon(
                                isConnected ? Icons.vpn_lock : Icons.power_settings_new,
                                size: 64,
                                color: Colors.white,
                              ),
                            const SizedBox(height: 15),
                            Text(
                              isConnecting ? "CONNECTING..." : (isConnected ? "CONNECTED" : "TAP TO CONNECT"),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (isConnected) ...[
                              const SizedBox(height: 15),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: ValueListenableBuilder<String>(
                                  valueListenable: widget.duration,
                                  builder: (context, val, _) {
                                    return Text(
                                      val,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Colors.white,
                                      ),
                                    );
                                  }
                                ),
                              ),
                              if (widget.autoPilotActive) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: widget.isResetting ? Colors.redAccent : Colors.blueAccent.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: widget.isResetting ? Colors.red : Colors.blueAccent, width: 0.5),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        widget.isResetting ? Icons.sync : Icons.radar,
                                        size: 10,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        widget.isResetting ? "RESETTING" : "MONITORING",
                                        style: const TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              ]
                            ]
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (isConnected)
                  const Positioned(
                    bottom: 20,
                    right: 20,
                    child: PingButton(),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 15),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: ValueListenableBuilder<int>(
              valueListenable: widget.sessionRx,
              builder: (context, rx, _) {
                return ValueListenableBuilder<int>(
                  valueListenable: widget.sessionTx,
                  builder: (context, tx, _) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Text(
                          "Session: ${FormatUtils.formatBytes(rx + tx)}",
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        Container(width: 1, height: 12, color: Colors.white10),
                        Text(
                          "Rx: ${FormatUtils.formatBytes(rx)}",
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                        ),
                        Container(width: 1, height: 12, color: Colors.white10),
                        Text(
                          "Tx: ${FormatUtils.formatBytes(tx)}",
                          style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                        ),
                      ],
                    );
                  }
                );
              }
            ),
          ),
          Row(
            children: [
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: widget.dl,
                  builder: (context, val, _) => StatCard(
                    label: "Download",
                    value: val,
                    icon: Icons.download,
                    color: Colors.green,
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: widget.ul,
                  builder: (context, val, _) => StatCard(
                    label: "Upload",
                    value: val,
                    icon: Icons.upload,
                    color: Colors.orange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

}

class StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          )
        ],
      ),
    );
  }
}
