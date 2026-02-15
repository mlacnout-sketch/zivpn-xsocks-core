import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:math';

// --- KONFIGURASI SAWERIA ---
const String _kSaweriaUrl = "https://saweria.co/Damnwhoknows";

Future<void> _openSaweria(BuildContext context) async {
  final Uri url = Uri.parse(_kSaweriaUrl);
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => SaweriaWebViewPage(initialUrl: url)),
  );
}

Future<void> _openSaweriaExternal() async {
  final Uri url = Uri.parse(_kSaweriaUrl);

  if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
    throw Exception('Tidak bisa membuka link');
  }
}

// ==========================================
// 1. BANNER "SI OREN" (MODERN & MEME STYLE)
// ==========================================
class SiOrenBanner extends StatefulWidget {
  const SiOrenBanner({super.key});

  @override
  State<SiOrenBanner> createState() => _SiOrenBannerState();
}

class _SiOrenBannerState extends State<SiOrenBanner> {
  bool _isVisible = false; 

  @override
  void initState() {
    super.initState();
    // ALGORITMA PROBABILITAS: 30% Muncul
    if (Random().nextInt(100) < 30) {
      _isVisible = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();

    return Dismissible(
      key: const Key('si_oren_banner'),
      direction: DismissDirection.horizontal,
      onDismissed: (direction) => setState(() => _isVisible = false),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        child: Stack(
          children: [
            // Background Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2A2A35), Color(0xFF1F1F28)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.5), width: 2), // OREN LEBIH TEBAL
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.15),
                    blurRadius: 15,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  const Row(
                    children: [
                      Text(
                        "🐈 CAPEK SAMA SI OREN?", 
                        style: TextStyle(
                          color: Colors.orangeAccent, 
                          fontWeight: FontWeight.w900, 
                          fontSize: 16,
                          letterSpacing: 1.2
                        )
                      ),
                      Spacer(),
                      Text("✖️", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Body Text
                  const Text(
                    "Daripada buang waktu nonton iklan judi slot 30 detik, mending traktir dev kopi sachet biar update lancar.",
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  
                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _isVisible = false),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey,
                          textStyle: const TextStyle(fontSize: 11),
                        ),
                        child: const Text("🤡 Skip, gw suka iklan"), 
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _openSaweria(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orangeAccent,
                          foregroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 4,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        icon: const Text("☕", style: TextStyle(fontSize: 18)),
                        label: const Text("Traktir Kopi", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  )
                ],
              ),
            ),
            
            // Decorative Circle (Meme Vibe)
            Positioned(
              right: -10,
              top: -10,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.orange.withValues(alpha: 0.1),
                ),
                child: const Center(child: Text("🍊", style: TextStyle(fontSize: 24))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 2. DIALOG SARKAS (FINAL BOSS)
// ==========================================
// Returns true if dialog shown, false if skipped by RNG
bool showSarcasticDialog(BuildContext context, {required VoidCallback onProceed}) {
  // ALGORITMA PROBABILITAS: 40% Muncul
  if (Random().nextInt(100) > 40) {
    return false; // Skip dialog, langsung proceed di logic pemanggil
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2C),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Image/Icon
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: const Text("🤑", textAlign: TextAlign.center, style: TextStyle(fontSize: 56)),
              ),
              
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      "Wait, Mau Cabut?",
                      style: TextStyle(
                        fontSize: 20, 
                        fontWeight: FontWeight.bold, 
                        color: Colors.white
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Koneksi lancar? Hemat waktu tanpa iklan? \nItu semua murni hasil begadang dev.\n\nMau support biar admin gak tipes ngoding fitur baru?",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white60, 
                        fontSize: 14, 
                        height: 1.5
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Main Action (Donasi)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purpleAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 8,
                          shadowColor: Colors.purpleAccent.withValues(alpha: 0.4),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _openSaweria(context);
                          Future.delayed(const Duration(seconds: 1), onProceed);
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("Support Dev ", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            Text("💖", style: TextStyle(fontSize: 18)),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Villain Action (Skip)
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        onProceed();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey,
                      ),
                      child: const Text(
                        "🗿 Skip, saya tim gratisan sejati",
                        style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  return true;
}


class SaweriaWebViewPage extends StatefulWidget {
  final Uri initialUrl;

  const SaweriaWebViewPage({super.key, required this.initialUrl});

  @override
  State<SaweriaWebViewPage> createState() => _SaweriaWebViewPageState();
}

class _SaweriaWebViewPageState extends State<SaweriaWebViewPage> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
        ),
      )
      ..loadRequest(widget.initialUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Support Dev ☕'),
        actions: [
          IconButton(
            tooltip: 'Buka di browser',
            onPressed: _openSaweriaExternal,
            icon: const Icon(Icons.open_in_new),
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Color(0xFFFF8A00), Color(0xFFFF4D6D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                )
              ],
            ),
            child: const Row(
              children: [
                Text('💖', style: TextStyle(fontSize: 22)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Terima kasih sudah support. Donasi kamu bantu update tetap jalan 🚀',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_loading)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openSaweriaExternal,
        icon: const Icon(Icons.favorite),
        label: const Text('Buka di Browser'),
      ),
    );
  }
}
