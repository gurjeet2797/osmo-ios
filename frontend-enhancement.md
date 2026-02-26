# Osmo Website Build Prompt

> Use this prompt with a web development agent to build the Osmo marketing/landing site.

---

## Project Overview

Build a single-page marketing website for **Osmo**, a voice-driven calendar assistant iOS app preparing for App Store launch. The site should feel like stepping into the app itself — a cosmic, dark, particle-rich experience using **WebGPU** (with Canvas2D fallback) that mirrors the native iOS UI exactly.

The logo file is at: `/Users/gurjeetsingh/Projects/Osmo/Assets.xcassets/AppIcon.appiconset/osmo_icon.png`
(A glowing white particle ring on pure black — this IS the brand. Use it as favicon, OG image, and hero element.)

---

## Tech Stack

- **Rendering**: WebGPU (primary) with Canvas2D fallback for unsupported browsers
- **Framework**: Vanilla HTML/CSS/JS or lightweight (Astro, 11ty) — no React/Next.js overhead
- **Styling**: CSS custom properties for the design tokens below. No Tailwind.
- **Fonts**: System font stack (`-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", system-ui, sans-serif`) — match iOS exactly. Monospaced text uses `"SF Mono", ui-monospace, monospace`.
- **Hosting**: Static — will deploy to Vercel/Netlify
- **Output directory**: `/Users/gurjeetsingh/Projects/Osmo/website/`

---

## Design System — Exact Values from iOS App

### Color Palette

```css
:root {
  /* Backgrounds */
  --bg-primary: #000000;                    /* Pure black — app background */
  --bg-sheet: rgba(255,255,255,0.06);       /* rgb(15,15,15) — chat sheet, cards */
  --bg-elevated: rgba(255,255,255,0.04);    /* Assistant bubbles, subtle containers */
  --bg-input: rgba(255,255,255,0.06);       /* Input fields, pill buttons */

  /* Text */
  --text-primary: rgba(255,255,255,1.0);    /* Headings, greeting */
  --text-secondary: rgba(255,255,255,0.8);  /* Body text, assistant messages */
  --text-tertiary: rgba(255,255,255,0.6);   /* Sign-in button, secondary info */
  --text-muted: rgba(255,255,255,0.35);     /* Status text, timestamps */
  --text-dim: rgba(255,255,255,0.22);       /* Tagline, subtle labels */
  --text-suggestion: rgba(255,255,255,0.75);/* Suggestion pill text */

  /* Borders */
  --border-subtle: rgba(255,255,255,0.1);   /* Input borders, pill strokes */
  --border-faint: rgba(255,255,255,0.08);   /* Message bubble borders */
  --border-ghost: rgba(255,255,255,0.04);   /* Assistant bubble borders */

  /* Accents */
  --accent-star-hue-min: 0.55;             /* Cool blue — star hue range start */
  --accent-star-hue-max: 0.75;             /* Cyan — star hue range end */
  --accent-star-saturation: 0.3;
  --accent-glow: hsla(234, 30%, 100%, 0.08); /* Touch/interaction glow */

  /* Nebula colors (RGB) */
  --nebula-1: rgba(38, 13, 77, 0.08);      /* rgb(0.15, 0.05, 0.3) */
  --nebula-2: rgba(13, 26, 64, 0.04);      /* rgb(0.05, 0.1, 0.25) */

  /* Semantic */
  --success: rgba(0, 255, 0, 0.8);
  --error: rgba(255, 0, 0, 0.8);
  --recording: rgba(255, 0, 0, 0.8);

  /* Drag handle */
  --handle: rgba(255,255,255,0.25);
}
```

### Typography Scale

| Element | Size | Weight | Tracking | Font |
|---------|------|--------|----------|------|
| Hero greeting ("Hi there") | 32px | 100 (Thin) | 4px | System |
| App name header ("Osmo") | 22px | 700 (Bold) | 0 | System |
| Body text / messages | 15px | 400 | 0 | System |
| Suggestion pills | 14px | 500 (Medium) | 0 | System |
| Tagline ("what can i help with?") | 11px | 300 (Light) | 2px | Monospace |
| Status text | 11px | 500 | 1px | Monospace |
| Subtitle ("ask anything...") | 13px | 400 | 0 | Monospace |
| Category tabs | 11px | 500 | 0 | System |
| Tags | 11px | 500 | 0 | System |
| Section labels ("UPCOMING") | 10px | 600 | 2px | Monospace |

### Spacing & Radii

| Element | Value |
|---------|-------|
| Message bubble corner radius | 20px |
| Sheet corner radius | 28px |
| Control center corner radius | 32px |
| Pill/capsule | 9999px (full capsule) |
| Category content radius | 16px |
| Event card radius | 12px |
| Bubble horizontal padding | 16px |
| Bubble vertical padding | 12px |
| Pill horizontal padding | 18px |
| Pill vertical padding | 11px |
| Sheet horizontal margin | 16px |
| Section content padding | 20-24px |
| Message vertical spacing | 20px |

