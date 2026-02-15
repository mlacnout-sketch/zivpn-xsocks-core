# Tun2Socks Performance Fuzzing & Stress Testing Strategy (Android NDK)

This document is a **performance-stability test design** for the native tun2socks pipeline on Android.
It intentionally focuses on CPU, memory, latency, throughput, event-loop behavior, lock contention, and allocator pressure under hostile/high-load traffic.

---

## 1) Performance test architecture

### 1.1 Test layers

1. **Micro-bench layer (native unit/harness)**
   - Target: packet parse, TCP reassembly paths, buffer operations, session lookup, allocator hot paths.
   - Binary: host Linux + Android NDK test binary.

2. **Component load layer (tun2socks + synthetic peers)**
   - Target: end-to-end packet ingress/egress behavior, reactor responsiveness, per-flow fairness.
   - Runs `libtun2socks.so` with controlled traffic generators.

3. **System stress layer (on-device Android)**
   - Target: realistic CPU scheduler effects, thermal throttling, memory pressure, syscall patterns.
   - Tooling: `simpleperf`, `perfetto`, heapprofd, statsd exports.

4. **Soak layer (24h+)**
   - Target: memory growth, fragmentation, throughput drift, latency tail degradation, timer jitter.

### 1.2 Data plane under test (hot paths)

Primary first-party code paths to instrument and stress:

- **Ingress packet path**
  - `device_read_handler_send` and packet handoff to lwIP (`pbuf_alloc`, `pbuf_take`, `ip_input`).
  - File: `native/badvpn/tun2socks/tun2socks.c`.

- **DNS rewrite path**
  - `process_device_dns_packet` (per-packet checksums, header rewrites, connection lookup for transparent DNS).
  - File: `native/badvpn/tun2socks/tun2socks.c`.

- **UDP forwarding path**
  - `process_device_udp_packet` + `SocksUdpGwClient` send/receive.
  - Files: `native/badvpn/tun2socks/tun2socks.c`, `native/badvpn/tun2socks/SocksUdpGwClient.c`.

- **TCP session path**
  - accept/recv/send callbacks (`listener_accept_func`, `client_recv_func`, `client_send_to_socks`, `client_socks_recv_send_out`, `client_sent_func`).
  - File: `native/badvpn/tun2socks/tun2socks.c`.

- **Session tracking / lookup**
  - BAVL tree lookup/insert/remove for transparent DNS connection mapping.
  - File: `native/badvpn/tun2socks/tun2socks.c`.

- **Allocator path**
  - memory pools + fallback malloc/free (`pool_alloc`, `pool_free`, `pool_free_all`).
  - File: `native/badvpn/tun2socks/MemoryPool.c`.

- **UDPGW server path (if deployed)**
  - per-client/per-connection queueing and tree lookups.
  - File: `native/badvpn/udpgw/udpgw.c`.

---

## 2) Performance-sensitive risks to explicitly detect

### 2.1 Algorithmic / loop risks
- O(n²) behavior in packet loops (e.g., repeated scans over variable-length buffers or linked structures).
- Cost explosion with out-of-order TCP segments and retransmissions.
- Excessive per-packet checksum recomputation and repeated parsing.

### 2.2 Memory behavior risks
- TCP reassembly buffer growth under delayed ACK / out-of-order streams.
- Memory pool fallback to heap under bursty allocation patterns.
- Fragmentation from frequent alloc/free churn in session churn scenarios.

### 2.3 Latency and scheduling risks
- Reactor/event-loop blocking by heavy packet callback work.
- Timer drift in `tcp_tmr` scheduling under high CPU load.
- Elevated syscall frequency increasing context-switch overhead.

### 2.4 Concurrency/locking risks
- Contention in shared session maps/queues if multithreaded regions are enabled.
- Cross-thread handoff bottlenecks (queue pressure, wakeups).

---

## 3) Synthetic traffic generator design

### 3.1 Generator topology

Use a dedicated load generator host (or second device) connected over ADB reverse/forward or LAN:

- **Packet generator**: DPDK/TRex/moongen (preferred) or Linux raw socket replay.
- **TCP flow generator**: custom asyncio/libuv tool or `wrk`/`h2load` for stream pressure.
- **DNS flooder**: custom UDP query emitter with randomized IDs/domains.
- **Slow upstream emulator**: tc/netem-based impairment proxy.

