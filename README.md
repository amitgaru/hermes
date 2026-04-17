# Intro

Hermes is a TCP proxy written in Python (async/await) to simulate network delays between the servers. One can configure either the upstream-only proxy delay or both (upstream and downstream) proxy delays.


# Docker container setup

## Docker compose setup (recommended)

```sh
services:
  hermes:
    image: xillar/hermes:latest
    container_name: hermes
    ports:
      - "6389:6389"
    environment:
      LISTEN_HOST: "0.0.0.0"
      LISTEN_PORT: "6389"
      FORWARD_HOST: "localhost"
      FORWARD_PORT: "6379"
      UPSTREAM_ONLY: "true"
      LATENCY_MSECS: "${LATENCY_MSECS:-5}"
```


# Benchmarks
