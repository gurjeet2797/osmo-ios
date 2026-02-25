# Sygil Command Center — Backend

Voice-driven Command Center backend (Phase 1: Calendar).  
Receives transcripts from the iOS app, plans actions via LLM, executes Google Calendar operations server-side, and returns Apple EventKit requests for on-device execution.

## Quick start

```bash
# 1. Start infrastructure
docker compose up -d

# 2. Create virtualenv & install
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"

# 3. Configure
cp .env.example .env
# Fill in OPENAI_API_KEY, GOOGLE_CLIENT_ID/SECRET, FERNET_KEY, JWT_SECRET_KEY

# 4. Generate a Fernet key
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

# 5. Run migrations
alembic upgrade head

# 6. Start server
uvicorn app.main:app --reload
```

## Architecture

```
iOS App  ──transcript──▶  POST /command
                              │
                    ┌─────────┴──────────┐
                    │   LLM Planner      │  (intent → ActionPlan)
                    │   Policy Gate      │  (confirm destructive ops)
                    │   Executor Router  │
                    ├────────┬───────────┤
                    │ Server │  Device   │
                    │ (GCal) │  (iOS)    │
                    └────────┴───────────┘
                              │
                    ◀─── response + device_actions
```

## API

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check |
| POST | `/auth/google` | Start Google OAuth2 flow |
| GET | `/auth/google/callback` | Google OAuth2 callback |
| POST | `/command` | Main command entry (transcript → response) |
| POST | `/command/confirm` | Confirm a pending action plan |
| POST | `/command/device-result` | iOS reports device-side execution results |
