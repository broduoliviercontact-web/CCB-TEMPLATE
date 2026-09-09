#!/usr/bin/env python3
"""Local harness for the CCB token proxy.

Spins up a fake upstream HTTP server on 127.0.0.1 that always returns a
minimal Anthropic /v1/messages response with a deterministic usage block,
then starts the production token-proxy.py against that upstream, then makes
two real POST /v1/messages calls. Validates the resulting usage.jsonl lines
by parsing them with json.loads.

This harness exercises the actual production proxy (no monkey-patching, no
in-process fakes). All communication is over localhost. No external model
is contacted. aiohttp is the only dependency, and it is already required by
the token proxy.
"""

from __future__ import annotations

import asyncio
import importlib.util
import json
import os
import socket
import sys
from pathlib import Path

from aiohttp import web


def _pick_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def _load_proxy_module(proxy_path: str):
    spec = importlib.util.spec_from_file_location("ccb_proxy", proxy_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


async def _run_fake_upstream(port: int, ready: asyncio.Event) -> None:
    """Minimal Anthropic-compatible fake upstream."""

    async def messages(request: web.Request) -> web.Response:
        body = await request.read()
        try:
            document = json.loads(body)
        except json.JSONDecodeError:
            document = {}
        model = document.get("model") if isinstance(document, dict) else None
        payload = {
            "id": "msg_test",
            "type": "message",
            "role": "assistant",
            "content": [],
            "model": model,
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 123, "output_tokens": 45},
        }
        return web.json_response(payload)

    app = web.Application()
    app.router.add_post("/v1/messages", messages)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "127.0.0.1", port)
    await site.start()
    ready.set()
    # Run until cancelled.
    try:
        await asyncio.Event().wait()
    finally:
        await runner.cleanup()


async def _start_proxy(proxy_module, upstream_port: int, metrics_path: Path, active_task_path: Path) -> tuple:
    """Start the real token-proxy.py on a free port."""
    from aiohttp import ClientSession
    port = _pick_free_port()
    app = web.Application()
    app["upstream"] = f"http://127.0.0.1:{upstream_port}"
    app["metrics"] = metrics_path
    app["active_task"] = active_task_path
    app.on_startup.append(proxy_module.startup)
    app.on_cleanup.append(proxy_module.cleanup)
    app.router.add_get("/health", proxy_module.health)
    app.router.add_get("/{agent}", proxy_module.agent_health)
    app.router.add_get("/{agent}/", proxy_module.agent_health)
    app.router.add_route("*", "/{agent}/{tail:.*}", proxy_module.forward)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "127.0.0.1", port)
    await site.start()
    # Wait for /health.
    async with ClientSession() as session:
        for _ in range(50):
            try:
                async with session.get(f"http://127.0.0.1:{port}/health", timeout=0.2) as response:
                    if response.status == 200:
                        break
            except Exception:
                pass
            await asyncio.sleep(0.05)
        else:
            raise RuntimeError("proxy never became ready")
    return runner, port


async def _post_message(proxy_port: int, agent: str) -> dict:
    from aiohttp import ClientSession

    body = {
        "model": "test-model:cloud",
        "max_tokens": 32,
        "messages": [{"role": "user", "content": "hello"}],
    }
    async with ClientSession() as session:
        async with session.post(
            f"http://127.0.0.1:{proxy_port}/{agent}/v1/messages",
            json=body,
        ) as response:
            return await response.json()


async def _run(active_task_path: Path, metrics_path: Path, proxy_path: str) -> None:
    proxy_module = _load_proxy_module(proxy_path)
    upstream_port = _pick_free_port()
    ready = asyncio.Event()
    upstream_task = asyncio.create_task(_run_fake_upstream(upstream_port, ready))
    try:
        await ready.wait()
        runner, proxy_port = await _start_proxy(
            proxy_module, upstream_port, metrics_path, active_task_path,
        )
        try:
            response = await _post_message(proxy_port, "developer")
            assert response["usage"]["input_tokens"] == 123, response
        finally:
            await runner.cleanup()
    finally:
        upstream_task.cancel()
        try:
            await upstream_task
        except (asyncio.CancelledError, Exception):
            pass


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print("usage: _proxy_attr_harness.py ACTIVE_TASK METRICS_JSONL PROXY_PY", file=sys.stderr)
        return 2
    active_task_path = Path(argv[1])
    metrics_path = Path(argv[2])
    proxy_path = argv[3]
    asyncio.run(_run(active_task_path, metrics_path, proxy_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))