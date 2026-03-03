# OpenClaw Integration — Setup Guide

Osmo can delegate complex, multi-step, and memory-requiring tasks to a
dedicated OpenClaw AI instance running as a Docker sidecar. This is entirely
opt-in — the standard Osmo flow is unchanged unless you flip the switch.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    iPhone (Osmo iOS)                    │
│              SwiftUI · EventKit · Speech                │
└────────────────────────┬────────────────────────────────┘
                         │ POST /command
                         ▼
┌─────────────────────────────────────────────────────────┐
│               Osmo FastAPI Backend (Railway)            │
│                                                         │
│  openclaw_task_router.py                                │
│  ┌────────────────────────────────────────────────┐     │
│  │ Simple task? ──► local planner (OpenAI/Claude) │     │
│  │ Complex task? ─► OpenClaw client               │     │
│  └────────────────────┬───────────────────────────┘     │
└───────────────────────┼─────────────────────────────────┘
                        │ POST /message (Bearer token)
                        ▼
┌─────────────────────────────────────────────────────────┐
│              OpenClaw Gateway (Docker, port 18790)      │
│                                                         │
│  • Persistent session memory across requests            │
│  • Sub-agent spawning for long-running tasks            │
│  • Multi-model routing (Claude / GPT / Gemini)          │
│  • Cron jobs for proactive briefings                    │
│  • Web search, file ops, browser automation             │
└─────────────────────────────────────────────────────────┘
```

---

## Prerequisites

- Docker Desktop (or Docker Engine + Compose v2)
- An Anthropic or OpenAI API key
- The Osmo backend running (local or Railway)

---

## Step 1 — Generate a Gateway Token

```bash
openssl rand -hex 32
# → e.g. a3f9c2d1b4e8f7a6c5d2e1f0b9a8c7d6...
```

Save this value — you'll use it in two places.

---

## Step 2 — Update your `.env`

Add to `backend/.env`:

```env
OPENCLAW_ENABLED=true
OPENCLAW_URL=http://localhost:18790
OPENCLAW_TOKEN=<your-token-from-step-1>
OPENCLAW_GATEWAY_TOKEN=<same-token>
```

---

## Step 3 — Start the OpenClaw Sidecar

From the `backend/` directory:

```bash
docker compose -f docker-compose.yml -f docker-compose.openclaw.yml up -d openclaw
```

Check it's healthy:

```bash
docker compose -f docker-compose.yml -f docker-compose.openclaw.yml ps
# openclaw   running (healthy)
```

---

## Step 4 — Verify the Connection

Hit the status endpoint (with a valid JWT):

```bash
curl -H "Authorization: Bearer <your-jwt>" http://localhost:8000/openclaw/status
# → {"enabled": true, "reachable": true, "url": "http://localhost:18790", ...}
```

---

## What Unlocks When Enabled

| Feature | Before | After |
|---|---|---|
| "Remind me to follow up" | ❌ No persistent memory | ✅ OpenClaw remembers across sessions |
| "Research everyone in my 3pm meeting" | ❌ Single-shot, no web access | ✅ Multi-step agent with web search |
| "Prepare a briefing for tomorrow" | ❌ Out of scope | ✅ Calendar + context → structured brief |
| "Draft an agenda for the Q1 review" | ❌ Basic text response | ✅ Agent-crafted agenda |
| Morning briefings | ❌ Manual request only | ✅ Proactive push via `/openclaw/briefing` |
| Task routing | ❌ Every request hits OpenAI | ✅ Smart split — simple stays local, complex goes to OpenClaw |

---

## API Endpoints

### `GET /openclaw/status`
Check if OpenClaw is configured and reachable.

### `POST /openclaw/briefing`
Generate a morning briefing.
```json
{
  "events": [{"title": "Team standup", "start_time": "09:00", "attendees": ["Alice"]}],
  "preferences": "prefers bullet points, no fluff"
}
```

### `POST /openclaw/meeting-prep`
Generate structured meeting prep notes.
```json
{
  "meeting_title": "Q1 Review",
  "attendees": ["Alice Johnson", "Bob Smith"],
  "notes": "Focus on revenue targets"
}
```

---

## Task Routing Logic

`openclaw_task_router.py` decides what gets delegated vs handled locally.

**Delegated to OpenClaw** (multi-step / memory / research):
- "remind me to...", "follow up on...", "research...", "prepare a briefing"
- "draft an agenda", "summarize", "what do you know about..."
- Requests with 3+ steps or conjunctions

**Stays local** (fast one-shot device actions):
- "play music", "call Alice", "add calendar event"
- "set a timer", "take a photo", "open the app"

If OpenClaw is unreachable, the local planner handles everything — zero downtime.

---

## Troubleshooting

**OpenClaw won't start:**
```bash
docker logs osmo-openclaw
```

**"reachable: false" in status:**
- Check the container is running: `docker ps | grep openclaw`
- Verify port 18790 is not blocked
- Check `OPENCLAW_TOKEN` matches `OPENCLAW_GATEWAY_TOKEN`

**Tasks not being delegated:**
- Confirm `OPENCLAW_ENABLED=true` in `.env` and restart the backend
- Check the routing log: look for `openclaw.delegated` in backend logs
