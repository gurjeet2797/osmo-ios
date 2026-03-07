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
    anthropic_model: str = "claude-haiku-4-5-20251001"
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
    # APNs (Apple Push Notifications) — set APNS_KEY_PATH to enable
    # ---------------------------------------------------------------------------
    apns_key_path: str = ""  # path to .p8 file (local dev)
    apns_key_contents: str = ""  # paste .p8 file contents here (Railway/cloud)
    apns_key_id: str = ""
    apns_team_id: str = ""
    apns_bundle_id: str = "com.gurjeet.osmoai"

    def validate_production(self) -> list[str]:
        """Return list of warnings for missing production settings."""
        warnings = []
        if self.jwt_secret_key == "change-me-in-production":
            warnings.append("JWT_SECRET_KEY is using the default value — set a secure random key")
        if not self.fernet_key:
            warnings.append("FERNET_KEY is not set — Google OAuth token encryption will fail")
        if self.llm_provider == "anthropic" and not self.anthropic_api_key:
            warnings.append("ANTHROPIC_API_KEY is not set but llm_provider=anthropic")
        if self.llm_provider == "openai" and not self.openai_api_key:
            warnings.append("OPENAI_API_KEY is not set but llm_provider=openai")
        if not self.google_client_id or not self.google_client_secret:
            warnings.append("GOOGLE_CLIENT_ID/SECRET not set — OAuth will fail")
        return warnings


settings = Settings()