### 3.2 Traffic profiles

1. **High packet rate profile**
   - Target: 100k–300k packets/sec synthetic ingress.
   - Mix: 64B/128B/256B packets to maximize per-packet overhead.

2. **Large fragmented TCP streams**
   - Many MB per flow split into tiny segments.
   - Forced out-of-order + retransmit ratio 5–20%.

3. **Concurrent TCP sessions**
   - 1k+ concurrent connections (ramp 100 -> 500 -> 1k -> 2k).
   - Steady send/recv + random half-close/full-close.

4. **Rapid open/close churn**
   - 2k–20k conn/min with short lifetimes.
   - Detect allocator/session bookkeeping overhead.

5. **DNS flood**
   - 50k–200k qps mix of valid/invalid domains.
   - Exercise `process_device_dns_packet` and mapping table pressure.

6. **Slow upstream**
   - RTT 200–2000ms, 1–10% loss, reordering 5–30%.
   - Observe reassembly growth and backpressure behavior.

7. **Small-packet worst-case flood**
   - 64-byte packets, high PPS, highly fragmented streams.
   - Maximizes header parsing/copying overhead.

---

## 4) Benchmark harness (C++) example

Below is a lightweight **native performance harness skeleton** for Android/NDK builds.
It simulates packet processing calls, tracks latency histogram, allocation deltas, and throughput.

```cpp
// perf_harness.cpp
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <thread>
#include <vector>

struct Metrics {
    std::atomic<uint64_t> packets{0};
    std::atomic<uint64_t> bytes{0};
    std::atomic<uint64_t> drops{0};
    std::atomic<uint64_t> alloc_calls{0};
    std::atomic<uint64_t> free_calls{0};
    std::atomic<uint64_t> p50_ns{0}, p95_ns{0}, p99_ns{0};
};

static inline uint64_t now_ns() {
    using namespace std::chrono;
    return duration_cast<nanoseconds>(steady_clock::now().time_since_epoch()).count();
}

// Replace this with actual packet ingress function wrapper.
extern "C" int tun2socks_ingress_packet(const uint8_t* data, int len);

int main() {
    Metrics m;
    constexpr int kPacketSize = 128;
    constexpr int kThreads = 4;
    constexpr int kDurationSec = 60;

    std::vector<uint8_t> pkt(kPacketSize, 0xAB);
    std::atomic<bool> run{true};

    auto worker = [&]() {
        std::vector<uint64_t> samples;
        samples.reserve(1 << 20);

        while (run.load(std::memory_order_relaxed)) {
            const uint64_t t0 = now_ns();
            int rc = tun2socks_ingress_packet(pkt.data(), kPacketSize);
            const uint64_t dt = now_ns() - t0;

            if (rc == 0) {
                m.packets.fetch_add(1, std::memory_order_relaxed);
                m.bytes.fetch_add(kPacketSize, std::memory_order_relaxed);
                samples.push_back(dt);
            } else {
                m.drops.fetch_add(1, std::memory_order_relaxed);
            }
        }

        if (!samples.empty()) {
            std::sort(samples.begin(), samples.end());
            auto pct = [&](double p){ return samples[(size_t)(p * (samples.size()-1))]; };
            m.p50_ns.store(pct(0.50));
            m.p95_ns.store(pct(0.95));
            m.p99_ns.store(pct(0.99));
        }
    };

    std::vector<std::thread> threads;
    for (int i = 0; i < kThreads; i++) threads.emplace_back(worker);

    const uint64_t start = now_ns();
    std::this_thread::sleep_for(std::chrono::seconds(kDurationSec));
    run.store(false);
    for (auto &t : threads) t.join();

    const double elapsed_s = (now_ns() - start) / 1e9;
    const double pps = m.packets.load() / elapsed_s;
    const double mbps = (m.bytes.load() * 8.0) / (elapsed_s * 1e6);

    std::printf("packets=%llu drops=%llu pps=%.2f mbps=%.2f\n",
        (unsigned long long)m.packets.load(),
        (unsigned long long)m.drops.load(), pps, mbps);
    std::printf("latency(ns): p50=%llu p95=%llu p99=%llu\n",
        (unsigned long long)m.p50_ns.load(),
        (unsigned long long)m.p95_ns.load(),
        (unsigned long long)m.p99_ns.load());

    return 0;
}
```

