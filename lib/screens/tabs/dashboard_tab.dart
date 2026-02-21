import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../widgets/ping_button.dart';
import '../../widgets/donation_widgets.dart';
import '../../utils/format_utils.dart';

class DashboardTab extends StatefulWidget {
  final String vpnState;
  final VoidCallback onToggle;
  final VoidCallback? onToggleAutoPilot;
  final ValueNotifier<String> dl, ul;
  final ValueNotifier<String> duration;
  final ValueNotifier<int> sessionRx, sessionTx;
  final bool autoPilotActive;
  final bool isResetting;

  const DashboardTab({
    super.key,
    required this.vpnState,
    required this.onToggle,
    this.onToggleAutoPilot,
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
  bool _startEntrance = false;

  @override
  void initState() {
    super.initState() ;
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

    // Trigger entrance animation
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _startEntrance = true);
    });
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
          AnimatedOpacity(
            duration: const Duration(milliseconds: 600),
            opacity: _startEntrance ? 1.0 : 0.0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "ZIVPN",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text("Turbo Tunnel Engine", style: TextStyle(color: Colors.grey)),
                  ],
                ),
                if (widget.onToggleAutoPilot != null)
                  _AutoPilotShortcut(
                    isActive: widget.autoPilotActive,
                    onToggle: widget.onToggleAutoPilot!,
                  ),
              ],
            ),
          ),
          const SiOrenBanner(), // Banner Si Oren
          const SizedBox(height: 20),
          Expanded(
            child: AnimatedScale(
              duration: const Duration(milliseconds: 800),
              scale: _startEntrance ? 1.0 : 0.8,
              curve: Curves.elasticOut,
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

class _AutoPilotShortcut extends StatefulWidget {
  final bool isActive;
  final VoidCallback onToggle;

  const _AutoPilotShortcut({required this.isActive, required this.onToggle});

  @override
  State<_AutoPilotShortcut> createState() => _AutoPilotShortcutState();
}

class _AutoPilotShortcutState extends State<_AutoPilotShortcut> with SingleTickerProviderStateMixin, RouteAware {
  late AnimationController _controller;
  late Animation<Offset> _planeAnimation;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _planeAnimation = Tween<Offset>(
      begin: const Offset(-0.3, 0),
      end: const Offset(0.3, 0),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _updateAnimation();
  }

  void _updateAnimation() {
    if (widget.isActive && _isVisible) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
    }
  }

  @override
  void didUpdateWidget(_AutoPilotShortcut oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      _updateAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: widget.isActive ? Colors.blueAccent.withValues(alpha: 0.1) : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: widget.isActive ? Colors.blueAccent : Colors.white10,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                // Kalkulasi rotasi berdasarkan posisi animasi (miring saat belok)
                final rotation = (_planeAnimation.value.dx * 0.5);
                return Transform.rotate(
                  angle: rotation,
                  child: SlideTransition(
                    position: _planeAnimation,
                    child: Icon(
                      widget.isActive ? Icons.airplanemode_active : Icons.airplanemode_inactive,
                      size: 18,
                      color: widget.isActive ? Colors.blueAccent : Colors.grey,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            Text(
              "Auto Pilot",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: widget.isActive ? Colors.blueAccent : Colors.grey,
              ),
            ),
          ],
        ),
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
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  value,
                  key: ValueKey(value),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          )
        ],
      ),
    );
  }
}
