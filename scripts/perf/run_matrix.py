#!/usr/bin/env python3
import argparse
import json
import os
import re
import subprocess
import time

SCENARIOS = [
    ("high_pps_small_pkt", ["--threads", "6", "--duration", "15", "--pps", "120000", "--flows", "400", "--fragmentation-mode", "none"]),
    ("fragmented_tcp", ["--threads", "6", "--duration", "15", "--pps", "90000", "--flows", "1200", "--fragmentation-mode", "heavy"]),
    ("concurrent_sessions", ["--threads", "8", "--duration", "15", "--pps", "100000", "--flows", "2000", "--fragmentation-mode", "moderate"]),
    ("rapid_churn", ["--threads", "8", "--duration", "12", "--pps", "130000", "--flows", "2500", "--fragmentation-mode", "none"]),
    ("dns_flood", ["--threads", "6", "--duration", "12", "--pps", "150000", "--flows", "300", "--fragmentation-mode", "none"]),
    ("slow_upstream_sim", ["--threads", "4", "--duration", "12", "--pps", "60000", "--flows", "1000", "--fragmentation-mode", "heavy"]),
    ("mixed_worst_case", ["--threads", "10", "--duration", "20", "--pps", "140000", "--flows", "2200", "--fragmentation-mode", "heavy"]),
]

LINE_PATTERNS = {
    "metric": re.compile(r"METRIC packets=(\d+) bytes=(\d+) drops=(\d+) pps=([0-9.]+) mbps=([0-9.]+)"),
    "lat": re.compile(r"LATENCY_NS p50=(\d+) p95=(\d+) p99=(\d+) p999=(\d+)"),
    "flow": re.compile(r"FLOW tcp=(\d+) udp=(\d+) dns=(\d+) reassembly_bytes=(\d+) event_loop_max_ns=(\d+)"),
    "alloc": re.compile(r"ALLOC alloc_calls=(\d+) free_calls=(\d+) pool_hits=(\d+) pool_misses=(\d+) bytes_heap=(\d+) lock_wait_ns=(\d+)"),
}


def run_one(bin_path, name, args):
    proc = subprocess.run([bin_path] + args, capture_output=True, text=True, check=True)
    out = proc.stdout
    rec = {"scenario": name, "raw": out}
    for k, pat in LINE_PATTERNS.items():
        m = pat.search(out)
        if m:
            rec[k] = [float(x) if "." in x else int(x) for x in m.groups()]
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", default="./build-native/tun2socks_perf_harness")
    ap.add_argument("--out", default="perf_results.json")
    ap.add_argument("--soak-seconds", type=int, default=120)
    args = ap.parse_args()

    results = []
    for name, sc_args in SCENARIOS:
        results.append(run_one(args.bin, name, sc_args))

    # compressed soak in CI/local env; full 24h should be run externally with larger --soak-seconds
    soak_args = ["--threads", "8", "--duration", str(args.soak_seconds), "--pps", "100000", "--flows", "1800", "--fragmentation-mode", "heavy"]
    t0 = time.time()
    results.append(run_one(args.bin, "soak_mixed", soak_args))
    results[-1]["soak_runtime_s"] = time.time() - t0

    with open(args.out, "w") as f:
        json.dump(results, f, indent=2)

    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
