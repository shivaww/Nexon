"""
TermuxForge Media Hooks
=========================

Media model discovery and generation via external API endpoints.
Supports image and video generation providers, with results saved
as artifacts on disk.
"""

import asyncio
import json
import logging
import os
import time
from dataclasses import dataclass, field
from typing import Any, Optional

logger = logging.getLogger("termux_forge.media_hooks")

ARTIFACTS_DIR = os.path.expanduser("~/.termux_forge/artifacts/media")


@dataclass
class MediaProvider:
    """
    Configuration for a media generation provider.

    Attributes
    ----------
    name : str
        Provider identifier (e.g., "openai", "stability").
    display_name : str
        Human-readable provider name.
    media_types : list[str]
        Supported media types (e.g., ["image", "video"]).
    base_url : str
        API base URL.
    api_key_env : str
        Environment variable name for the API key.
    models : list[str]
        Available model identifiers.
    available : bool
        Whether the provider is configured and ready.
    """

    name: str
    display_name: str
    media_types: list[str] = field(default_factory=list)
    base_url: str = ""
    api_key_env: str = ""
    models: list[str] = field(default_factory=list)
    available: bool = False

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "displayName": self.display_name,
            "mediaTypes": self.media_types,
            "baseUrl": self.base_url,
            "models": self.models,
            "available": self.available,
        }


# ── Known providers ──────────────────────────────────────────────────

KNOWN_PROVIDERS: list[MediaProvider] = [
    MediaProvider(
        name="openai",
        display_name="OpenAI DALL·E",
        media_types=["image"],
        base_url="https://api.openai.com/v1",
        api_key_env="OPENAI_API_KEY",
        models=["dall-e-3", "dall-e-2"],
    ),
    MediaProvider(
        name="stability",
        display_name="Stability AI",
        media_types=["image"],
        base_url="https://api.stability.ai/v1",
        api_key_env="STABILITY_API_KEY",
        models=["stable-diffusion-xl-1024-v1-0", "stable-diffusion-v1-6"],
    ),
    MediaProvider(
        name="replicate",
        display_name="Replicate",
        media_types=["image", "video"],
        base_url="https://api.replicate.com/v1",
        api_key_env="REPLICATE_API_TOKEN",
        models=["flux-1.1-pro", "sdxl"],
    ),
    MediaProvider(
        name="fal",
        display_name="fal.ai",
        media_types=["image", "video"],
        base_url="https://fal.run",
        api_key_env="FAL_KEY",
        models=["fal-ai/flux/dev", "fal-ai/fast-sdxl"],
    ),
    MediaProvider(
        name="together",
        display_name="Together AI",
        media_types=["image"],
        base_url="https://api.together.xyz/v1",
        api_key_env="TOGETHER_API_KEY",
        models=["stabilityai/stable-diffusion-xl-base-1.0"],
    ),
]


@dataclass
class MediaResult:
    """Result of a media generation request."""

    success: bool
    provider: str
    model: str
    media_type: str
    file_path: str = ""
    url: str = ""
    error: str = ""
    duration: float = 0.0
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "success": self.success,
            "provider": self.provider,
            "model": self.model,
            "mediaType": self.media_type,
            "filePath": self.file_path,
            "url": self.url,
            "error": self.error,
            "duration": round(self.duration, 3),
            "metadata": self.metadata,
        }


