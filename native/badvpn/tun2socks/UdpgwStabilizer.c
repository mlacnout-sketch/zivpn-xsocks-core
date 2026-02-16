#include "UdpgwStabilizer.h"

#define UDPGW_STAB_MIN_CONNECTIONS 32
#define UDPGW_STAB_MAX_CONNECTIONS 2048
#define UDPGW_STAB_MIN_BUFFER_PACKETS 8
#define UDPGW_STAB_MAX_BUFFER_PACKETS 96
#define UDPGW_STAB_MIN_UDP_MTU 576
#define UDPGW_STAB_MEMORY_BUDGET_BYTES (16 * 1024 * 1024)

static int clamp_int(int value, int min, int max)
{
    if (value < min) {
        return min;
    }
    if (value > max) {
        return max;
    }
    return value;
}

void UdpgwStabilizer_Compute(
    int udp_mtu,
    int requested_max_connections,
    int requested_buffer_packets,
    int memory_budget_bytes,
    UdpgwStabilizerResult *out
)
{
    int effective_connections;
    int effective_buffer;
    int total_packets_budget;

    if (!out) {
        return;
    }

    out->requested_max_connections = requested_max_connections;
    out->requested_buffer_packets = requested_buffer_packets;
    out->memory_budget_bytes = memory_budget_bytes;

    effective_connections = clamp_int(
        requested_max_connections,
        UDPGW_STAB_MIN_CONNECTIONS,
        UDPGW_STAB_MAX_CONNECTIONS
    );
    effective_buffer = clamp_int(
        requested_buffer_packets,
        UDPGW_STAB_MIN_BUFFER_PACKETS,
        UDPGW_STAB_MAX_BUFFER_PACKETS
    );

    udp_mtu = clamp_int(udp_mtu, UDPGW_STAB_MIN_UDP_MTU, 65535);
    if (memory_budget_bytes <= 0) {
        memory_budget_bytes = UDPGW_STAB_MEMORY_BUDGET_BYTES;
    }
    memory_budget_bytes = clamp_int(memory_budget_bytes, 4 * 1024 * 1024, 128 * 1024 * 1024);
    total_packets_budget = memory_budget_bytes / udp_mtu;
    if (total_packets_budget < UDPGW_STAB_MIN_CONNECTIONS * UDPGW_STAB_MIN_BUFFER_PACKETS) {
        total_packets_budget = UDPGW_STAB_MIN_CONNECTIONS * UDPGW_STAB_MIN_BUFFER_PACKETS;
    }

    if ((long long)effective_connections * effective_buffer > total_packets_budget) {
        int max_connections_by_budget = total_packets_budget / UDPGW_STAB_MIN_BUFFER_PACKETS;
        if (max_connections_by_budget < UDPGW_STAB_MIN_CONNECTIONS) {
            max_connections_by_budget = UDPGW_STAB_MIN_CONNECTIONS;
        }

        if (effective_connections > max_connections_by_budget) {
            effective_connections = max_connections_by_budget;
        }

        if (effective_connections > 0) {
            int max_buffer_by_budget = total_packets_budget / effective_connections;
            if (max_buffer_by_budget < UDPGW_STAB_MIN_BUFFER_PACKETS) {
                max_buffer_by_budget = UDPGW_STAB_MIN_BUFFER_PACKETS;
            }
            if (effective_buffer > max_buffer_by_budget) {
                effective_buffer = max_buffer_by_budget;
            }
        }
    }

    out->effective_max_connections = effective_connections;
    out->effective_buffer_packets = effective_buffer;
    out->estimated_buffer_bytes = effective_connections * effective_buffer * udp_mtu;
    out->changed = (
        out->effective_max_connections != out->requested_max_connections ||
        out->effective_buffer_packets != out->requested_buffer_packets
    );
}
