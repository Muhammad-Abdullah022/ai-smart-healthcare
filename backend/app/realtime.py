"""Live updates over WebSocket (online consultations).

Each logged-in app opens one socket: ws://host/ws?token=<access token>.
The server pushes small JSON events to the patient and the doctor of a consultation the moment
something happens (new message, payment uploaded, prescription sent ...). Everything is also saved in
MongoDB, so an app that was offline simply reloads the conversation.
"""
import asyncio
import json

import jwt
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.core.security import decode_token

router = APIRouter(tags=["realtime"])


class Hub:
    def __init__(self) -> None:
        self._sockets: dict[str, set[WebSocket]] = {}

    def add(self, user_id: str, ws: WebSocket) -> None:
        self._sockets.setdefault(user_id, set()).add(ws)

    def remove(self, user_id: str, ws: WebSocket) -> None:
        self._sockets.get(user_id, set()).discard(ws)
        if not self._sockets.get(user_id):
            self._sockets.pop(user_id, None)

    def online(self, user_id) -> bool:
        return bool(self._sockets.get(str(user_id)))

    async def send(self, user_ids, event: dict) -> None:
        text = json.dumps(event, default=str)
        for uid in {str(u) for u in user_ids if u}:
            for ws in list(self._sockets.get(uid, ())):
                try:
                    await ws.send_text(text)
                except Exception:  # closed tab / lost network
                    self.remove(uid, ws)


hub = Hub()


@router.websocket("/ws")
async def live(ws: WebSocket):
    token = ws.query_params.get("token", "")
    try:
        user_id = decode_token(token, expected_type="access")["sub"]
    except jwt.InvalidTokenError:
        await ws.close(code=4401)
        return
    await ws.accept()
    hub.add(user_id, ws)
    await ws.send_text(json.dumps({"type": "hello"}))
    try:
        while True:
            # The app sends "ping" every ~25 s so proxies keep the connection open.
            msg = await asyncio.wait_for(ws.receive_text(), timeout=120)
            if msg == "ping":
                await ws.send_text('{"type":"pong"}')
    except (WebSocketDisconnect, asyncio.TimeoutError, RuntimeError):
        pass
    finally:
        hub.remove(user_id, ws)
