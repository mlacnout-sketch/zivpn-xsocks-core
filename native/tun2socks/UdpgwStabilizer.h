#ifndef BADVPN_TUN2SOCKS_UDPGW_STABILIZER_H
#define BADVPN_TUN2SOCKS_UDPGW_STABILIZER_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int requested_max_connections;
    int requested_buffer_packets;
    int memory_budget_bytes;
    int effective_max_connections;
    int effective_buffer_packets;
    int estimated_buffer_bytes;
    int changed;
} UdpgwStabilizerResult;

void UdpgwStabilizer_Compute(
    int udp_mtu,
    int requested_max_connections,
    int requested_buffer_packets,
    int memory_budget_bytes,
    UdpgwStabilizerResult *out
);

#ifdef __cplusplus
}
#endif

#endif
