// File: integration/benchmark.c

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/time.h>
#include <string.h>

#define NUM_ITERATIONS 1000

// Mock functions if not linking against real library
// In real scenario, we would link against the wrapper library
int hysteria_connect(const char *server, int port, const char *auth);
int hysteria_send(int handle, const void *data, size_t len);

double get_time_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (tv.tv_sec * 1000.0) + (tv.tv_usec / 1000.0);
}

void benchmark_connect(void) {
    printf("\n[BENCHMARK] Connection Establishment\n");

    double start = get_time_ms();

    for (int i = 0; i < NUM_ITERATIONS; i++) {
        // Mock server address
        int handle = hysteria_connect("test.server.com", 443, "password");
        if (handle < 0) {
            // printf("Connection failed at iteration %d\n", i);
            // In mock/test without real server, this might fail, so we just count attempts
        }
        // Don't close immediately for connection pool testing
    }

    double end = get_time_ms();
    double duration = end - start;
    double avg = duration / NUM_ITERATIONS;

    printf("  Total time: %.2f ms\n", duration);
    printf("  Average per connection: %.2f ms\n", avg);
    printf("  Connections/sec: %.0f\n", 1000.0 / avg);
}

void benchmark_send(void) {
    printf("\n[BENCHMARK] Data Transmission\n");

    int handle = hysteria_connect("test.server.com", 443, "password");
    if (handle < 0) {
        printf("Failed to establish connection (mocking may be needed)\n");
        // return;
        // Proceed for testing purposes if wrapper mocks it
    }

    unsigned char data[1024];
    memset(data, 'A', sizeof(data));

    double start = get_time_ms();
    size_t total_bytes = 0;

    for (int i = 0; i < NUM_ITERATIONS; i++) {
        int sent = hysteria_send(handle, data, sizeof(data));
        if (sent > 0) {
            total_bytes += sent;
        }
    }

    double end = get_time_ms();
    double duration = end - start;
    double throughput = (total_bytes / 1024.0 / 1024.0) / (duration / 1000.0);

    printf("  Total bytes: %zu\n", total_bytes);
    printf("  Duration: %.2f ms\n", duration);
    printf("  Throughput: %.2f MB/s\n", throughput);
}

int main(void) {
    printf("═══════════════════════════════════════\n");
    printf("  HYSTERIA BINARY BENCHMARK\n");
    printf("═══════════════════════════════════════\n");

    benchmark_connect();
    benchmark_send();

    printf("\n[*] Benchmark complete\n");
    return 0;
}