---

## 5) Throughput, latency, memory, and CPU measurement methods

### 5.1 Throughput method
- Measure at three points:
  1. **Ingress PPS/BPS** before tun2socks API boundary.
  2. **Post-forward PPS/BPS** after socks/udpgw egress.
  3. **Goodput** (payload-only, excludes overhead).
- Report: avg, p50, p95, p99 over 10s windows + full-test aggregate.

### 5.2 Latency tracking instrumentation
- Add per-stage timestamps (ns):
  - packet receive
  - parse complete
  - session lookup complete
  - queue enqueue/dequeue
  - socket write complete
- Emit stage delta histograms to ring buffer and flush every second.
- Track **tail latency** (p99/p99.9), not just averages.

### 5.3 Memory profiling integration
- Integrate allocation counters in pool + heap wrappers:
  - alloc count/free count
  - bytes in-use
  - peak in-use
  - fallback-to-malloc count
- On Android use:
  - **heapprofd** (Perfetto heap profiler)
  - `/proc/<pid>/smaps_rollup` sampling every 5s (RSS/PSS)
  - optional jemalloc stats if allocator supports it.

### 5.4 CPU profiling strategy
- Use **simpleperf** sampling + call graph:
  - `simpleperf record -g --app <pkg> --duration 60`
  - `simpleperf report --children`
- Correlate with Perfetto scheduling trace to detect reactor stalls.
- Generate flamegraphs from simpleperf stack samples for hotspot ranking.

---

## 6) Android-compatible profiling workflow

### 6.1 simpleperf
1. Build with frame pointers (`-fno-omit-frame-pointer`) for better stacks.
2. Run stress profile.
3. Collect:
   - CPU hotspots by function
   - cycles/instructions/cache-miss (if available)
   - per-thread CPU time.

### 6.2 Perfetto
- Trace categories: sched, freq, binder, memory, heapprofd, userspace counters.
- Add custom counters for:
  - queue depth
  - active sessions
  - reassembly bytes
  - event-loop iteration duration.

### 6.3 Heap profiler (heapprofd)
- Enable native heap sampling in Perfetto config.
- Capture allocation flame chart during:
  - connection churn
  - fragmented TCP scenario
  - DNS flood.

### 6.4 Flamegraph generation
- Export simpleperf data -> folded stacks -> flamegraph SVG.
- Keep baseline flamegraph per release tag for regression diffing.

---

## 7) Scenario matrix (must-run)

| Scenario | Duration | Key Load | Primary KPIs |
|---|---:|---|---|
| S1 High PPS small packets | 20 min | 100k+ pps @ 64B | CPU%, p99 latency, drops |
| S2 Fragmented TCP | 30 min | 1k flows, out-of-order/retransmit | reassembly bytes, p99.9 latency |
| S3 Concurrent sessions | 30 min | 1k–2k live TCP sessions | lookup cost, memory/session |
| S4 Conn churn | 20 min | rapid open/close | alloc/sec, free/sec, lock wait |
| S5 DNS flood | 20 min | 50k–200k qps | DNS path CPU, lookup latency |
| S6 Slow upstream | 30 min | RTT/loss/reorder | buffer growth, throughput collapse |
| S7 Mixed worst-case | 60 min | all above combined | stability, no runaway memory |

---

## 8) Regression thresholds (initial guardrails)

Set release gates (fail CI/perf job if violated):

- **CPU spike**: no sustained core >85% for >5 min in S1/S7.
- **Memory growth**: RSS slope < 1%/hour after warm-up (30 min).
- **Latency**:
  - p99 ingress->egress < 2x baseline.
  - p99.9 not exceeding 5x baseline.
- **Throughput**:
  - goodput >= 90% of baseline in S1; >= 80% in S7.
- **Event loop blocking**:
  - reactor iteration >10ms occurs <0.1% of ticks.
- **Allocator pressure**:
  - fallback mallocs from pools < 2% in steady state.
- **Session lookup**:
  - median lookup time stable with ≤20% increase from 1k to 2k sessions.

---

## 9) Long-run soak strategy (24h)