---

## WebGPU Cosmic Background — Exact Spec

This is the hero. It must match the iOS app's `CosmicBackground` + `ParticleOrb` system.

### Starfield

- **120 stars** scattered across viewport
- Each star has: random position, size (0.6–2.8px), brightness (0.3–1.0), pulse speed (0.5–2.5), drift angle, drift speed (0.1–0.5), hue (0.55–0.75 on HSB scale = blue-to-cyan)
- **Drift motion**: `x += cos(time * driftSpeed + angle) * 2.0`, `y += sin(time * driftSpeed * 0.7 + angle) * 2.0`
- **Pulse**: `brightness * (sin(time * pulseSpeed + phase) * 0.35 + 0.65)`
- **Rendering**: Two concentric radial gradients per star:
  1. **Glow** (outer): Hue-tinted color at 12% opacity → 4% → transparent. Radius = `size * 6 * pulse`
  2. **Core** (inner): White at full alpha → 30% → transparent. Radius = `size * 1.5 * pulse`
- **Staggered entrance**: Each star has reveal delay 0–2.5s, fading in over 0.6s

### Nebula Clouds

- **3 layers** of radial gradients drifting slowly
- Motion: sinusoidal X/Y drift at different speeds per layer (time * 0.04–0.08)
- Colors: deep purple `rgba(38, 13, 77, 0.08)` and deep blue `rgba(13, 26, 64, 0.04)` fading to transparent
- Radius: ~30% of viewport width, oscillating ±10%

### Constellation Lines

- Connect stars within **100px** of each other
- Line opacity: `(1.0 - distance/100) * 0.08` — very subtle
- Line width: 0.3px (use 1px with low opacity on web)
- Color: white
- Fade in at 2.0s after page load, 1.0s transition

### Mouse/Touch Interaction

- On hover/touch, stars within **150px** repel outward with force `(1 - dist/150)^2 * 40`
- Glow appears at cursor: `hsl(234, 30%, 100%)` radial gradient, opacity 2–8%, radius ~60px
- Ease-in: 0.2s, ease-out: 0.8s

### Particle Orb (Hero Element)

- **150 particles** orbiting in a ring formation (matching the Osmo logo)
- **Ring distribution**: Inner ring (radius 12–22), middle (22–32), outer (32–40) — all relative to a 110px radius container
- Each particle: size 0.8–2.2px, brightness 0.4–0.9
- **Orbit**: Each particle orbits at speed 0.3–0.9 rad/s (random direction CW/CCW)
- **Breathing**: Orbit radius pulses `1.0 + sin(time * 0.5 + phase) * 0.12`
- **Noise wander**: Perlin-style displacement, strength 6px, speed 1.2
- **Rendering**: Same two-gradient approach as stars (glow + core)
- **Idle bob**: Whole orb sways `sin(time * 0.6) * 2 + sin(time * 1.1) * 1` pixels vertically
- **On hover**: Particles scatter slightly (spring physics, stiffness 5.0, damping 2.8), then reform
- Canvas size: 220x220px, 60fps

---

## Page Structure & Sections

### 1. Hero Section (Full Viewport)

The cosmic background fills the entire viewport. Centered content:

```
[Particle Orb — animated, interactive]

          O s m o
    ——— (60px line) ———
  what can i help with?
```

- "Osmo" in 32px thin, letter-spacing 4px, white — fades in from blur (blur 8px→0, scale 0.88→1.0, 1.8s easeOut)
- Horizontal divider: 60px wide, 0.5px height, gradient `transparent → white 12% → transparent` — extends from 0→60px width (1.0s easeOut, 0.6s delay)
- Tagline: 11px light monospace, white 22% opacity — fades in (0.8s easeOut, 1.0s delay)
- Particle orb: fades in (1.2s easeOut, 1.6s delay)
- Scroll indicator at bottom: subtle animated chevron

### 2. "Your Calendar, Your Voice" Section

Dark section with subtle card showing a mock chat interaction:

```
[Mock phone frame with chat UI]

Left side text:
  VOICE-FIRST CALENDAR
  Schedule meetings, check your day,
  and manage events — just by speaking.

  [Suggestion pills from the app]:
  "What's on my calendar today?"
  "Schedule a meeting tomorrow at 2pm"
  "Find free time this week"
```

The mock chat shows the greeting message:
> "Hey! I'm Osmo, your personal calendar assistant. Try saying 'Schedule a meeting tomorrow at 2pm' or tap the mic to get started."

