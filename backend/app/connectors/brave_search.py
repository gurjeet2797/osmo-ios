from __future__ import annotations

from typing import Any

import httpx
import structlog

from app.config import settings

log = structlog.get_logger()

BRAVE_SEARCH_URL = "https://api.search.brave.com/res/v1/web/search"


class BraveSearchClient:
    """Thin wrapper around the Brave Web Search API."""

    def __init__(self, api_key: str | None = None):
        self._api_key = api_key or settings.brave_search_api_key
        if not self._api_key:
            raise RuntimeError("BRAVE_SEARCH_API_KEY is not configured")

    async def search(
        self,
        query: str,
        count: int = 5,
        country: str | None = None,
        search_lang: str | None = None,
        result_filter: str | None = None,
    ) -> list[dict[str, Any]]:
        """Search the web using Brave Search.

        Args:
            query: Search query string.
            count: Number of results (max 20).
            country: Country code for results (e.g. 'US').
            search_lang: Language code (e.g. 'en').
            result_filter: Filter type (e.g. 'web', 'news').

        Returns:
            List of result dicts with title, url, description.
        """
        params: dict[str, Any] = {
            "q": query,
            "count": min(count, 20),
        }
        if country:
            params["country"] = country
        if search_lang:
            params["search_lang"] = search_lang
        if result_filter:
            params["result_filter"] = result_filter

        headers = {
            "Accept": "application/json",
            "Accept-Encoding": "gzip",
            "X-Subscription-Token": self._api_key,
        }

        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(BRAVE_SEARCH_URL, params=params, headers=headers)
            resp.raise_for_status()
            data = resp.json()

        results = []
        for item in data.get("web", {}).get("results", []):
            results.append({
                "title": item.get("title", ""),
                "url": item.get("url", ""),
                "description": item.get("description", ""),
            })

        return results[:count]
