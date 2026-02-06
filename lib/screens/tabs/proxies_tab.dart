import 'package:flutter/material.dart';
import 'dart:io';

class ProxiesTab extends StatefulWidget {
  final List<Map<String, dynamic>> accounts;
  final int activePingIndex;
  final Function(int) onActivate;
  final Function(Map<String, dynamic>) onAdd;
  final Function(int) onDelete;

  const ProxiesTab({
    super.key,
    required this.accounts,
    required this.activePingIndex,
    required this.onActivate,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  State<ProxiesTab> createState() => _ProxiesTabState();
}

class _ProxiesTabState extends State<ProxiesTab> with TickerProviderStateMixin {
  final Map<int, String> _pingResults = {};
  final Map<int, bool> _isPinging = {};
  final Map<int, AnimationController> _animControllers = {};

  final List<String> suggestions = [
    "http://google.com/generate_204",
    "http://cp.cloudflare.com/generate_204",
    "https://www.gstatic.com/generate_204",
    "connectivitycheck.gstatic.com",
    "1.1.1.1"
  ];

  @override
  void dispose() {
    for (var controller in _animControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _showAddDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final ipCtrl = TextEditingController();
    final authCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF272736),
        title: const Text("Add Account"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: "Account Name"),
              ),
              TextField(
                controller: ipCtrl,
                decoration: const InputDecoration(labelText: "IP/Domain:Port"),
              ),
              TextField(
                controller: authCtrl,
                decoration: const InputDecoration(labelText: "Password"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (nameCtrl.text.isNotEmpty && ipCtrl.text.isNotEmpty) {
                widget.onAdd({
                  "name": nameCtrl.text,
                  "ip": ipCtrl.text,
                  "auth": authCtrl.text,
                  "obfs": "hu``hqb`c",
                  "usage": 0,
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _showPingDialog(BuildContext context, int index) {
    final targetCtrl = TextEditingController(text: suggestions[0]);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF272736),
        title: const Text("Ping Destination"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Autocomplete<String>(
              initialValue: TextEditingValue(text: targetCtrl.text),
              optionsBuilder: (v) => suggestions.where((s) => s.contains(v.text.toLowerCase())),
              onSelected: (s) => targetCtrl.text = s,
              fieldViewBuilder: (ctx, ctrl, node, onSub) {
                ctrl.addListener(() => targetCtrl.text = ctrl.text);
                return TextField(
                  controller: ctrl,
                  focusNode: node,
                  decoration: const InputDecoration(
                    labelText: "Target",
                    prefixIcon: Icon(Icons.network_check),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: suggestions.take(3).map((s) => ActionChip(
                label: Text(s, style: const TextStyle(fontSize: 10)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _doPing(index, s);
                },
              )).toList(),
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF)),
            onPressed: () {
              Navigator.pop(ctx);
              String target = targetCtrl.text.trim();
              _doPing(index, target);
            },
            child: const Text("Ping"),
          )
        ],
      ),
    );
  }

  Future<void> _doPing(int index, String target) async {
    if (!_animControllers.containsKey(index)) {
      _animControllers[index] = AnimationController(
        duration: const Duration(milliseconds: 1000),
        vsync: this,
      );
    }
    
    _animControllers[index]!.repeat();
    
    setState(() {
      _isPinging[index] = true;
      _pingResults[index] = "Pinging...";
    });

    final sw = Stopwatch()..start();
    String latency = "Timeout";

    try {
      if (target.startsWith("http")) {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 5);
        final req = await client.getUrl(Uri.parse(target));
        final res = await req.close();
        sw.stop();
        if (res.statusCode == 204 || res.statusCode == 200) {
          latency = "${sw.elapsedMilliseconds} ms";
        } else {
          latency = "HTTP ${res.statusCode}";
        }
      } else {
        final res = await Process.run('ping', ['-c', '1', '-W', '2', target]);
        sw.stop();
        if (res.exitCode == 0) {
          final m = RegExp(r"time=([0-9\.]+) ms").firstMatch(res.stdout.toString());
          if (m != null) latency = "${m.group(1)} ms";
        }
      }
    } catch (_) {
      latency = "Error";
    }

    if (mounted) {
      setState(() {
        _pingResults[index] = latency;
        _isPinging[index] = false;
      });
      _animControllers[index]!.stop();
      _animControllers[index]!.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        backgroundColor: const Color(0xFF6C63FF),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: widget.accounts.isEmpty
          ? const Center(child: Text("No accounts saved", style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: widget.accounts.length,
              itemBuilder: (context, index) {
                final acc = widget.accounts[index];
                final isSelected = index == widget.activePingIndex;
                final res = _pingResults[index];
                final isPinging = _isPinging[index] ?? false;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: isSelected ? const BorderSide(color: Color(0xFF6C63FF), width: 2) : BorderSide.none,
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF6C63FF) : Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.dns,
                        color: isSelected ? Colors.white : Colors.white70,
                      ),
                    ),
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          acc['name'] ?? "Unknown",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (res != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: res.contains("ms") ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              res,
                              style: TextStyle(
                                fontSize: 10,
                                color: res.contains("ms") ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      acc['ip'] ?? "",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: RotationTransition(
                            turns: _animControllers[index] ?? const AlwaysStoppedAnimation(0),
                            child: Icon(
                              Icons.flash_on,
                              color: isPinging ? Colors.yellow : Colors.grey,
                              size: 20,
                            ),
                          ),
                          onPressed: () => _showPingDialog(context, index),
                        ),
                        PopupMenuButton(
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(value: 'del', child: Text("Delete")),
                          ],
                          onSelected: (v) => widget.onDelete(index),
                        ),
                      ],
                    ),
                    onTap: () => widget.onActivate(index),
                  ),
                );
              },
            ),
    );
  }
}