Style the suggestion pills exactly as the app: 14px medium, white 75% opacity, capsule bg white 6%, border white 10%, 0.5px stroke, 18px h-padding, 11px v-padding.

### 3. Features Grid

Three feature cards with glassmorphism styling (bg white 6%, border white 10%, 0.5px stroke, 28px radius):

1. **Voice Commands** — mic icon, "Speak naturally. Osmo understands context, relative dates, and your intent."
2. **Google Calendar Sync** — calendar icon, "Connect your Google account. Create, update, and manage events seamlessly."
3. **Smart Scheduling** — sparkles icon, "Find free time, avoid conflicts, and let Osmo handle the details."

Cards use the app's glass effect: `backdrop-filter: blur(20px)` + white 6% fill + white 10% border.

### 4. "How It Works" Section

Three-step flow with connecting lines:

1. **Sign in with Google** — "Connect your calendar in one tap"
2. **Talk to Osmo** — "Use voice or text to describe what you need"
3. **It just works** — "Events created, schedule checked, conflicts resolved"

Each step number styled as a small orb (particle ring motif).

### 5. App Preview Section

Show a styled iPhone mockup with the HomeView screenshot aesthetic:
- Pure black background with cosmic stars
- Greeting text "Hi, [Name]" centered
- Particle orb at bottom
- "Coming to the App Store" badge below

### 6. Footer / CTA

```
          [Osmo Logo - particle ring]
                  Osmo
          Your voice. Your calendar.

     [Notify Me When It Launches] (email input + button)

     Privacy Policy · Terms · Contact
```

Email input styled as the app's input bar: capsule, white 6% bg, white 10% border, 15px text.
Submit button: capsule, white 90% text when filled, white 15% when empty.

---

## Animations & Interactions

### Scroll-Triggered

- Each section fades in + slides up 20px on scroll (IntersectionObserver)
- Feature cards stagger 0.15s apart
- Use the app's spring timing: `cubic-bezier(0.32, 0.72, 0, 1)` (approximates spring response 0.5, damping 0.78)

### Hover States

- Suggestion pills: bg → white 10%, border → white 15%, 0.2s transition
- Feature cards: border → white 15%, subtle scale 1.02, 0.3s transition
- CTA button: bg → white 12%, 0.2s transition
- Links: opacity 0.6 → 1.0

### Particle Orb Interactivity

- On hover: particles spread outward slightly (spring physics), glow intensifies
- On click: particles scatter then reform (morph duration 0.35s, quintic easing `t*t*t*(t*(t*6-15)+10)`)
- Continuous idle animation: orbiting + breathing + noise wander

---

## SEO & Meta

```html
<title>Osmo — Voice-Driven Calendar Assistant</title>
<meta name="description" content="Schedule meetings, check your day, and manage your calendar — just by speaking. Osmo is the voice-first calendar assistant for iOS.">
<meta property="og:title" content="Osmo — Your Voice, Your Calendar">
<meta property="og:description" content="The voice-first calendar assistant for iOS. Coming soon to the App Store.">
<meta property="og:image" content="/og-image.png"> <!-- Generate from Osmo logo on cosmic bg, 1200x630 -->
<meta property="og:type" content="website">
<meta name="theme-color" content="#000000">
<link rel="icon" type="image/png" href="/favicon.png"> <!-- Osmo logo -->
```

---

## Performance Requirements

- WebGPU with Canvas2D fallback (detect via `navigator.gpu`)
- Particle system at 60fps on modern hardware
- Reduce particle count on mobile (80 stars, 100 orb particles)
- `prefers-reduced-motion`: disable particle animation, show static star image
- Lazy-load below-fold sections
- Total page weight < 500KB (excluding WebGPU shaders)
- Core Web Vitals: LCP < 2.5s, CLS < 0.1

---

## File Structure

```
website/
  index.html
  css/
    tokens.css          (design tokens from above)
    main.css            (layout, typography, components)
  js/
    cosmic-bg.js        (WebGPU starfield + nebula + constellations)
    particle-orb.js     (WebGPU orb with physics)
    canvas-fallback.js  (Canvas2D fallback)
    animations.js       (scroll triggers, entrance sequence)
    email-signup.js     (newsletter form handling)
  shaders/
    starfield.wgsl      (WebGPU compute + render shaders)
    particle.wgsl       (Orb particle shaders)
  assets/
    osmo-logo.png       (from app assets)
    og-image.png        (1200x630 generated)
    favicon.png         (32x32 from logo)
  fonts/                (empty — using system fonts)
```

---

## Key Principle

**Everything should feel like the iOS app rendered in a browser.** Same colors, same opacities, same animation timings, same spatial relationships. A user should go from the website to the app and feel zero visual discontinuity. The cosmic background IS the brand — it's not decoration, it's the entire experience.
