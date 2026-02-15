import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../models/account.dart';
import '../../utils/format_utils.dart';

class ProxiesTab extends StatefulWidget {
  final List<Account> accounts;
  final int activePingIndex;
  final Function(int) onActivate;
  final Function(Account) onAdd;
  final Function(int, Account) onEdit;
  final Function(int) onDelete;

  const ProxiesTab({
    super.key,
    required this.accounts,
    required this.activePingIndex,
    required this.onActivate,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<ProxiesTab> createState() => _ProxiesTabState();
}

class _ProxiesTabState extends State<ProxiesTab> {
  void _showAccountDialog(BuildContext context, {int? index}) {
    final isEditing = index != null;
    final Account? existingData = isEditing ? widget.accounts[index] : null;

    final nameCtrl = TextEditingController(text: existingData?.name ?? "");
    final ipCtrl = TextEditingController(text: existingData?.ip ?? "");
    final authCtrl = TextEditingController(text: existingData?.auth ?? "");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Row(
          children: [
            Icon(isEditing ? Icons.edit_note : Icons.add_circle_outline, color: AppColors.primary),
            const SizedBox(width: 12),
            Text(isEditing ? "Edit Account" : "Add Account", style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              _buildModernInput(nameCtrl, "Account Name", Icons.label_outline),
              const SizedBox(height: 16),
              _buildModernInput(ipCtrl, "Server IP / Domain", Icons.dns_outlined),
              const SizedBox(height: 16),
              _buildModernInput(authCtrl, "Password", Icons.vpn_key_outlined),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: Colors.grey),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () {
              final name = nameCtrl.text.trim();
              final ip = ipCtrl.text.trim();
              final pass = authCtrl.text.trim();

              if (name.isEmpty || ip.isEmpty || pass.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("All fields are required!")),
                );
                return;
              }

              final newData = Account(
                name: name,
                ip: ip,
                auth: pass,
                obfs: existingData?.obfs ?? "hu``hqb`c",
                usage: existingData?.usage ?? 0,
              );

              if (isEditing) {
                widget.onEdit(index, newData);
              } else {
                widget.onAdd(newData);
              }
              Navigator.pop(ctx);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Widget _buildModernInput(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: AppColors.primary.withValues(alpha: 0.7)),
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAccountDialog(context),
        backgroundColor: AppColors.primary,
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
                final usage = acc.usage;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: isSelected ? const BorderSide(color: AppColors.primary, width: 2) : BorderSide.none,
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.dns,
                        color: isSelected ? Colors.white : Colors.white70,
                      ),
                    ),
                    title: Text(
                      acc.name.isEmpty ? "Unknown" : acc.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          acc.ip,
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
                            "Used: ${FormatUtils.formatBytes(usage)}",
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                    trailing: PopupMenuButton(
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(value: 'edit', child: Text("Edit")),
                        const PopupMenuItem(value: 'del', child: Text("Delete")),
                      ],
                      onSelected: (val) {
                        if (val == 'edit') {
                          _showAccountDialog(context, index: index);
                        } else if (val == 'del') {
                          widget.onDelete(index);
                        }
                      },
                    ),
                    onTap: () => widget.onActivate(index),
                  ),
                );
              },
            ),
    );
  }
}
