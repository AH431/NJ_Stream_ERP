import json
import logging
import os
from pathlib import Path


class _JsonFormatter(logging.Formatter):
    """Single-line JSON formatter for structured log aggregation."""

    def format(self, record: logging.LogRecord) -> str:
        obj: dict = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S"),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        # Merge extra fields injected via logger.info(..., extra={...})
        _skip = frozenset({
            "name", "msg", "args", "levelname", "levelno", "pathname",
            "filename", "module", "exc_info", "exc_text", "stack_info",
            "lineno", "funcName", "created", "msecs", "relativeCreated",
            "thread", "threadName", "processName", "process", "message",
            "taskName",
        })
        for key, val in record.__dict__.items():
            if key not in _skip:
                obj[key] = val
        if record.exc_info:
            obj["exc"] = self.formatException(record.exc_info)
        return json.dumps(obj, ensure_ascii=False)


def get_logger(name: str, log_dir: str = "logs") -> logging.Logger:
    Path(log_dir).mkdir(exist_ok=True)

    logger = logging.getLogger(name)
    if logger.handlers:
        return logger

    logger.setLevel(logging.INFO)

    use_json = os.environ.get("LOG_FORMAT", "").lower() == "json"
    fmt: logging.Formatter = (
        _JsonFormatter() if use_json
        else logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s")
    )

    ch = logging.StreamHandler()
    ch.setFormatter(fmt)
    logger.addHandler(ch)

    fh = logging.FileHandler(os.path.join(log_dir, "rag.log"), encoding="utf-8")
    fh.setFormatter(fmt)
    logger.addHandler(fh)

    return logger
