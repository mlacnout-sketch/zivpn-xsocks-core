#ifndef BADVPN_TUN2SOCKS_SMART_PORT_PLANNER_H
#define BADVPN_TUN2SOCKS_SMART_PORT_PLANNER_H

#ifdef __cplusplus
extern "C" {
#endif

int SmartPortPlanner_Select(const char *range_text, int preferred_port, int seed);

#ifdef __cplusplus
}
#endif

#endif
