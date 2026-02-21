# ZiVPN XSocks Core Development - TODO List

## 🛡️ Tahap 1: Keamanan & Stabilitas (Prioritas Tinggi)
- [ ] **Audit Buffer Overflow (Prompt 1.1)**: Analisis mendalam pada file native C/C++ untuk mencegah celah keamanan memori.
- [ ] **Audit Thread Safety (Prompt 1.2)**: Memastikan `AutoPilotService` dan `ZivpnService` bebas dari race conditions.
- [ ] **Logical Bug Analysis (Prompt 1.3)**: Validasi logika reset AutoPilot dan mekanisme deteksi update.

## 💎 Tahap 2: Kualitas Kode & Refactoring
- [ ] **Dart/Flutter Review (Prompt 2.1)**: Optimalisasi widget rebuilds dan kepatuhan prinsip SOLID.
- [ ] **Native C/C++ Review (Prompt 2.2)**: Modernisasi kode C dan standarisasi penanganan error.
- [ ] **Dependency Audit (Prompt 2.3)**: Scan kerentanan pada library pihak ketiga (Shizuku, RxDart, dll).

## 🚀 Tahap 3: Optimasi Performa
- [ ] **Smart Preset V2 Analysis (Prompt 3.1)**: Validasi algoritma tuning RSRP/SINR untuk efisiensi baterai.
- [ ] **Buffer Tuning (Prompt 3.2)**: Analisis efektivitas buffer 64KB pada berbagai skenario kecepatan internet.
- [ ] **Memory & Battery Profiling (Prompt 3.3)**: Deteksi kebocoran memori pada sesi panjang (overnight).

## 📝 Tahap 4: Dokumentasi & Testing
- [ ] **Test Strategy (Prompt 5.1)**: Meningkatkan coverage unit test dan integration test.
- [ ] **Auto-Doc Generation (Prompt 5.2)**: Melengkapi README dan dokumentasi API internal.

---
*Status: In Progress - Menjalankan Audit Keamanan Memori (1.1)*
