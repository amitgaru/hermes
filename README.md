# Intro

`Hermes` is a TCP proxy written in Python (async/await) to simulate network delays between the servers. The network delay latency is applied per TCP packet. One can configure either the upstream-only proxy delay or both (upstream and downstream) proxy delays. It is a tool similar to [speedbump](https://github.com/kffl/speedbump) (written in Go).


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
      BUFFER_SIZE: "4096"
      LOG_LEVEL: "INFO"
```

Docker public image: `xillar/hermes:latest`

  ## Configuration (Environment Variables)
  
  The proxy is configured using environment variables. Below are the available options:
  
  ### Core Settings
  
  - **`LISTEN_HOST`** *(default: `0.0.0.0`)*  
    IP address the proxy binds to for incoming connections.  
    _Example:_ `0.0.0.0`
  
  - **`LISTEN_PORT`** *(default: `8000`)*  
    Port the proxy listens on.  
    _Example:_ `6379`
  
  - **`FORWARD_HOST`** *(default: `127.0.0.1`)*  
    Target server IP address where traffic is forwarded (e.g., Redis/KeyDB instance).  
    _Example:_ `127.0.0.1`
  
  - **`FORWARD_PORT`** *(default: `8888`)*  
    Target server port.  
    _Example:_ `6380`

  - **`BUFFER_SIZE`** *(default: `4096`)*  
    Size (in bytes) of each read operation from the socket.  
    Larger values may improve throughput, while smaller values can provide finer-grained latency control.  
    _Example:_ `4096`
  
  ### Latency Control
  
  - **`LATENCY_MSECS`** *(default: `0`)*  
    Artificial delay (in milliseconds) applied to each packet.  
    _Example:_ `5` (adds ~5ms delay per packet)
  
  - **`UPSTREAM_ONLY`** *(default: `true`)*  
    Controls where latency is applied:
    - `true`:  Delay is applied **only to upstream traffic** (client → server)  
    - `false`: Delay is applied to **both upstream and downstream** (client ↔ server)
  


# Benchmarks

*In Progress.*


# Acknowledgments

This project was developed with assistance from AI tools, including:

- **Claude (Anthropic)** – for code suggestions, design ideas, and implementation guidance  
- **OpenAI (ChatGPT)** – for code development, debugging help, and README/documentation improvements  

These tools were used to accelerate development and improve code quality and clarity.
