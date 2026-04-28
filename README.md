# Intro

**Hermes** is a TCP proxy written in Erlang that simulates network conditions between servers. It introduces configurable latency by delaying data forwarding on each send operation, where each operation transmits up to one buffer's worth of data. Hermes delivers better performance than **kffl/speedbump**. It also supports runtime delay injection via an HTTP API, a feature not available in Speedbump.

# Benchmarks

  ## redis-benchmark

  Benchmarking script is available at `benchmarks/redis_test.sh`. The following benchmarking results are based on `1M` requests across `100` concurrent clients with buffer size `65536` (64 KB) across different latencies.
  
  ### Baseline (without any proxy) vs Speedbump (0ms upstream latency) vs Hermes (0ms upstream latency)
  
  ![](results/0ms_upstream.png) 
  
  
  ### Baseline (without any proxy) vs Speedbump (5ms upstream latency) vs Hermes (5ms upstream latency)
  
  ![](results/5ms_upstream.png) 

# Docker compose setup (recommended)

```sh
services:
  hermes:
    image: xillar/hermes:latest
    container_name: hermes
    ports:
      - "6389:6389"
      - "8000:8000"
    environment:
      LISTEN_HOST: "0.0.0.0"
      LISTEN_PORT: "6389"
      FORWARD_HOST: "localhost"
      FORWARD_PORT: "6379"
      LATENCY_MSECS: "5"
      BUFFER_SIZE: "65536"
      LOG_LEVEL: "INFO"
      API_HOST: "0.0.0.0"
      API_PORT: "8000"
```

Docker public image: `xillar/hermes:latest`

  ### Configuration (Environment Variables)
  
  The proxy is configured using environment variables. Below are the available options:
  
  | Variable | Default | Description |
  |---|---|---|
  | `LISTEN_HOST` | `127.0.0.1` | Proxy bind address |
  | `LISTEN_PORT` | `6380` | Proxy listen port |
  | `FORWARD_HOST` | `127.0.0.1` | Target server address |
  | `FORWARD_PORT` | `6379` | Target server port |
  | `BUFFER_SIZE` | `65536` | Read buffer size (bytes) |
  | `API_HOST` | `127.0.0.1` | Latency API host |
  | `API_PORT` | `8000` | Latency API port |
  | `LATENCY_MSECS` | `0` | Artificial delay (ms) per flush |

  
### Latency API

**GET** `/latency` — read current latency

```sh
curl http://localhost:8000/latency
# {"latency": 5}
```

**POST** `/latency` — update latency

```sh
curl -X POST http://localhost:8000/latency \
     -H 'Content-Type: application/json' \
     -d '{"latency": 20}'
# {"latency": 20}
```
