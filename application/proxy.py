import os
import time
import logging
import asyncio

from collections import deque

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)

logger = logging.getLogger()


LISTEN_HOST = os.getenv("LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.getenv("LISTEN_PORT", "8000"))


FORWARD_HOST = os.getenv("FORWARD_HOST")
FORWARD_PORT = int(os.getenv("FORWARD_PORT", "8888"))

BUFFER_SIZE = 4096

LATENCY_MSECS = float(os.getenv("LATENCY_MSECS", "0.0"))
UPSTREAM_ONLY = os.getenv("UPSTREAM_ONLY", "true").lower() == "true"


logger.info(
    "Started with UPSTREAM_ONLY: %s, LISTEN_HOST: %s, LISTEN_PORT: %s, FORWARD_HOST: %s, FORWARD_PORT: %s, LATENCY_MSECS: %s",
    UPSTREAM_ONLY,
    LISTEN_HOST,
    LISTEN_PORT,
    FORWARD_HOST,
    FORWARD_PORT,
    LATENCY_MSECS
)


class TimedPacketQueue:

    def __init__(self, delay):
        self.queue = deque()
        self.delay = delay

    def push(self, item, writer):
        self.queue.append((item, writer, time.monotonic() + self._delay))

    def pop(self):
        if self.queue and self.queue[0][2] <= time.monotonic():
            return self.queue.popleft()
        return None, None, None

    def empty(self):
        return len(self.queue) == 0

    @property
    def delay(self):
        return self._delay
    
    @delay.setter
    def delay(self, new_delay):
        self._delay = new_delay / 1000 # convert ms to seconds


packet_queue = TimedPacketQueue(LATENCY_MSECS)


async def periodic_packet_processor():
    logger.info("Periodic packet processor task started.")
    while True:
        await asyncio.sleep(0)
        data, writer, _ = packet_queue.pop()
        if data is not None:
            try:
                writer.write(data)
                await writer.drain()
            except Exception as e:
                logger.error("Error processing delayed packet: %s", e)


async def forward(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    try:
        while True:
            data = await reader.read(BUFFER_SIZE)
            if not data:
                break
            logger.debug("Queuing %d bytes.", len(data))
            packet_queue.push(data, writer)
    except Exception as e:
        logger.error("Error during forwarding: %s", e)
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception as e:
            logger.error("Error closing writer: %s", e)
            pass


async def forward_wo_delay(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    try:
        while True:
            data = await reader.read(BUFFER_SIZE)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except Exception as e:
        logger.error("Error during forwarding: %s", e)
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception as e:
            logger.error("Error closing writer: %s", e)
            pass


async def handle_client(client_reader, client_writer):
    try:
        server_reader, server_writer = await asyncio.open_connection(
            FORWARD_HOST, FORWARD_PORT
        )
    except Exception as e:
        logger.error("Failed to connect to target: %s", e)
        client_writer.close()
        await client_writer.wait_closed()
        return

    # Forward data both ways concurrently
    tasks = [forward(client_reader, server_writer)]
    if UPSTREAM_ONLY:
        tasks.append(forward_wo_delay(server_reader, client_writer))
    else:
        tasks.append(forward(server_reader, client_writer))
    await asyncio.gather(*tasks)


async def main():
    asyncio.create_task(periodic_packet_processor())
    server = await asyncio.start_server(handle_client, LISTEN_HOST, LISTEN_PORT)
    logger.info(
        f"Forwarding {LISTEN_HOST}:{LISTEN_PORT} -> {FORWARD_HOST}:{FORWARD_PORT} with delay {LATENCY_MSECS}ms"
    )

    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    START_TIME = time.time()
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.warning("Proxy stopped.")
