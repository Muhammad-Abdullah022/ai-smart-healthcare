"""Simple in-memory rate limiting (task C-14).

Stops password guessing on login and runaway AI costs. It keeps counts in the
server's memory, which is fine for one server; a shared store (e.g. Redis) would
be needed if the backend is ever run on several servers.
"""
import time
from collections import defaultdict, deque

from fastapi import Depends, Request, status

from app.core.errors import ApiError


class RateLimiter:
    def __init__(self):
        self._hits: dict[str, deque] = defaultdict(deque)

    def check(self, key: str, limit: int, window_seconds: int) -> None:
        now = time.monotonic()
        hits = self._hits[key]
        while hits and now - hits[0] > window_seconds:
            hits.popleft()
        if len(hits) >= limit:
            retry = int(window_seconds - (now - hits[0])) + 1
            raise ApiError(status.HTTP_429_TOO_MANY_REQUESTS, "rate_limited",
                           f"Too many attempts. Please wait {retry} seconds and try again.")
        hits.append(now)

    def reset(self) -> None:
        self._hits.clear()


def limit_by_ip(name: str, limit: int, window_seconds: int):
    """Dependency: at most `limit` calls per `window_seconds` from one IP address."""

    def dependency(request: Request) -> None:
        limiter: RateLimiter = request.app.state.rate_limiter
        ip = request.client.host if request.client else "unknown"
        limiter.check(f"{name}:{ip}", limit, window_seconds)

    return Depends(dependency)


def limit_by_user(name: str, limit: int, window_seconds: int):
    """Dependency: at most `limit` calls per window for the logged-in user."""
    from app.deps import get_current_user  # avoid circular import

    def dependency(request: Request, user: dict = Depends(get_current_user)) -> None:
        request.app.state.rate_limiter.check(f"{name}:{user['_id']}", limit, window_seconds)

    return Depends(dependency)
