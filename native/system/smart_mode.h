#ifndef ZIVPN_SMART_MODE_H
#define ZIVPN_SMART_MODE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SmartModeTuning {
    int tcp_snd_buf;
    int tcp_wnd;
    int socks_buf;
    int udpgw_max_conn;
    int udpgw_buf_size;
    int pdnsd_perm_cache;
    int pdnsd_timeout;
    int pdnsd_verbosity;
} SmartModeTuning;

void smart_mode_get_tuning(int score, SmartModeTuning *out_tuning);

#ifdef __cplusplus
}
#endif

#endif
