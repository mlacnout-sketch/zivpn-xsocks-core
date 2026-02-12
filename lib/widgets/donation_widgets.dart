import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// --- KONFIGURASI SAWERIA ---
const String _kSaweriaUrl = "https://saweria.co/Damnwhoknows";

Future<void> _launchSaweria() async {
  try {
    await launchUrl(Uri.parse(_kSaweriaUrl), mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint("Gagal buka saweria: $e");
  }
}

// ==========================================
// 1. BANNER "SI OREN" (DASHBOARD)
// ==========================================
class SiOrenBanner extends StatefulWidget {
  const SiOrenBanner({super.key});

  @override
  State<SiOrenBanner> createState() => _SiOrenBannerState();
}

class _SiOrenBannerState extends State<SiOrenBanner> {
  bool _isVisible = true; 

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();

    return Dismissible(
      key: const Key('si_oren_banner'),
      direction: DismissDirection.horizontal,
      onDismissed: (direction) {
        setState(() => _isVisible = false);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2E2E3E), Color(0xFF1E1E2C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.volunteer_activism, color: Colors.orangeAccent, size: 20),
                SizedBox(width: 8),
                Text(
                  "Capek sama Iklan Si Oren?",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              "App ini bersih tanpa iklan judi/obat kuat. Support dev biar server tetap ngebut?",
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // TOMBOL NEGATIF (Disamarkan)
                InkWell(
                  onTap: () => setState(() => _isVisible = false),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      "Gak, mending balik ke Si Oren",
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // TOMBOL POSITIF (Menonjol)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purpleAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 5,
                  ),
                  onPressed: () {
                    _launchSaweria();
                  },
                  child: const Text(
                    "Gas Donasi (Tanpa Iklan) 🚀",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 2. DIALOG SARKAS (TRIGGER EVENT)
// ==========================================
void showSarcasticDialog(BuildContext context, {required VoidCallback onProceed}) {
  showDialog(
    context: context,
    barrierDismissible: false, // User harus milih
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(20),
        
        // Header
        title: const Center(
          child: Column(
            children: [
              Icon(Icons.coffee_rounded, size: 40, color: Colors.purpleAccent),
              SizedBox(height: 10),
              Text("Koneksi Lancar Jaya?", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        
        // Body Message
        content: const Text(
          "Cuma mau ngingetin, app ini gratis murni hasil begadang. Mau traktir kopi biar admin makin semangat update?",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        
        // Tombol Aksi
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // TOMBOL UTAMA (HERO) - Ungu/Terang
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purpleAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  shadowColor: Colors.purpleAccent.withOpacity(0.4),
                  elevation: 8,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _launchSaweria();
                  // Beri jeda dikit buat buka browser sebelum lanjut proses (opsional)
                  Future.delayed(const Duration(seconds: 1), onProceed);
                },
                child: const Text(
                  "Traktir Kopi Biar Semangat ☕",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              
              const SizedBox(height: 12),

              // TOMBOL TOLAK (VILLAIN) - Text Only / Grey
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  onProceed(); // Lanjut disconnect
                },
                child: Text(
                  "Skip, saya hobi nonton iklan 30 detik.", // SARKAS LEVEL MAX
                  style: TextStyle(
                    color: Colors.grey[600], 
                    fontSize: 12,
                    fontStyle: FontStyle.italic 
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          )
        ],
      );
    },
  );
}
