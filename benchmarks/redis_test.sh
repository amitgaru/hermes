#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────
REDIS_IMAGE="redis:latest"
SPEEDBUMP_IMAGE="kffl/speedbump:latest"
HERMES_IMAGE="xillar/hermes:latest"
REDIS_PORT=6379
SPEEDBUMP_PORT=6380
HERMES_PORT=6381
NETWORK="bench-net"

REDIS_CONTAINER="bench-redis"
SPEEDBUMP_CONTAINER="bench-speedbump"
HERMES_CONTAINER="bench-hermes"

REDIS_BENCH_ARGS="-n 1000 -c 50 --csv"
TESTS="SET GET INCR LPUSH LPOP SADD SPOP MSET"

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────
log()  { echo -e "\n\033[1;34m[$(date '+%H:%M:%S')] >>> $*\033[0m"; }
ok()   { echo -e "\033[1;32m[OK] $*\033[0m"; }
err()  { echo -e "\033[1;31m[ERR] $*\033[0m" >&2; }
hr()   { printf '%0.s─' {1..60}; echo; }

cleanup() {
    log "Cleaning up containers and network..."
    docker rm -f "$REDIS_CONTAINER" "$SPEEDBUMP_CONTAINER" "$HERMES_CONTAINER" 2>/dev/null || true
    docker network rm "$NETWORK" 2>/dev/null || true
    ok "Cleanup done."
}
trap cleanup EXIT

# ─────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────
log "Pulling images..."
docker pull "$REDIS_IMAGE"
docker pull "$SPEEDBUMP_IMAGE"
docker pull "$HERMES_IMAGE"

log "Creating isolated Docker network: $NETWORK"
docker network create "$NETWORK" 2>/dev/null || true

# ─────────────────────────────────────────────
# Start Redis (shared backend for both proxies)
# ─────────────────────────────────────────────
log "Starting Redis backend..."
docker run -d --rm \
    --name "$REDIS_CONTAINER" \
    --network "$NETWORK" \
    "$REDIS_IMAGE"
sleep 1
ok "Redis ($REDIS_CONTAINER) up on port $REDIS_PORT"

# ─────────────────────────────────────────────
# Run benchmark function
# ─────────────────────────────────────────────
run_benchmark() {
    local label="$1"
    local host="$2"
    local port="$3"

    hr
    echo -e "\033[1;33m  BENCHMARK: ${label}  (${host}:${port})\033[0m"
    hr

    for test in $TESTS; do
        echo -e "\033[0;36m  ▶ $test\033[0m"
        docker exec "$REDIS_CONTAINER" redis-benchmark \
            -h "$host" \
            -p "$port" \
            -t "$test" \
            $REDIS_BENCH_ARGS \
            2>&1 | sed 's/^/    /'
        echo
    done

    hr
}

# ─────────────────────────────────────────────
# Benchmark 1 — Direct Redis (baseline)
# ─────────────────────────────────────────────
log "Running baseline benchmark directly against Redis..."
run_benchmark "Redis (baseline)" "127.0.0.1" "$REDIS_PORT"

# ─────────────────────────────────────────────
# Benchmark 2 — Speedbump
# ─────────────────────────────────────────────
log "Starting Speedbump proxy..."
docker run -d --rm \
    --name "$SPEEDBUMP_CONTAINER" \
    --network "$NETWORK" \
    "$SPEEDBUMP_IMAGE" \
        --latency 5ms \
        --host 0.0.0.0 \
        --port $SPEEDBUMP_PORT \
        "$REDIS_CONTAINER":$REDIS_PORT
sleep 2
ok "Speedbump up on port $SPEEDBUMP_PORT"

log "Running benchmark through Speedbump..."
run_benchmark "Speedbump" "$SPEEDBUMP_CONTAINER" "$SPEEDBUMP_PORT"

docker rm -f bench-speedbump 2>/dev/null || true

# ─────────────────────────────────────────────
# Benchmark 3 — Hermes
# ─────────────────────────────────────────────
log "Starting Hermes proxy..."
docker run -d --rm \
    --network "$NETWORK" \
    --name "$HERMES_CONTAINER" \
    -e LATENCY_MSECS=5 \
    -e LISTEN_HOST=0.0.0.0 \
    -e LISTEN_PORT=${HERMES_PORT} \
    -e FORWARD_HOST="$REDIS_CONTAINER" \
    -e FORWARD_PORT=${REDIS_PORT} \
    "$HERMES_IMAGE"
sleep 2
ok "Hermes ($HERMES_CONTAINER) up on port $HERMES_PORT"

log "Running benchmark through Hermes..."
run_benchmark "Hermes" "$HERMES_CONTAINER" "$HERMES_PORT"

docker rm -f "$HERMES_CONTAINER" 2>/dev/null || true

# ─────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────
hr
log "All benchmarks complete."
hr
