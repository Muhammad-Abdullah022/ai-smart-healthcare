"""Shared dependencies used by API routes."""
import jwt
from fastapi import Depends, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.errors import ApiError
from app.core.security import decode_token
from app.repositories.user_repository import UserRepository

_bearer = HTTPBearer(auto_error=False)


def get_db(request: Request):
    return request.app.state.db


def get_repo(db=Depends(get_db)) -> UserRepository:
    return UserRepository(db)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    repo: UserRepository = Depends(get_repo),
) -> dict:
    """Return the logged-in user, or stop the request with 401."""
    if credentials is None:
        raise ApiError(status.HTTP_401_UNAUTHORIZED, "not_authenticated", "Please log in.")
    try:
        payload = decode_token(credentials.credentials, expected_type="access")
    except jwt.ExpiredSignatureError:
        raise ApiError(status.HTTP_401_UNAUTHORIZED, "token_expired", "Your session has expired.")
    except jwt.InvalidTokenError:
        raise ApiError(status.HTTP_401_UNAUTHORIZED, "invalid_token", "Please log in again.")

    user = await repo.find_by_id(payload["sub"])
    if user is None:
        raise ApiError(status.HTTP_401_UNAUTHORIZED, "invalid_token", "Please log in again.")
    return user
