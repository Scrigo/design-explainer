import json

import redis

from bookshop.config import REDIS_URL

QUEUE_NAME = "bookshop:jobs"

_client = redis.Redis.from_url(REDIS_URL)


def enqueue(job_type: str, payload: dict) -> None:
    _client.rpush(QUEUE_NAME, json.dumps({"type": job_type, "payload": payload}))


def dequeue(timeout: int = 5) -> dict | None:
    item = _client.blpop([QUEUE_NAME], timeout=timeout)
    if item is None:
        return None
    _, raw = item
    return json.loads(raw)
