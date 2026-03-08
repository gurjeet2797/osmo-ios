# Osmo AI — Architecture & Visual Guide

## View Hierarchy & Navigation

```
OsmoApp
 └─ ContentView                          [Root — owns AppViewModel]
     ├─ HomeView                         [Main screen — always visible]
     │   ├─ CosmicBackground             [Animated starfield backdrop]
     │   ├─ Top Bar                      [Sign in / Profile menu]
     │   ├─ Weather / Greeting           [Fades after first recording]
     │   ├─ Widget Stack                 [Calendar, Email, Commute, Briefing, Weather cards]
     │   │   OR Rotating Tips            [When no widget data]
     │   │   OR LLM Response             [Typewriter text after command]
     │   ├─ ParticleOrbView              [Interactive orb — bottom center]
     │   │   ├─ Tap → Start/stop recording
     │   │   ├─ Long press (0.5s) → Vision camera
     │   │   └─ Swipe up → Control Center
     │   └─ Live transcript + status     [Floating above bottom]
     │
     ├─ .sheet → ChatSheetView           [Full conversation thread]
     ├─ .sheet → HistorySheetView        [Past conversations]
     ├─ .sheet → ControlCenterView       [Calendar / Commute / Settings tabs]
     ├─ .sheet → PaywallView             [Subscription upgrade]
     ├─ .sheet → FAQView                 [What Can Osmo Do?]
     │
     ├─ .overlay → VisionCameraView      [UIImagePickerController for photo→AI]
     ├─ .fullScreenCover → CameraView    [Auto-capture camera (device action)]
     ├─ .sheet → MessageComposeView      [iMessage compose (device action)]
     └─ .translationTask                 [Apple Translation API bridge]
```

## User Interaction Flow

```
                    ┌──────────────┐
                    │   HomeView   │
                    │  (Orb idle)  │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
         TAP ORB     HOLD ORB 0.5s  SWIPE UP
              │            │            │
              ▼            ▼            ▼
      ┌──────────┐  ┌────────────┐  ┌────────────────┐
      │ Listening │  │   Vision   │  │ Control Center │
      │ (mic on)  │  │  Camera    │  │ Calendar/      │
      │ orb→mic   │  │ orb explode│  │ Commute/       │
      │ shape     │  │ + shrink   │  │ Settings       │
      └─────┬─────┘  └──────┬─────┘  └────────────────┘
            │               │
     silence/tap       photo taken
            │               │
            ▼               ▼
      ┌──────────┐    ┌──────────┐
      │Transcribe│    │ Listening│ (auto-starts recording
      │ orb spins│    │ with     │  after photo capture)
      └─────┬────┘    │ photo    │
            │         │ attached │
            ▼         └─────┬────┘
      ┌──────────┐          │
      │ Sending  │◀─────────┘
      │ orb spin │
      │ clockwise│
      └─────┬────┘
            │
     POST /command
            │
     ┌──────┴──────┐
     │             │
     ▼             ▼
┌─────────┐  ┌──────────┐
│ Success │  │  Error   │
│ orb pop │  │ orb shake│
│ +scale  │  │ +decay   │
└─────┬───┘  └─────┬────┘
      │            │
      ▼            ▼
  ┌───────────────────┐
  │ Response shown on │
  │ HomeView (typewriter)
  │ + device actions   │
  │ execute locally    │
  └────────────────────┘
```

## Orb States & Animations

```
OrbPhase          MotionState      Visual Behavior
─────────         ───────────      ──────────────────────────
.idle             idle             Gentle breathing, layered sine waves
                                   Soft orbit, noise wander
                  armed            Tighter spring on touch-down
.listening        listening        Morph → microphone shape, 3Hz pulse
.transcribing     thinking         Clockwise spin (1.4-2.2x speed)
                                   Uniform direction, low noise
.sending          thinking         Continue spin, quick envelope
.success          success          Scale pop (sine arch), brightness burst
.error            error            High-freq shake (25Hz) with decay
.cameraTransition idle             Explode → scale down + fade out
```

## Home Widgets — Status

| Widget    | Data Source                  | Status    | Notes                                    |
|-----------|------------------------------|-----------|------------------------------------------|
| Calendar  | `GET /calendar/events`       | LIVE      | Shows next 2 events, fetched on appear   |
| Briefing  | `GET /suggestions/briefing`  | LIVE      | Morning summary from LLM                 |
| Email     | `GET /widgets/data?email`    | LIVE      | Unread count + top 3, needs Google OAuth  |
| Commute   | `GET /widgets/data?commute`  | LIVE      | Google Routes API, needs work/home addr   |
| Weather   | WeatherKit (on-device)       | LIVE      | Uses CoreLocation, no backend needed      |

All widgets are **live and functional**. They show data when:
- **Calendar**: User has Google Calendar connected
- **Email**: User has Gmail connected via Google OAuth
- **Commute**: User has told Osmo their work/home address (stored as user facts/preferences)
- **Weather**: Location permission granted
- **Briefing**: Backend generates based on calendar + context

Widgets are togglable in Control Center → Settings tab. Order/visibility is persisted via `GET/POST /preferences`.

## Backend Command Flow

```
iOS transcript + photo
        │
        ▼
  POST /command ──────► Session Manager (conversation context)
        │
        ▼
  LLM Planner ────────► Builds ActionPlan with tool calls
        │                (uses skill manifests for instructions)
        ▼
  Policy Gate ─────────► Checks if destructive → requiresConfirmation
        │
        ▼
  Executor Router
   ├─ server tools ───► Execute on backend (Google Calendar, Gmail, Routes, etc.)
   └─ device tools ───► Return to iOS for local execution
        │
        ▼
  CommandResponse ────► spokenResponse + deviceActions[]
        │
        ▼
  iOS executes device actions locally:
   • ios_eventkit.*     → EventKitManager
   • ios_reminders.*    → ReminderManager
   • ios_camera.*       → CameraManager (fullScreenCover)
   • ios_messages.*     → MessageManager (MFMessageComposeViewController)
   • ios_music.*        → MusicManager (MusicKit)
   • ios_device.*       → DeviceControlManager (brightness, flashlight)
   • ios_app_launcher.* → AppLauncherManager (URL schemes)
   • ios_translation.*  → TranslationManager (Apple Translation API)
   • ios_navigation.*   → NavigationManager (open Maps)
   • ios_notifications.*→ NotificationManager (local notifications)
```
