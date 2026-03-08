# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Full-stack AI assistant. iOS frontend (SwiftUI, Swift 6, iOS 18+) with a Python FastAPI backend. No external iOS dependencies — pure Apple frameworks. General-purpose chat architecture with a plugin-based skill system (calendar, reminders, messages, music, navigation, email, etc.).

## Build & Run

### iOS
- **Xcode project** generated via XcodeGen from `project.yml`
- **Build**: `xcodebuild -project Osmo.xcodeproj -scheme Osmo -sdk iphonesimulator build`
- **Run on simulator**: `xcodebuild -project Osmo.xcodeproj -scheme Osmo -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build`
- No package manager dependencies (no SPM, CocoaPods, or Carthage)
- No test targets currently configured
- When adding new Swift files, they must be added to `project.yml` under the appropriate group, then regenerate the Xcode project with `xcodegen`

### Backend
- Located in `backend/` directory
- **Local dev**: `cd backend && docker compose up -d` (Postgres + Redis), then `uvicorn app.main:app --reload`
- **Install deps**: `pip install -e ".[dev]"`
- **Deploy**: Railway with `backend/Dockerfile` and `backend/railway.toml`
- **Migrations**: `cd backend && alembic upgrade head`
- **Run tests**: `cd backend && pytest` (uses pytest-asyncio with `asyncio_mode = "auto"`)
- **Lint**: `cd backend && ruff check .` (line-length 99, target py312)
- **Config**: `backend/.env` (see `app/config.py` for all env vars). Requires `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`, `GOOGLE_CLIENT_ID/SECRET`, `FERNET_KEY`, `JWT_SECRET_KEY`.

## Architecture

### iOS (MVVM)
**Entry flow**: `OsmoApp` → `ContentView` → `HomeView` (sheet presentation of `ChatSheetView` and `HistorySheetView`)

**State management**: Single `AppViewModel` (@Observable) owns all app state. `AuthManager` (@Observable) handles Google OAuth via ASWebAuthenticationSession. Both passed via SwiftUI environment.

**Networking**: `Services/APIClient.swift` (URLSession) → backend API. JWT tokens stored in Keychain via `Services/KeychainHelper.swift`.

**Models**: `Message` and `Conversation` in `Models/`. API request/response types in `Models/APIModels.swift`.

**Device actions**: Backend returns `device_actions` in responses. iOS-side manager classes in `Services/` (EventKitManager, ReminderManager, MusicManager, NavigationManager, etc.) execute these locally.

**Visual system**: Dark-mode only. `CosmicBackground` renders animated starfield. `Shaders.metal` provides GPU effects. `ParticleOrb/` contains the animated orb particle system. `GlassEffect+Adaptive` wraps iOS 26+ glass morphism.

### Backend (Command Center)
**Flow**: iOS sends transcript → `POST /command` → LLM Planner → ActionPlan → Policy Gate → Executor → routes to server tools or device tools → response.

**Auth**: Google OAuth2 → JWT Bearer tokens. Mobile callback redirects to `osmo://` custom URL scheme.

**LLM**: Supports both OpenAI and Anthropic (`llm_provider` setting in config). Planner in `app/core/planner.py`, LLM connector in `app/connectors/llm.py`.

**Key modules**:
- `app/api/command.py` — main command endpoint
- `app/core/planner.py` — LLM planning (intent → ActionPlan)
- `app/core/executor.py` — action execution and routing
- `app/core/policy.py` — confirmation gate for destructive ops
- `app/core/session_manager.py` — conversation session management

### Backend Skill System
Skills are the plugin architecture for adding new capabilities. Each skill lives in `backend/app/tools/skills/<skill_name>/` and contains:
- `skill.toml` — manifest with name, description, tool modules, and planner instructions
- Tool modules (Python files) — each defines `BaseTool` subclasses with `execute()` and `parameters_schema()`
- Tools register themselves at module import via `register_tool()`

`app/tools/loader.py` auto-discovers skills by scanning for `skill.toml` files. Tools have an `execution_target` of either `"server"` (executed on backend, e.g. Google Calendar API) or `"device"` (returned to iOS for local execution, e.g. EventKit).

Current skills: calendar, reminders, notifications, messages, music, camera, device, navigation, web_search, app_launcher, translation, memory, email, user_profile.

### Backend Connectors
`app/connectors/` contains third-party API clients (Google Calendar, Google Routes, Gmail, Brave Search, APNs, LLM). These are used by tool implementations, not called directly from API routes.

## Key Customization Points

- Backend URL: `Services/APIConfig.swift`
- LLM model/behavior: `backend/app/config.py` and `backend/app/core/planner.py`
- Bundle identifier and team: `project.yml`
- Adding a new skill: create `backend/app/tools/skills/<name>/skill.toml` + tool module(s)

## Swift 6 Concurrency

All models use `Sendable`. ViewModels use `@MainActor` isolation (via `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` build setting). Follow these patterns when adding new code.
