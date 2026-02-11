import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_colors.dart';
import '../logic/ping_logic.dart';

class PingButton extends StatefulWidget {
  const PingButton({super.key});

  @override
  State<PingButton> createState() => _PingButtonState();
}

class _PingButtonState extends State<PingButton> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  final ValueNotifier<String> _result = ValueNotifier("");
  bool _isPinging = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _result.dispose();
    super.dispose();
  }

  Future<void> _doPing() async {
    if (_isPinging) return;

    _isPinging = true;
    _result.value = "Pinging...";
    _animController.repeat();

    try {
      final prefs = await SharedPreferences.getInstance();
      String target = (prefs.getString('ping_target') ?? "https://clients3.google.com/generate_204").trim();

      final res = await PingLogic.performPing(target).timeout(
        const Duration(seconds: 15), 
        onTimeout: () => "Timeout"
      );
      if (mounted) _result.value = res;
    } catch (e) {
      if (mounted) _result.value = "Error";
    } finally {
      if (mounted) {
        _isPinging = false;
        _animController.stop();
        _animController.reset();
      }
    }
  }

  Color _getColor(String res) {
    if (res == "Pinging...") return Colors.white;
    if (res.contains("ms")) {
      final msStr = res.split(' ')[0] == "TCP" ? res.split(' ')[1] : res.split(' ')[0];
      final ms = int.tryParse(msStr) ?? 999;
      
      if (res.startsWith("TCP")) return Colors.cyanAccent; // Always cyan for TCP to distinguish
      if (ms < 150) return Colors.greenAccent;
      if (ms < 300) return Colors.yellow;
    }
    if (res == "Gstatic OK") return Colors.lightGreenAccent;
    if (res == "HTTP OK") return Colors.lightBlueAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: _result,
      builder: (context, value, child) {
        return Column(
          children: [
            FloatingActionButton.small(
              heroTag: "ping_btn",
              onPressed: _doPing,
              backgroundColor: AppColors.card,
              elevation: 4,
              child: RotationTransition(
                turns: _animController,
                child: Icon(
                  Icons.flash_on,
                  color: _isPinging ? Colors.yellow : AppColors.primary,
                ),
              ),
            ),
            if (value.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _getColor(value).withValues(alpha: 0.3),
                    width: 1
                  )
                ),
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _getColor(value),
                  ),
                ),
              ),
            ]
          ],
        );
      },
    );
  }
}
