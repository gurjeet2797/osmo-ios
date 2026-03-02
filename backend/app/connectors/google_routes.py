from __future__ import annotations

from datetime import datetime
from typing import Any

import httpx
import structlog

from app.config import settings

log = structlog.get_logger()

ROUTES_API_URL = "https://routes.googleapis.com/directions/v2:computeRoutes"


class GoogleRoutesClient:
    """Thin wrapper around the Google Routes API (REST)."""

    def __init__(self, api_key: str | None = None):
        self._api_key = api_key or settings.google_routes_api_key
        if not self._api_key:
            raise RuntimeError("GOOGLE_ROUTES_API_KEY is not configured")

    async def compute_route(
        self,
        origin: str,
        destination: str,
        travel_mode: str = "DRIVE",
        departure_time: str | None = None,
        arrival_time: str | None = None,
    ) -> dict[str, Any]:
        """Compute a route between origin and destination.

        Args:
            origin: Origin address or "lat,lng" string.
            destination: Destination address or "lat,lng" string.
            travel_mode: DRIVE, TRANSIT, WALK, BICYCLE.
            departure_time: ISO-8601 timestamp for departure.
            arrival_time: ISO-8601 timestamp for desired arrival.

        Returns:
            Dict with duration, distance, summary, and polyline.
        """
        body: dict[str, Any] = {
            "origin": _waypoint(origin),
            "destination": _waypoint(destination),
            "travelMode": travel_mode.upper(),
            "routingPreference": "TRAFFIC_AWARE" if travel_mode.upper() == "DRIVE" else "ROUTING_PREFERENCE_UNSPECIFIED",
            "computeAlternativeRoutes": False,
        }

        if departure_time:
            body["departureTime"] = departure_time
        if arrival_time and travel_mode.upper() == "TRANSIT":
            body["arrivalTime"] = arrival_time

        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": self._api_key,
            "X-Goog-FieldMask": "routes.duration,routes.distanceMeters,routes.description,routes.polyline.encodedPolyline,routes.legs.steps.navigationInstruction",
        }

        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.post(ROUTES_API_URL, json=body, headers=headers)
            resp.raise_for_status()
            data = resp.json()

        routes = data.get("routes", [])
        if not routes:
            return {"error": "No route found"}

        route = routes[0]
        duration_str = route.get("duration", "0s")
        duration_seconds = _parse_duration(duration_str)
        distance_meters = route.get("distanceMeters", 0)

        # Extract turn-by-turn instructions
        steps = []
        for leg in route.get("legs", []):
            for step in leg.get("steps", []):
                nav = step.get("navigationInstruction", {})
                if nav.get("instructions"):
                    steps.append(nav["instructions"])

        return {
            "duration_seconds": duration_seconds,
            "duration_text": _format_duration(duration_seconds),
            "distance_meters": distance_meters,
            "distance_text": _format_distance(distance_meters),
            "description": route.get("description", ""),
            "steps": steps[:15],  # Limit to keep context manageable
        }


def _waypoint(location: str) -> dict[str, Any]:
    """Build a waypoint from an address string or 'lat,lng' coordinate pair."""
    parts = location.split(",")
    if len(parts) == 2:
        try:
            lat, lng = float(parts[0].strip()), float(parts[1].strip())
            return {"location": {"latLng": {"latitude": lat, "longitude": lng}}}
        except ValueError:
            pass
    return {"address": location}


def _parse_duration(d: str) -> int:
    """Parse Google's duration string like '1234s' into seconds."""
    return int(d.rstrip("s")) if d.endswith("s") else 0


def _format_duration(seconds: int) -> str:
    """Format seconds into human-readable duration."""
    if seconds < 60:
        return f"{seconds} seconds"
    minutes = seconds // 60
    if minutes < 60:
        return f"{minutes} min"
    hours = minutes // 60
    remaining = minutes % 60
    if remaining == 0:
        return f"{hours} hr"
    return f"{hours} hr {remaining} min"


def _format_distance(meters: int) -> str:
    """Format meters into human-readable distance (miles)."""
    miles = meters / 1609.34
    if miles < 0.1:
        feet = meters * 3.28084
        return f"{int(feet)} ft"
    return f"{miles:.1f} mi"
