import logging

from bookshop import jobs
from bookshop.notifications.email import send_order_confirmation

log = logging.getLogger("bookshop.worker")


def handle_order_confirmation(payload: dict) -> None:
    send_order_confirmation(payload["email"], payload["order_id"])


HANDLERS = {
    "order_confirmation": handle_order_confirmation,
}


def run() -> None:
    log.info("worker started")
    while True:
        job = jobs.dequeue()
        if job is None:
            continue
        handler = HANDLERS.get(job["type"])
        if handler is None:
            log.warning("unknown job type: %s", job["type"])
            continue
        try:
            handler(job["payload"])
        except Exception:
            log.exception("job %s failed", job["type"])


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    run()
