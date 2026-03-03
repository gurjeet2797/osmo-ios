from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    database_url: str = "postgresql+asyncpg://osmo:osmo_dev@localhost:5432/osmo"

    @model_validator(mode="after")
    def normalize_database_url(self) -> "Settings":
        if self.database_url.startswith("postgres://"):
            self.database_url = self.database_url.replace("postgres://", "postgresql+asyncpg://", 1)
        elif self.database_url.startswith("postgresql://"):
            self.database_url = self.database_url.replace("postgresql://", "postgresql+asyncpg://", 1)
        return self

    redis_url: str = "redis://localhost:6379/0"

    llm_provider: str = "openai"  # "openai" or "anthropic"

    openai_api_key: str = ""
    openai_model: str = "gpt-4o"

    anthropic_api_key: str = ""
    anthropic_model: str = "claude-sonnet-4-5-20250929"
    anthropic_max_tokens: int = 4096

    session_max_messages: int = 50

    google_client_id: str = ""
    google_client_secret: str = ""
    google_redirect_uri: str = "http://localhost:8000/auth/google/callback"

    jwt_secret_key: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 1440

    fernet_key: str = ""

    google_routes_api_key: str = ""

    brave_search_api_key: str = ""

    sentry_dsn: str = ""

    # Subscription & rate limiting
    dev_emails: str = "sales@develloinc.com,gurjeet2797@gmail.com"
    free_daily_limit: int = 25
    pro_monthly_price: str = "$4.99"

    environment: str = "development"
    allowed_origins: str = ""

    # ---------------------------------------------------------------------------
    # OpenClaw integration (opt-in — set OPENCLAW_ENABLED=true to activate)
    # ---------------------------------------------------------------------------
    openclaw_enabled: bool = False
    openclaw_url: str = "http://localhost:18790"
    openclaw_token: str = ""
    openclaw_timeout: float = 30.0
    openclaw_router_model: str = ""  # cheap classifier model, auto-detect from provider


settings = Settings()
