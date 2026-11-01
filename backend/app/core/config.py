"""Application settings.

All secret values (database password, JWT secret, AI keys) are read from
environment variables or the local `.env` file. They are NEVER written in code.
"""
from functools import lru_cache

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "AI Smart Healthcare API"
    # Set USE_MEMORY_DB=true to run without MongoDB Atlas (data is lost when the server stops).
    use_memory_db: bool = False
    mongodb_uri: str = Field(default="", description="MongoDB Atlas connection string")
    mongodb_db: str = "ai_smart_healthcare"

    jwt_secret: str = Field(..., description="Secret used to sign login tokens")
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 15
    refresh_token_days: int = 7

    cors_origins: str = ""
    # Lets the Flutter web app (Chrome, any localhost port) call the API during development.
    cors_origin_regex: str = r"http://(localhost|127\.0\.0\.1)(:\d+)?"

    gemini_api_key: str = ""
    xai_api_key: str = ""

    @field_validator("jwt_secret")
    @classmethod
    def secret_must_be_long(cls, value: str) -> str:
        if len(value) < 32 or value.startswith("<"):
            raise ValueError(
                "JWT_SECRET must be a random value of at least 32 characters. "
                "See backend/.env.example for how to generate one."
            )
        return value

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    """Load settings once and reuse them."""
    return Settings()
