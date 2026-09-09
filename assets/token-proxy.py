#!/usr/bin/env python3
"""Transparent Anthropic-compatible proxy that stores token metadata only."""

from __future__ import annotations

import argparse
import asyncio
import json
import time
from datetime import datetime, timezone
from pathlib import Path

from aiohttp import ClientSession, ClientTimeout, web

AGENTS = {"manager", "graph", "developer", "reviewer"}
HOP_BY_HOP_HEADERS = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailers", "transfer-encoding", "upgrade"}


def parse_usage(payload: bytes) -> dict[str, int | None]:
    usage: dict[str, int | None] = {"input_tokens": None, "output_tokens": None}
    documents: list[object] = []
    try:
        documents.append(json.loads(payload))
    except (UnicodeDecodeError, json.JSONDecodeError):
        for line in payload.splitlines():
            if line.startswith(b"data:"):
                try:
                    documents.append(json.loads(line[5:].strip()))
                except (UnicodeDecodeError, json.JSONDecodeError):
                    pass
    for document in documents:
        if not isinstance(document, dict):
            continue
        candidate = document.get("usage")
        if isinstance(candidate, dict):
            for key in usage:
                value = candidate.get(key)
                if isinstance(value, int):
                    usage[key] = value
    return usage


def append_metric(path: Path, metric: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as destination:
        destination.write(json.dumps(metric, ensure_ascii=False, separators=(",", ":")) + "\n")


async def health(_: web.Request) -> web.Response:
    return web.json_response({"status": "ok"})


async def agent_health(request: web.Request) -> web.Response:
    if request.match_info["agent"] not in AGENTS:
        raise web.HTTPNotFound()
    return web.json_response({"status": "ok"})


async def forward(request: web.Request) -> web.StreamResponse:
    agent = request.match_info["agent"]
    if agent not in AGENTS:
        raise web.HTTPNotFound()
    tail = request.match_info.get("tail", "")
    upstream = request.app["upstream"].rstrip("/") + "/" + tail
    if request.query_string:
        upstream += "?" + request.query_string
    body = await request.read()
    model = None
    try:
        document = json.loads(body)
        if isinstance(document, dict) and isinstance(document.get("model"), str):
            model = document["model"]
    except (UnicodeDecodeError, json.JSONDecodeError):
        pass
    headers = {key: value for key, value in request.headers.items() if key.lower() not in HOP_BY_HOP_HEADERS | {"host", "content-length"}}
    started = time.monotonic()
    async with request.app["client"].request(request.method, upstream, data=body, headers=headers) as response:
        response_headers = {key: value for key, value in response.headers.items() if key.lower() not in HOP_BY_HOP_HEADERS | {"content-length"}}
        downstream = web.StreamResponse(status=response.status, reason=response.reason, headers=response_headers)
        await downstream.prepare(request)
        chunks: list[bytes] = []
        async for chunk in response.content.iter_chunked(65536):
            chunks.append(chunk)
            await downstream.write(chunk)
        await downstream.write_eof()
    usage = parse_usage(b"".join(chunks))
    metric: dict[str, object] = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "agent": agent,
        "model": model,
        "input_tokens": usage["input_tokens"],
        "output_tokens": usage["output_tokens"],
        "duration_ms": round((time.monotonic() - started) * 1000),
    }
    attribution = read_active_task(request.app["active_task"])
    if attribution:
        metric.update(attribution)
    append_metric(request.app["metrics"], metric)
    return downstream


def read_active_task(path: Path) -> dict[str, object]:
    """Read .ccb/token-monitor/active-task and return a small attribution dict.

    The file is plain JSON with three keys only: task_id, initial_complexity,
    current_complexity. No prompt, no content, no secrets. It is the single
    source of truth for attribution because the official global CCB launches
    the per-agent Claude Code processes and does not propagate custom
    request headers from this template.
    """
    try:
        with path.open("r", encoding="utf-8") as source:
            document = json.load(source)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}
    if not isinstance(document, dict):
        return {}
    attribution: dict[str, object] = {}
    task_id = document.get("task_id")
    if isinstance(task_id, str) and task_id:
        attribution["task_id"] = task_id
    initial = document.get("initial_complexity")
    if isinstance(initial, str) and initial:
        attribution["initial_complexity"] = initial
    current = document.get("current_complexity")
    if isinstance(current, str) and current:
        attribution["complexity"] = current
        attribution["current_complexity"] = current
    return attribution


async def cleanup(app: web.Application) -> None:
    await app["client"].close()


async def startup(app: web.Application) -> None:
    app["client"] = ClientSession(timeout=ClientTimeout(total=None))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", required=True)
    parser.add_argument("--metrics", required=True, type=Path)
    parser.add_argument("--port", required=True, type=int)
    parser.add_argument("--active-task", required=True, type=Path)
    arguments = parser.parse_args()
    app = web.Application()
    app["upstream"] = arguments.upstream
    app["metrics"] = arguments.metrics
    app["active_task"] = arguments.active_task
    app.on_startup.append(startup)
    app.on_cleanup.append(cleanup)
    app.router.add_get("/health", health)
    app.router.add_get("/{agent}", agent_health)
    app.router.add_get("/{agent}/", agent_health)
    app.router.add_route("*", "/{agent}/{tail:.*}", forward)
    web.run_app(app, host="127.0.0.1", port=arguments.port, print=None)


if __name__ == "__main__":
    main()
