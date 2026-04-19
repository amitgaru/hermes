import os
import time
import asyncio

from collections import deque
from multiprocessing import Value, Process

from custom_logger import logger
from api import start_api_server


class TimedPacketQueue:

    def __init__(self, delay):
        self.queue = deque()
        self._delay = delay

    def push(self, item, writer):
        logger.debug("Pushing packet to queue.")
        self.queue.append((item, writer, time.monotonic() + self.delay))

    def pop(self):
        if len(self.queue) > 0 and self.queue[0][2] <= time.monotonic():
            logger.debug("Popping packet from queue.")
            return self.queue.popleft()
        return None, None, None

    @property
    def delay(self):
        return self._delay.value


async def periodic_packet_processor(packet_queue):
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


async def forward(packet_queue, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
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


async def handle_client(packet_queue, client_reader, client_writer):
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
    tasks = [forward(packet_queue, client_reader, server_writer)]
    if UPSTREAM_ONLY:
        tasks.append(forward_wo_delay(server_reader, client_writer))
    else:
        tasks.append(forward(packet_queue, server_reader, client_writer))
    await asyncio.gather(*tasks)


async def main(packet_queue):
    asyncio.create_task(periodic_packet_processor(packet_queue))
    server = await asyncio.start_server(lambda cr, cw: handle_client(packet_queue, cr, cw), LISTEN_HOST, LISTEN_PORT)
    logger.info(
        f"Forwarding {LISTEN_HOST}:{LISTEN_PORT} -> {FORWARD_HOST}:{FORWARD_PORT} with delay {LATENCY_MSECS}ms"
    )

    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    START_TIME = time.time()
    LISTEN_HOST = os.getenv("LISTEN_HOST", "127.0.0.1")
    LISTEN_PORT = int(os.getenv("LISTEN_PORT", "6389"))

    FORWARD_HOST = os.getenv("FORWARD_HOST", "127.0.0.1")
    FORWARD_PORT = int(os.getenv("FORWARD_PORT", "6379"))

    BUFFER_SIZE = int(os.getenv("BUFFER_SIZE", "4096"))

    LATENCY_MSECS = int(os.getenv("LATENCY_MSECS", "0"))
    UPSTREAM_ONLY = os.getenv("UPSTREAM_ONLY", "true").lower() == "true"

    logger.info(
        "Started with UPSTREAM_ONLY: %s, LISTEN_HOST: %s, LISTEN_PORT: %s, FORWARD_HOST: %s, FORWARD_PORT: %s, LATENCY_MSECS: %s",
        UPSTREAM_ONLY,
        LISTEN_HOST,
        LISTEN_PORT,
        FORWARD_HOST,
        FORWARD_PORT,
        LATENCY_MSECS,
    )

    shared_latency = Value("f", float(LATENCY_MSECS / 1000), lock=False)
    packet_queue = TimedPacketQueue(shared_latency)

    try:
        p = Process(target=start_api_server, args=(shared_latency,))
        p.start()
        asyncio.run(main(packet_queue))
        p.join()
    except KeyboardInterrupt:
        logger.warning("Proxy stopped.")
