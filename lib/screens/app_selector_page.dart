import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_colors.dart';

class AppSelectorPage extends StatefulWidget {
  final List<String> initialSelected;

  const AppSelectorPage({super.key, required this.initialSelected});

  @override
  State<AppSelectorPage> createState() => _AppSelectorPageState();
}

class _AppSelectorPageState extends State<AppSelectorPage> {
  static const platform = MethodChannel('com.minizivpn.app/core');
  
  List<Map<String, String>> _allApps = [];
  List<Map<String, String>> _filteredApps = [];
  final Set<String> _selectedPackages = {};
  bool _isLoading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedPackages.addAll(widget.initialSelected);
    _loadApps();
    _searchCtrl.addListener(_filterApps);
  }

  Future<void> _loadApps() async {
    try {
      final List<dynamic> apps = await platform.invokeMethod('getInstalledApps');

      // ⚡ Bolt Optimization: Pre-compute lowercase values once.
      // Moves O(N) processing out of the search loop, preventing lag during typing.
      final processedApps = apps.map((e) {
        final map = Map<String, String>.from(e);
        map['name_lower'] = map['name']!.toLowerCase();
        map['package_lower'] = map['package']!.toLowerCase();
        return map;
      }).toList();

      if (mounted) {
        setState(() {
          _allApps = processedApps;
          _filteredApps = _allApps;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load apps: $e")),
        );
      }
    }
  }

  void _filterApps() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _filteredApps = _allApps.where((app) {
        // ⚡ Bolt Optimization: Use pre-computed lowercase values
        // Reduces filter complexity from O(N * string_len) to O(N * lookup)
        return app['name_lower']!.contains(query) ||
               app['package_lower']!.contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Select Apps"),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.pop(context, _selectedPackages.toList()),
          )
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: "Search apps...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: AppColors.card,
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _filteredApps.length,
              itemBuilder: (context, index) {
                final app = _filteredApps[index];
                final pkg = app['package']!;
                final isSelected = _selectedPackages.contains(pkg);

                return CheckboxListTile(
                  title: Text(app['name']!),
                  subtitle: Text(pkg, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  value: isSelected,
                  activeColor: AppColors.primary,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedPackages.add(pkg);
                      } else {
                        _selectedPackages.remove(pkg);
                      }
                    });
                  },
                );
              },
            ),
    );
  }
}
