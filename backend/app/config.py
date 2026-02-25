from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    database_url: str = "postgresql+asyncpg://osmo:osmo_dev@localhost:5432/osmo"
    redis_url: str = "redis://localhost:6379/0"

    openai_api_key: str = ""
    openai_model: str = "gpt-4o"

    google_client_id: str = ""
    google_client_secret: str = ""
    google_redirect_uri: str = "http://localhost:8000/auth/google/callback"

    jwt_secret_key: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 1440

    fernet_key: str = ""

    sentry_dsn: str = ""

    environment: str = "development"
    allowed_origins: str = ""


settings = Settings()
