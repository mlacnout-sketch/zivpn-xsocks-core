# Rekomendasi Peningkatan Performa (Bahasa C)

Dokumen ini menjadi panduan prioritas untuk peningkatan performa modul native C/C++ (terutama `native/tun2socks`).

## Prioritas utama

1. **Profiling lebih dulu, baru optimasi**
   - Gunakan build profiling (`-g -O2`) lalu ukur hotspot dengan `perf`, `simpleperf` (Android), atau `gprof`.
   - Simpan baseline metrik: throughput (Mbps), latency p50/p95, CPU usage, memory footprint.
2. **Optimasi compiler terukur**
   - Jalur produksi packet processing: `-O3 -DNDEBUG`.
   - Pertimbangkan `-flto` dan validasi benchmark sebelum/sesudah.
   - CPU/ABI tuning harus opsional dan diuji lintas perangkat.
3. **Kurangi alokasi memori di hot path**
   - Hindari `malloc/free` per paket.
   - Reuse buffer atau gunakan pool/ring buffer.
4. **Perbaiki cache locality dan branch behavior**
   - Dekatkan field yang sering diakses.
   - Pisahkan fast-path dari slow-path.
5. **Kurangi syscall/context switch**
   - Batch I/O jika memungkinkan.
   - Hindari logging sinkron pada loop packet forwarding.

## Quick wins untuk `tun2socks`

1. Profil loop utama relay paket + DNS handling.
2. Hilangkan alokasi dinamis berulang per paket.
3. Audit ukuran MTU/buffer untuk menghindari copy tambahan.
4. Pastikan path error tidak memperlambat fast-path.
5. Jalankan benchmark soak test 5–10 menit untuk stabilitas throughput + CPU.

## KPI yang disarankan

- Throughput naik minimal **10–20%**.
- CPU per Mbps turun minimal **10%**.
- p95 latency tidak memburuk (regresi >5% dianggap gagal).
- Memory peak stabil tanpa kebocoran pada soak test.

## Template eksperimen

- **Hipotesis:** contoh "menghapus `malloc/free` per-packet menurunkan CPU 8%".
- **Perubahan:** ringkasan perubahan + lokasi file.
- **Hasil:** data sebelum/sesudah (minimal 3 kali run).
- **Keputusan:** lanjut / rollback.
