"""Registration, login, token refresh and logout."""
import jwt
from fastapi import APIRouter, Depends, status

from app.core.errors import ApiError
from app.core.rate_limit import limit_by_ip
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    hash_token_id,
    verify_password,
)
from app.deps import get_current_user, get_repo
from app.models.user import LoginRequest, RefreshRequest, RegisterRequest, TokenResponse, UserOut
from app.repositories.user_repository import UserRepository

router = APIRouter(prefix="/auth", tags=["auth"])

# Used so a login for an unknown email takes about as long as a wrong password.
_DUMMY_HASH = hash_password("dummy-password-1")


def user_out(user: dict) -> UserOut:
    return UserOut(
        id=str(user["_id"]),
        email=user["email"],
        full_name=user["full_name"],
        roles=user["roles"],
        email_verified=user["email_verified"],
    )


async def _issue_tokens(repo: UserRepository, user: dict) -> TokenResponse:
    access = create_access_token(str(user["_id"]), user["roles"])
    refresh, token_id, expires_at = create_refresh_token(str(user["_id"]))
    await repo.save_refresh_token(user["_id"], hash_token_id(token_id), expires_at)
    return TokenResponse(access_token=access, refresh_token=refresh)


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED,
             dependencies=[limit_by_ip("register", 5, 600)])
async def register(body: RegisterRequest, repo: UserRepository = Depends(get_repo)):
    user = await repo.create_user(body.email, hash_password(body.password), body.full_name)
    if user is None:
        raise ApiError(status.HTTP_409_CONFLICT, "email_taken", "An account with this email already exists.")
    await repo.audit(user["_id"], "user.register")
    return await _issue_tokens(repo, user)


@router.post("/login", response_model=TokenResponse, dependencies=[limit_by_ip("login", 10, 300)])
async def login(body: LoginRequest, repo: UserRepository = Depends(get_repo)):
    user = await repo.find_by_email(body.email)
    password_hash = user["password_hash"] if user else _DUMMY_HASH
    if not verify_password(body.password, password_hash) or user is None:
        await repo.audit(user["_id"] if user else None, "user.login_failed")
        # Same message for unknown email and wrong password (no account enumeration).
        raise ApiError(status.HTTP_401_UNAUTHORIZED, "invalid_credentials", "Email or password is incorrect.")
    await repo.mark_login(user["_id"])
    await repo.audit(user["_id"], "user.login")
    return await _issue_tokens(repo, user)


@router.post("/refresh", response_model=TokenResponse)
async def refresh(body: RefreshRequest, repo: UserRepository = Depends(get_repo)):
    invalid = ApiError(status.HTTP_401_UNAUTHORIZED, "invalid_token", "Please log in again.")
    try:
        payload = decode_token(body.refresh_token, expected_type="refresh")
    except jwt.InvalidTokenError:
        raise invalid
    token_hash = hash_token_id(payload["jti"])
    stored = await repo.find_active_refresh_token(token_hash)
    user = await repo.find_by_id(payload["sub"])
    if stored is None or user is None:
        raise invalid
    # Rotate: the old refresh token can only be used once.
    await repo.revoke_refresh_token(token_hash)
    return await _issue_tokens(repo, user)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(body: RefreshRequest, repo: UserRepository = Depends(get_repo)):
    try:
        payload = decode_token(body.refresh_token, expected_type="refresh")
        await repo.revoke_refresh_token(hash_token_id(payload["jti"]))
        user = await repo.find_by_id(payload["sub"])
        await repo.audit(user["_id"] if user else None, "user.logout")
    except jwt.InvalidTokenError:
        pass  # Logging out with a bad token is harmless.


@router.get("/me", response_model=UserOut)
async def me(user: dict = Depends(get_current_user)):
    return user_out(user)
