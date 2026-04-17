# Intro

`Hermes` is a TCP proxy written in Python (async/await) to simulate network delays between the servers. One can configure either the upstream-only proxy delay or both (upstream and downstream) proxy delays.


# Docker compose setup (recommended)

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

Docker public image: `xillar/hermes:latest`

## Configuration (Environment Variables)

The proxy is configured using environment variables. Below are the available options:

### Core Settings

- **`LISTEN_HOST`**  
  IP address the proxy binds to for incoming connections.  
  _Example:_ `0.0.0.0`

- **`LISTEN_PORT`**  
  Port the proxy listens on.  
  _Example:_ `6379`

- **`FORWARD_HOST`**  
  Target server IP address where traffic is forwarded (e.g., Redis/KeyDB instance).  
  _Example:_ `127.0.0.1`

- **`FORWARD_PORT`**  
  Target server port.  
  _Example:_ `6380`

---

### Latency Control

- **`LATENCY_MSECS`**  
  Artificial delay (in milliseconds) applied to each packet.  
  _Example:_ `5` (adds ~5ms delay per packet)

- **`UPSTREAM_ONLY`** *(default: `true`)*  
  Controls where latency is applied:
  - `true` → Delay is applied **only to upstream traffic** (client → server)  
  - `false` → Delay is applied to **both upstream and downstream** (client ↔ server)

---


# Benchmarks

*In Progress*
