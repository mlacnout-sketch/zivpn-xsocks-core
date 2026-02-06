import 'package:flutter/material.dart';

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

class _ProxiesTabState extends State<ProxiesTab> {
  String _formatTotalBytes(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB";
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
                final usage = acc['usage'] ?? 0;

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
                    title: Text(
                      acc['name'] ?? "Unknown",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          acc['ip'] ?? "",
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(4)
                          ),
                          child: Text(
                            "Used: ${_formatTotalBytes(usage)}",
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                    trailing: PopupMenuButton(
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(value: 'del', child: Text("Delete")),
                      ],
                      onSelected: (v) => widget.onDelete(index),
                    ),
                    onTap: () => widget.onActivate(index),
                  ),
                );
              },
            ),
    );
  }
}