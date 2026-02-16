#include "SmartPortPlanner.h"

#include <stdio.h>

static int clamp_int(int v, int lo, int hi)
{
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

int SmartPortPlanner_Select(const char *range_text, int preferred_port, int seed)
{
    int start_port, end_port;
    int width;
    int offset;

    preferred_port = clamp_int(preferred_port, 1024, 65535);
    if (!range_text || sscanf(range_text, "%d-%d", &start_port, &end_port) != 2) {
        return preferred_port;
    }

    start_port = clamp_int(start_port, 1024, 65535);
    end_port = clamp_int(end_port, 1024, 65535);
    if (start_port > end_port) {
        int tmp = start_port;
        start_port = end_port;
        end_port = tmp;
    }

    if (preferred_port < start_port || preferred_port > end_port) {
        preferred_port = start_port + (end_port - start_port) / 2;
    }

    width = end_port - start_port + 1;
    if (width <= 1) {
        return start_port;
    }

    offset = seed % width;
    if (offset < 0) offset += width;

    return start_port + ((preferred_port - start_port + offset) % width);
}
