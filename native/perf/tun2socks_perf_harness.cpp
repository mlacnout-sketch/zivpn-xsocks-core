#include <algorithm>
#include <atomic>
#include <chrono>
#include <cinttypes>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <random>
#include <thread>
#include <unordered_map>
#include <vector>

extern "C" {
#include "../badvpn/tun2socks/MemoryPool.h"
}

struct FlowState {
    uint32_t expected_seq{0};
    uint64_t reassembly_bytes{0};
    uint64_t packets{0};
};

struct Metrics {
    std::atomic<uint64_t> packets{0};
    std::atomic<uint64_t> bytes{0};
    std::atomic<uint64_t> drops{0};
    std::atomic<uint64_t> dns_packets{0};
    std::atomic<uint64_t> udp_packets{0};
    std::atomic<uint64_t> tcp_packets{0};
    std::atomic<uint64_t> alloc_ops{0};
    std::atomic<uint64_t> free_ops{0};
    std::atomic<uint64_t> event_loop_max_ns{0};
    std::atomic<uint64_t> flow_reassembly_bytes{0};
};

struct LatencyHistogram {
    std::mutex m;
    std::vector<uint64_t> samples_ns;
    std::atomic<uint64_t> sample_counter{0};
    void add(uint64_t ns) {
        uint64_t c = sample_counter.fetch_add(1, std::memory_order_relaxed);
        if ((c & 0x3F) != 0) return; // 1/64 sampling to keep overhead and memory bounded
        std::lock_guard<std::mutex> lk(m);
        samples_ns.push_back(ns);
    }
};

static inline uint64_t now_ns() {
    using namespace std::chrono;
    return duration_cast<nanoseconds>(steady_clock::now().time_since_epoch()).count();
}

struct Args {
    int threads{4};
    int duration{20};
    int pps{100000};
    int flows{1000};
    std::string fragmentation_mode{"none"};
};

static Args parse_args(int argc, char** argv) {
    Args a;
    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--threads") && i + 1 < argc) a.threads = std::atoi(argv[++i]);
        else if (!strcmp(argv[i], "--duration") && i + 1 < argc) a.duration = std::atoi(argv[++i]);
        else if (!strcmp(argv[i], "--pps") && i + 1 < argc) a.pps = std::atoi(argv[++i]);
        else if (!strcmp(argv[i], "--flows") && i + 1 < argc) a.flows = std::atoi(argv[++i]);
        else if (!strcmp(argv[i], "--fragmentation-mode") && i + 1 < argc) a.fragmentation_mode = argv[++i];
    }
    return a;
}

