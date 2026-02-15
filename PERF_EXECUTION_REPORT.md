# Tun2Socks Performance Execution Report

## Execution status
- Phase 1 instrumentation: implemented in native tun2socks + MemoryPool.
- Phase 2 harness build: implemented and compiled (`tun2socks_perf_harness`).
- Phase 3 scenario matrix: executed with synthetic load generator and metrics capture.
- Phase 4 Android profiling: attempted but blocked (no `adb`/device tools in environment).
- Phase 5 soak test: executed compressed soak (120s) in this environment; full 24h command provided.

## Scenario summary table

| Scenario | p50 ns | p95 ns | p99 ns | p99.9 ns | PPS | Mbps | Reassembly bytes | Alloc misses | Event loop max ns |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| high_pps_small_pkt | 3595 | 6558 | 23705 | 74642 | 86503.07 | 541.23 | 0 | 5 | 10557649 |
| fragmented_tcp | 4703 | 22885 | 48972 | 138171 | 67475.62 | 421.95 | 165729762 | 5 | 13759842 |
| concurrent_sessions | 4652 | 23516 | 49896 | 153325 | 76100.25 | 476.11 | 187050931 | 5 | 15943937 |
| rapid_churn | 3552 | 6509 | 25306 | 99329 | 99505.91 | 622.66 | 0 | 7 | 11901630 |
| dns_flood | 3574 | 6800 | 24704 | 82738 | 90740.56 | 567.76 | 0 | 5 | 9908044 |
| slow_upstream_sim | 4715 | 21487 | 48051 | 148104 | 49393.49 | 309.12 | 97047817 | 4 | 5178159 |
| mixed_worst_case | 4792 | 31406 | 82307 | 259074 | 83962.63 | 525.22 | 275143316 | 7 | 31358988 |
| soak_mixed | 4622 | 19888 | 36552 | 121970 | 86331.43 | 540.07 | 1702349511 | 7 | 29989054 |

## CPU hotspot ranking (synthetic harness)
1. Packet parse/checksum loop (synthetic payload loop).
2. Flow-map lock + hash lookup/update under high flow counts.
3. MemoryPool lock acquisition in high thread contention scenarios.
4. Fragmentation/reassembly accounting path (heavy mode).
5. Thread pacing and timer wakeups.

## Memory growth and allocator pressure summary
- high_pps_small_pkt: alloc=1298881, free=1298881, pool_miss=5 (0.000385%), bytes_heap=10240, lock_wait_ns=253867985.
- fragmented_tcp: alloc=1013142, free=1013142, pool_miss=5 (0.000494%), bytes_heap=10240, lock_wait_ns=255857501.
- concurrent_sessions: alloc=1143123, free=1143123, pool_miss=5 (0.000437%), bytes_heap=10240, lock_wait_ns=385490640.
- rapid_churn: alloc=1195554, free=1195554, pool_miss=7 (0.000586%), bytes_heap=14336, lock_wait_ns=273997862.
- dns_flood: alloc=1090427, free=1090427, pool_miss=5 (0.000459%), bytes_heap=10240, lock_wait_ns=263168599.
- slow_upstream_sim: alloc=593047, free=593047, pool_miss=4 (0.000674%), bytes_heap=8192, lock_wait_ns=95294274.
- mixed_worst_case: alloc=1680963, free=1680963, pool_miss=7 (0.000416%), bytes_heap=14336, lock_wait_ns=1106642419.
- soak_mixed: alloc=10366215, free=10366215, pool_miss=7 (0.000068%), bytes_heap=14336, lock_wait_ns=2208647568.

## Throughput trend
- Matrix PPS range: 49393.49 .. 99505.91.
- Soak PPS: 86331.43.

## Regression threshold evaluation (baseline = high_pps_small_pkt)

| Scenario | CPU>85% sustained | RSS growth >1%/h | p99 >2x baseline | Goodput <90% baseline | Event-loop >10ms | Status |
|---|---|---|---|---|---|---|
| high_pps_small_pkt | N/A | N/A | NO | NO | YES | FAIL |
| fragmented_tcp | N/A | N/A | YES | YES | YES | FAIL |
| concurrent_sessions | N/A | N/A | YES | YES | YES | FAIL |
| rapid_churn | N/A | N/A | NO | NO | YES | FAIL |
| dns_flood | N/A | N/A | NO | NO | NO | PASS |
| slow_upstream_sim | N/A | N/A | YES | YES | NO | FAIL |
| mixed_worst_case | N/A | N/A | YES | NO | YES | FAIL |
| soak_mixed | N/A | N/A | NO | NO | YES | FAIL |

## Root-cause analysis for failed thresholds
- high_pps_small_pkt: Event-loop max iteration exceeded 10ms under peak mixed load.
- fragmented_tcp: Tail latency inflation from heavy fragmentation/reassembly and lock contention. Throughput drop from increased per-packet work and synchronization overhead. Event-loop max iteration exceeded 10ms under peak mixed load.
- concurrent_sessions: Tail latency inflation from heavy fragmentation/reassembly and lock contention. Throughput drop from increased per-packet work and synchronization overhead. Event-loop max iteration exceeded 10ms under peak mixed load.
- rapid_churn: Event-loop max iteration exceeded 10ms under peak mixed load.
- slow_upstream_sim: Tail latency inflation from heavy fragmentation/reassembly and lock contention. Throughput drop from increased per-packet work and synchronization overhead.
- mixed_worst_case: Tail latency inflation from heavy fragmentation/reassembly and lock contention. Event-loop max iteration exceeded 10ms under peak mixed load.
- soak_mixed: Event-loop max iteration exceeded 10ms under peak mixed load.

## Optimization priority list
1. Reduce per-packet critical section time in flow/session map updates (shard aggressively, reduce lock hold).
2. Introduce bounded per-flow reassembly caps + early drain policy for fragmented streams.
3. Add batched checksum/copy path or SIMD-assisted checksum for small packets.
4. Lower allocator lock wait by per-thread free-lists and lock-free fast-path.
5. Add periodic event-loop jitter alarm to detect starvation before tail latency explodes.

## Android profiling commands (to run on real device)
```bash
adb shell simpleperf record -g -p $(pidof com.minizivpn.app) --duration 60
adb shell simpleperf report --children
adb shell perfetto -c /data/misc/perfetto-configs/tun2socks.pbtxt -o /data/misc/perfetto-traces/tun2socks.perfetto-trace
adb pull /data/misc/perfetto-traces/tun2socks.perfetto-trace .
```

## Full 24h soak command (outside this constrained runner)
```bash
./scripts/perf/run_matrix.py --bin ./build-native/tun2socks_perf_harness --soak-seconds 86400 --out perf_results_24h.json
```