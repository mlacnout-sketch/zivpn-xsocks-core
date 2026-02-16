# C Code Bug Audit (10 Temuan) + Status

Audit fokus pada `native/tun2socks/`.

## Status ringkas
- ✅ Sudah diperbaiki pada patch native terbaru: 1, 2, 3, 4, 5, 6, 7, 9, 10.
- ⚠️ Butuh validasi runtime lebih lanjut: 8 (strategi recovery setelah UDP error sekarang cleanup koneksi, namun perlu uji pada device untuk memastikan perilaku reconnect sesuai ekspektasi operasi).

## Daftar temuan
1. ✅ Kunci koneksi DNS sebelumnya hanya pakai port sumber (`uint16_t port`) sehingga flow berbeda bisa tertimpa.
2. ✅ `insert_connection` sebelumnya tidak memeriksa hasil `malloc`.
3. ✅ `free_connections` sebelumnya melepas node tree tanpa `free(con)`.
4. ✅ Rewrite DNS balasan sebelumnya lookup hanya via `dest_port`.
5. ✅ `connection_send` berpotensi menulis frame melebihi ukuran buffer efektif.
6. ✅ `BDatagram_RecvAsync_Init` relay sebelumnya memakai `udp_mtu` alih-alih framed `udpgw_mtu`.
7. ✅ `PacketPassInterface_Init` receive sebelumnya juga mismatch ukuran MTU.
8. ⚠️ `dgram_handler` error-path perlu diverifikasi runtime (sekarang sudah cleanup koneksi).
9. ✅ `connection_free` sebelumnya tidak melepas `first_job` dan payload deferred.
10. ✅ `num_connections` relay sebelumnya tidak diinisialisasi eksplisit.