### 9.1 Soak phases
1. **Warm-up** (30 min): steady mixed traffic.
2. **Main soak** (22h): cyclical profile every 30 min:
   - 10 min high PPS
   - 10 min fragmented TCP
   - 5 min DNS flood
   - 5 min churn.
3. **Cool-down** (90 min): medium load to expose delayed cleanup issues.

### 9.2 What to log every 5s
- RSS/PSS, native heap in-use, pool usage.
- packets/sec, drops/sec, goodput Mbps.
- p50/p95/p99/p99.9 latency.
- active sessions, TCP reassembly bytes/segments.
- reactor max loop duration, queue depths.
- syscalls/sec and context switches/sec.

### 9.3 Soak pass criteria
- No monotonic memory growth after hour 2.
- No throughput drift >10% over last 6h.
- No tail-latency blowups (>2x baseline) persisting >10 min.
- No crash, deadlock, event-loop starvation.

---

## 10) Bottleneck diagnosis playbook (when thresholds fail)

### 10.1 TCP reassembly buffer growth
- Check per-flow reassembly bytes and segment counts.
- Add hard caps + eviction/backpressure strategy.
- Coalesce adjacent segments to reduce metadata overhead.

### 10.2 Retransmission / out-of-order cost
- Measure duplicate segment drop fast-path hit rate.
- Cache sequence-window decisions per flow.
- Avoid repeated checksum/parsing for duplicate payloads.

### 10.3 Hash/BAVL session tracking cost
- Profile lookup/insert/remove nanoseconds by active-session bucket.
- If scaling bends superlinearly, test hash-map with pre-sized buckets.
- Introduce slab allocation for session structs.

### 10.4 Per-packet allocations and resizing
- Identify call sites with alloc/free inside packet callbacks.
- Replace repeated `malloc/free` with object pools/ring buffers.
- Pre-size vectors/buffers for expected burst envelopes.

### 10.5 Excessive copying
- Count bytes copied per packet path stage.
- Replace copy chains with iovec/scatter-gather where possible.
- Avoid `pbuf_take`-style full-copy when zero-copy path is viable.

### 10.6 Lock contention
- Add lock wait-time counters around hot mutexes.
- Reduce lock granularity; prefer sharded session maps.
- Shift heavy work out of locked regions.

### 10.7 Syscall frequency
- Batch writes/reads where feasible.
- Reuse sockets and buffers to reduce kernel crossings.
- Validate epoll/reactor wakeup rates for busy loops.

---

## 11) Metrics dashboard plan

Use Grafana (or Perfetto + CSV post-processing) with panels:

1. **Traffic**: ingress/egress PPS, Mbps, drop rate.
2. **Latency**: p50/p95/p99/p99.9 end-to-end + per-stage.
3. **Memory**: RSS/PSS, heap in-use, pool occupancy, alloc/free rate.
4. **CPU**: total + per-thread CPU, context switches, scheduling delays.
5. **TCP internals**: active sessions, reassembly bytes, retransmit handling rate.
6. **Event-loop**: loop iteration time histogram, queue depth, timer drift.
7. **Regression scorecard**: pass/fail against thresholds.

---

## 12) Practical implementation checklist

- [ ] Add low-overhead counters/timers around ingress, parse, lookup, enqueue, egress.
- [ ] Wrap pool + heap allocation paths with stats hooks.
- [ ] Add per-scenario driver scripts (adb + traffic generator orchestration).
- [ ] Export metrics in Prometheus text format or CSV for CI artifacts.
- [ ] Add perf regression CI job (nightly) + 24h soak weekly job.
- [ ] Store baseline flamegraphs and KPI snapshots per release.

---

## 13) Notes specific to this repository

Given the current code layout, prioritize instrumentation in:

- `native/badvpn/tun2socks/tun2socks.c` (device read path, DNS/UDP rewrite, TCP callbacks, reactor timer).
- `native/badvpn/tun2socks/SocksUdpGwClient.c` (UDPGW forwarding and buffering behavior).
- `native/badvpn/tun2socks/MemoryPool.c` (pool hit/miss and fallback heap cost).
- `native/badvpn/udpgw/udpgw.c` (queue/tree behavior under client/connection storms).

This gives highest signal for CPU spikes, memory growth, latency regressions, throughput collapse, and event-loop blocking under extreme traffic.