class MediaHooks:
    """
    Discovers available media generation providers and generates
    images/videos via their APIs, saving outputs as artifacts.
    """

    def __init__(self) -> None:
        self._providers: dict[str, MediaProvider] = {}
        os.makedirs(ARTIFACTS_DIR, exist_ok=True)

    # ── Discovery ─────────────────────────────────────────────────────

    async def discover_providers(self) -> list[dict[str, Any]]:
        """
        Discover which media providers are configured.

        A provider is considered available if its API key environment
        variable is set.

        Returns
        -------
        list[dict]
            Information about each provider including availability.
        """
        self._providers.clear()

        for provider in KNOWN_PROVIDERS:
            p = MediaProvider(
                name=provider.name,
                display_name=provider.display_name,
                media_types=list(provider.media_types),
                base_url=provider.base_url,
                api_key_env=provider.api_key_env,
                models=list(provider.models),
                available=bool(os.environ.get(provider.api_key_env)),
            )
            self._providers[p.name] = p

        logger.info(
            "Media discovery: %d/%d providers available",
            sum(1 for p in self._providers.values() if p.available),
            len(self._providers),
        )
        return [p.to_dict() for p in self._providers.values()]

    def list_providers(self) -> list[dict[str, Any]]:
        """Return cached provider information."""
        return [p.to_dict() for p in self._providers.values()]

    def get_available_providers(self) -> list[dict[str, Any]]:
        """Return only available (configured) providers."""
        return [p.to_dict() for p in self._providers.values() if p.available]

    # ── Generation ────────────────────────────────────────────────────

    async def generate_image(
        self,
        prompt: str,
        provider: str = "openai",
        model: str | None = None,
        size: str = "1024x1024",
        output_name: str | None = None,
    ) -> MediaResult:
        """
        Generate an image using a media provider API.

        Parameters
        ----------
        prompt : str
            Text description of the image to generate.
        provider : str
            Provider name (default: "openai").
        model : str, optional
            Specific model to use.
        size : str
            Image dimensions (e.g., "1024x1024").
        output_name : str, optional
            Output filename (auto-generated if omitted).

        Returns
        -------
        MediaResult
            Result including file path or error.
        """
        p = self._providers.get(provider)
        if not p:
            return MediaResult(
                success=False, provider=provider, model=model or "",
                media_type="image",
                error=f"Unknown provider: {provider}",
            )

        if not p.available:
            return MediaResult(
                success=False, provider=provider, model=model or "",
                media_type="image",
                error=f"Provider not configured (set {p.api_key_env})",
            )

        api_key = os.environ.get(p.api_key_env, "")
        model = model or (p.models[0] if p.models else "")
        start = time.monotonic()

        try:
            if provider == "openai":
                return await self._openai_generate(
                    api_key, model, prompt, size, output_name,
                )
            elif provider == "stability":
                return await self._stability_generate(
                    api_key, model, prompt, size, output_name,
                )
            else:
                return await self._generic_generate(
                    p, api_key, model, prompt, size, output_name,
                )
        except Exception as exc:
            duration = time.monotonic() - start
            logger.exception("Media generation failed: %s", provider)
            return MediaResult(
                success=False, provider=provider, model=model,
                media_type="image", error=str(exc), duration=duration,
            )

    async def generate_video(
        self,
        prompt: str,
        provider: str = "replicate",
        model: str | None = None,
        output_name: str | None = None,
    ) -> MediaResult:
        """
        Generate a video using a media provider API.

        Parameters
        ----------
        prompt : str
            Text description of the video to generate.
        provider : str
            Provider name.
        model : str, optional
            Specific model.
        output_name : str, optional
            Output filename.
        """
        p = self._providers.get(provider)
        if not p:
            return MediaResult(
                success=False, provider=provider, model=model or "",
                media_type="video",
                error=f"Unknown provider: {provider}",
            )

        if "video" not in p.media_types:
            return MediaResult(
                success=False, provider=provider, model=model or "",
                media_type="video",
                error=f"Provider {provider} does not support video generation",
            )

        if not p.available:
            return MediaResult(
                success=False, provider=provider, model=model or "",
                media_type="video",
                error=f"Provider not configured (set {p.api_key_env})",
            )

        return MediaResult(
            success=False, provider=provider, model=model or "",
            media_type="video",
            error="Video generation requires provider-specific implementation",
        )

    # ── Artifact saving ───────────────────────────────────────────────

    def _save_artifact(
        self,
        data: bytes,
        extension: str,
        name: str | None = None,
    ) -> str:
        """Save binary data as a media artifact file."""
        if not name:
            name = f"media_{int(time.time())}"
        filename = f"{name}.{extension}"
        path = os.path.join(ARTIFACTS_DIR, filename)
        with open(path, "wb") as f:
            f.write(data)
        logger.info("Saved media artifact: %s (%d bytes)", path, len(data))
        return path

    # ── Provider-specific implementations ─────────────────────────────

    async def _openai_generate(
        self,
        api_key: str,
        model: str,
        prompt: str,
        size: str,
        output_name: str | None,
    ) -> MediaResult:
        """Generate an image using OpenAI's DALL·E API."""
        import aiohttp

        start = time.monotonic()
        async with aiohttp.ClientSession() as session:
            async with session.post(
                "https://api.openai.com/v1/images/generations",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": model,
                    "prompt": prompt,
                    "n": 1,
                    "size": size,
                    "response_format": "b64_json",
                },
                timeout=aiohttp.ClientTimeout(total=120),
            ) as resp:
                data = await resp.json()

                if resp.status != 200:
                    return MediaResult(
                        success=False, provider="openai", model=model,
                        media_type="image",
                        error=data.get("error", {}).get("message", str(data)),
                        duration=time.monotonic() - start,
                    )

                import base64
                image_data = base64.b64decode(
                    data["data"][0]["b64_json"]
                )
                path = self._save_artifact(image_data, "png", output_name)

                return MediaResult(
                    success=True, provider="openai", model=model,
                    media_type="image", file_path=path,
                    duration=time.monotonic() - start,
                    metadata={"prompt": prompt, "size": size},
                )

    async def _stability_generate(
        self,
        api_key: str,
        model: str,
        prompt: str,
        size: str,
        output_name: str | None,
    ) -> MediaResult:
        """Generate an image using Stability AI's API."""
        import aiohttp

        start = time.monotonic()
        width, height = (int(x) for x in size.split("x"))

        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"https://api.stability.ai/v1/generation/{model}/text-to-image",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                },
                json={
                    "text_prompts": [{"text": prompt, "weight": 1}],
                    "cfg_scale": 7,
                    "width": width,
                    "height": height,
                    "samples": 1,
                    "steps": 30,
                },
                timeout=aiohttp.ClientTimeout(total=120),
            ) as resp:
                data = await resp.json()

                if resp.status != 200:
                    return MediaResult(
                        success=False, provider="stability", model=model,
                        media_type="image",
                        error=str(data.get("message", data)),
                        duration=time.monotonic() - start,
                    )

                import base64
                image_data = base64.b64decode(
                    data["artifacts"][0]["base64"]
                )
                path = self._save_artifact(image_data, "png", output_name)

                return MediaResult(
                    success=True, provider="stability", model=model,
                    media_type="image", file_path=path,
                    duration=time.monotonic() - start,
                    metadata={"prompt": prompt, "size": size},
                )

    async def _generic_generate(
        self,
        provider: MediaProvider,
        api_key: str,
        model: str,
        prompt: str,
        size: str,
        output_name: str | None,
    ) -> MediaResult:
        """Generic API-based image generation (returns a stub)."""
        return MediaResult(
            success=False,
            provider=provider.name,
            model=model,
            media_type="image",
            error=f"Provider '{provider.name}' requires a custom implementation. "
                  f"Use the OpenAI or Stability providers, or extend MediaHooks.",
        )
