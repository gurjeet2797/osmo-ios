# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Full-stack AI chat + calendar assistant. iOS frontend (SwiftUI, Swift 6, iOS 18+) with a Python FastAPI backend. No external iOS dependencies — pure Apple frameworks. General-purpose chat architecture with calendar as the first plugin integration.

## Build System

### iOS
- **Xcode project** generated via XCGen from `project.yml`
- **Build**: `xcodebuild -project Osmo.xcodeproj -scheme Osmo -sdk iphonesimulator build`
- **Run on simulator**: `xcodebuild -project Osmo.xcodeproj -scheme Osmo -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build`
- No package manager dependencies (no SPM, CocoaPods, or Carthage)
- No test targets currently configured

### Backend
- Located in `backend/` directory
- **Local dev**: `docker compose up -d` (Postgres + Redis), then `uvicorn app.main:app --reload`
- **Deploy**: Railway with `backend/Dockerfile` and `backend/railway.toml`
- **Migrations**: `alembic upgrade head`
- **Dependencies**: FastAPI, SQLAlchemy (async), OpenAI, Google Calendar API

## Architecture

### iOS (MVVM)
**Entry flow**: `OsmoApp` → `ContentView` → `HomeView` (with sheet presentation of `ChatSheetView` and `HistorySheetView`)

**State management**: Single `AppViewModel` (@Observable) owns all app state. `AuthManager` (@Observable) handles Google OAuth via ASWebAuthenticationSession. Both passed via SwiftUI environment.

**Networking**: `Services/APIClient.swift` (URLSession) → backend API. JWT tokens stored in Keychain via `Services/KeychainHelper.swift`.

**Models**: `Message` (id, content, isUser, timestamp, categories, tags, planId, requiresConfirmation, deviceActions) and `Conversation` (id, messages, createdAt). API types in `Models/APIModels.swift`.

**Device actions**: `Services/EventKitManager.swift` executes local EventKit operations when the backend routes actions to the device.

**Visual system**: Dark-mode only. `CosmicBackground` renders animated starfield at 30fps. `Shaders.metal` provides GPU effects. `GlassEffect+Adaptive` wraps iOS 26+ glass morphism.

### Backend (Command Center)
**Flow**: iOS sends transcript → `POST /command` → LLM Planner (OpenAI) → ActionPlan → Policy Gate → Executor → routes to server tools (Google Calendar) or device tools (iOS EventKit) → response.

**Auth**: Google OAuth2 → JWT Bearer tokens. Mobile callback redirects to `osmo://` custom URL scheme.

**Key files**: `app/core/planner.py` (LLM planning), `app/core/executor.py` (action execution), `app/api/command.py` (main endpoint), `app/tools/` (tool registry).

## Key Customization Points

- Suggestions and category types: `AppViewModel` (CategoryType enum, suggestions array)
- App name/taglines: hardcoded strings in `HomeView` and `ChatSheetView`
- Bundle identifier and team: `project.yml`
- Backend URL: `Services/APIConfig.swift`
- LLM model/behavior: `backend/app/config.py` and `backend/app/core/planner.py`
- Metal shaders: `Shaders.metal` for visual effect tuning

## Swift 6 Concurrency

All models use `Sendable`. ViewModels use `@MainActor` isolation (via `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` build setting). Follow these patterns when adding new code.
