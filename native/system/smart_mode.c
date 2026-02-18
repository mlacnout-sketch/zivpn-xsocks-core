#include "smart_mode.h"

static SmartModeTuning throughput_tuning(void) {
    SmartModeTuning tuning;
    tuning.tcp_snd_buf = 65535;
    tuning.tcp_wnd = 65535;
    tuning.socks_buf = 131072;
    tuning.udpgw_max_conn = 1024;
    tuning.udpgw_buf_size = 64;
    tuning.pdnsd_perm_cache = 4096;
    tuning.pdnsd_timeout = 8;
    tuning.pdnsd_verbosity = 1;
    return tuning;
}

static SmartModeTuning balanced_tuning(void) {
    SmartModeTuning tuning;
    tuning.tcp_snd_buf = 65535;
    tuning.tcp_wnd = 65535;
    tuning.socks_buf = 65536;
    tuning.udpgw_max_conn = 512;
    tuning.udpgw_buf_size = 32;
    tuning.pdnsd_perm_cache = 2048;
    tuning.pdnsd_timeout = 10;
    tuning.pdnsd_verbosity = 2;
    return tuning;
}

static SmartModeTuning latency_tuning(void) {
    SmartModeTuning tuning;
    tuning.tcp_snd_buf = 32768;
    tuning.tcp_wnd = 32768;
    tuning.socks_buf = 65536;
    tuning.udpgw_max_conn = 256;
    tuning.udpgw_buf_size = 16;
    tuning.pdnsd_perm_cache = 2048;
    tuning.pdnsd_timeout = 5;
    tuning.pdnsd_verbosity = 1;
    return tuning;
}

void smart_mode_get_tuning(int score, SmartModeTuning *out_tuning) {
    if (!out_tuning) {
        return;
    }

    if (score >= 75) {
        *out_tuning = throughput_tuning();
    } else if (score >= 45) {
        *out_tuning = balanced_tuning();
    } else if (score >= 0) {
        *out_tuning = latency_tuning();
    } else {
        // Missing/invalid probe score: default to balanced profile.
        *out_tuning = balanced_tuning();
    }
}
