import os
import logging

from datetime import datetime


class MillisecondFormatter(logging.Formatter):
    def formatTime(self, record, datefmt=None):
        dt = datetime.fromtimestamp(record.created)
        return dt.strftime(datefmt)


handler = logging.StreamHandler()
handler.setFormatter(
    MillisecondFormatter(
        fmt="%(asctime)s - %(levelname)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S.%f",
    )
)

logger = logging.getLogger()
logger.handlers.clear()
logger.addHandler(handler)
logger.setLevel(os.getenv("LOG_LEVEL", "INFO"))
