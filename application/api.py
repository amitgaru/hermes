import os

from flask import Flask, request, jsonify

from custom_logger import logger


API_HOST = os.getenv("API_HOST", "127.0.0.1")
API_PORT = int(os.getenv("API_PORT", "8000"))


def create_app(shared_latency):
    app = Flask("Hermes API")

    @app.post("/latency")
    def set_latency():
        latency_msecs = request.get_json(silent=True)["latency_msecs"]
        logger.info("Setting latency to %s ms", latency_msecs)
        shared_latency.value = latency_msecs
        return jsonify({"latency_msecs": shared_latency.value})

    @app.get("/latency")
    def get_latency():
        return jsonify({"latency_msecs": shared_latency.value})

    return app


def start_api_server(shared_latency):
    app = create_app(shared_latency)
    logger.info("Starting API server on %s:%s", API_HOST, API_PORT)
    app.run(host=API_HOST, port=API_PORT)