int main(int argc, char** argv) {
    const Args args = parse_args(argc, argv);
    MemoryPool pool;
    pool_init(&pool, 2048);
    pool_reset_stats();

    Metrics m;
    LatencyHistogram hist;

    constexpr int kShards = 16;
    std::unordered_map<uint32_t, FlowState> flow_maps[kShards];
    std::mutex flow_locks[kShards];

    std::atomic<bool> running{true};
    const uint64_t start_ns = now_ns();

    auto worker = [&](int tid) {
        std::mt19937_64 rng(0xC0FFEE + tid * 131);
        std::uniform_int_distribution<uint32_t> flow_dist(1, std::max(2, args.flows));
        std::uniform_int_distribution<int> packet_size_dist(64, 1500);
        std::uniform_int_distribution<int> proto_dist(0, 99);
        std::uniform_int_distribution<int> frag_dist(0, 99);

        const double per_thread_pps = (double)args.pps / std::max(1, args.threads);
        const uint64_t target_gap_ns = (uint64_t)(1e9 / std::max(1.0, per_thread_pps));
        uint64_t next_tick = now_ns();

        while (running.load(std::memory_order_relaxed)) {
            const uint64_t loop_start = now_ns();

            uint32_t flow = flow_dist(rng);
            int pkt_size = packet_size_dist(rng);
            int proto = proto_dist(rng); // 0..59 TCP, 60..89 UDP, 90..99 DNS
            bool fragmented = (args.fragmentation_mode != "none") && (frag_dist(rng) < 35);

            void* buf = pool_alloc(&pool);
            if (!buf) {
                m.drops.fetch_add(1);
                continue;
            }
            m.alloc_ops.fetch_add(1);

            // Synthetic packet parsing/reassembly cost model.
            if (proto < 60) {
                m.tcp_packets.fetch_add(1);
                int shard = flow % kShards;
                {
                    std::lock_guard<std::mutex> lk(flow_locks[shard]);
                    auto &fs = flow_maps[shard][flow];
                    fs.packets++;
                    if (fragmented) {
                        fs.reassembly_bytes += pkt_size;
                        m.flow_reassembly_bytes.fetch_add(pkt_size);
                    } else if (fs.reassembly_bytes > 0) {
                        uint64_t drain = std::min<uint64_t>(fs.reassembly_bytes, (uint64_t)pkt_size);
                        fs.reassembly_bytes -= drain;
                    }
                    fs.expected_seq += (uint32_t)pkt_size;
                }
            } else if (proto < 90) {
                m.udp_packets.fetch_add(1);
            } else {
                m.dns_packets.fetch_add(1);
            }

            // Simulate copy/checksum overhead to expose allocation/cpu scaling.
            volatile uint64_t checksum = 0;
            uint8_t *b = reinterpret_cast<uint8_t*>(buf);
            int loops = fragmented ? 4 : 1;
            for (int l = 0; l < loops; ++l) {
                for (int i = 0; i < pkt_size; ++i) {
                    checksum += (uint64_t)((i + l + tid) & 0xFF);
                    b[i % 2048] = (uint8_t)checksum;
                }
            }

            pool_free(&pool, buf);
            m.free_ops.fetch_add(1);

            m.packets.fetch_add(1);
            m.bytes.fetch_add((uint64_t)pkt_size);
            hist.add(now_ns() - loop_start);

            const uint64_t elapsed = now_ns() - loop_start;
            uint64_t prev = m.event_loop_max_ns.load();
            while (elapsed > prev && !m.event_loop_max_ns.compare_exchange_weak(prev, elapsed)) {}

            next_tick += target_gap_ns;
            uint64_t now = now_ns();
            if (next_tick > now) {
                std::this_thread::sleep_for(std::chrono::nanoseconds(next_tick - now));
            } else {
                // behind schedule, drop pacing to recover
                next_tick = now;
            }
        }
    };

    std::vector<std::thread> threads;
    for (int i = 0; i < args.threads; ++i) {
        threads.emplace_back(worker, i);
    }

    std::this_thread::sleep_for(std::chrono::seconds(args.duration));
    running.store(false);
    for (auto &t : threads) t.join();

    MemoryPoolStats ps{};
    pool_get_stats(&ps);
    pool_free_all(&pool);

    std::vector<uint64_t> lat;
    {
        std::lock_guard<std::mutex> lk(hist.m);
        lat = std::move(hist.samples_ns);
    }
    if (lat.empty()) {
        std::puts("No samples captured");
        return 1;
    }
    std::sort(lat.begin(), lat.end());
    auto pct = [&](double p) -> uint64_t {
        size_t idx = (size_t)(p * (lat.size() - 1));
        return lat[idx];
    };

    const double elapsed_s = (now_ns() - start_ns) / 1e9;
    const double pps = m.packets.load() / elapsed_s;
    const double mbps = (m.bytes.load() * 8.0) / (elapsed_s * 1e6);

    std::printf("RESULT threads=%d duration=%d pps_target=%d flows=%d frag=%s\n",
                args.threads, args.duration, args.pps, args.flows, args.fragmentation_mode.c_str());
    std::printf("METRIC packets=%" PRIu64 " bytes=%" PRIu64 " drops=%" PRIu64 " pps=%.2f mbps=%.2f\n",
                m.packets.load(), m.bytes.load(), m.drops.load(), pps, mbps);
    std::printf("LATENCY_NS p50=%" PRIu64 " p95=%" PRIu64 " p99=%" PRIu64 " p999=%" PRIu64 "\n",
                pct(0.50), pct(0.95), pct(0.99), pct(0.999));
    std::printf("FLOW tcp=%" PRIu64 " udp=%" PRIu64 " dns=%" PRIu64 " reassembly_bytes=%" PRIu64 " event_loop_max_ns=%" PRIu64 "\n",
                m.tcp_packets.load(), m.udp_packets.load(), m.dns_packets.load(),
                m.flow_reassembly_bytes.load(), m.event_loop_max_ns.load());
    std::printf("ALLOC alloc_calls=%llu free_calls=%llu pool_hits=%llu pool_misses=%llu bytes_heap=%llu lock_wait_ns=%llu\n",
                ps.alloc_calls, ps.free_calls, ps.pool_hits, ps.pool_misses, ps.bytes_from_heap, ps.lock_wait_ns);

    return 0;
}
