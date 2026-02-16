# C Code Bug Audit (10 Temuan)

Audit ini fokus pada source C di `native/tun2socks/`.

1. **Kunci koneksi DNS hanya pakai port sumber (`uint16_t port`)** sehingga beberapa flow berbeda yang kebetulan memakai source port sama akan tertimpa/mix-up.
2. **`insert_connection` tidak memeriksa hasil `malloc`** dan langsung dereference `tmp`, berpotensi crash saat OOM.
3. **`free_connections` melepas node dari tree tanpa `free(con)`**, menyebabkan memory leak saat shutdown/restart path.
4. **Logika rewrite DNS balasan bergantung lookup `dest_port` saja**, sehingga response bisa dipetakan ke flow yang salah saat terjadi port collision.
5. **`connection_send` menulis header SOCKS + alamat + payload ke buffer berukuran `client->udp_mtu`**, padahal ukuran final > payload; berpotensi overflow/corrupt packet.
6. **`BDatagram_RecvAsync_Init` di relay mode memakai `client->udp_mtu`**, padahal parser menerima frame SOCKS UDP dengan overhead (`udpgw_mtu`), berisiko truncation/drop.
7. **`PacketPassInterface_Init` untuk receive juga memakai `client->udp_mtu`**, mismatch lagi dengan frame inbound ber-header SOCKS.
8. **`dgram_handler` hanya log "UDP error" tanpa cleanup/reconnect**; koneksi bermasalah bisa tertinggal dan tidak self-heal.
9. **`connection_free` tidak memanggil `BPending_Free(&o->first_job)`**; jika pending job masih terjadwal, ini berisiko use-after-free.
10. **`o->num_connections` tidak diinisialisasi pada mode relay**; dipakai di `SocksUdpGwClient_SubmitPacket`, sehingga bisa baca nilai sampah.

