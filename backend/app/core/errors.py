"""One consistent error format for the whole API.

Every error response looks like:
    {"error": {"code": "invalid_credentials", "message": "Email or password is incorrect."}}
"""
from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse


class ApiError(Exception):
    def __init__(self, status_code: int, code: str, message: str):
        self.status_code = status_code
        self.code = code
        self.message = message


def _body(code: str, message: str, details=None) -> dict:
    error = {"code": code, "message": message}
    if details is not None:
        error["details"] = details
    return {"error": error}


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def handle_api_error(_: Request, exc: ApiError):
        return JSONResponse(status_code=exc.status_code, content=_body(exc.code, exc.message))

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(_: Request, exc: RequestValidationError):
        details = [
            {"field": ".".join(str(p) for p in err["loc"][1:]), "message": err["msg"]}
            for err in exc.errors()
        ]
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            content=_body("validation_error", "Some fields are invalid.", details),
        )

    @app.exception_handler(Exception)
    async def handle_unexpected(request: Request, exc: Exception):
        # Full details go to the backend window and backend/logs/errors.log (never to the user).
        import traceback
        from datetime import datetime
        from pathlib import Path

        text = "".join(traceback.format_exception(type(exc), exc, exc.__traceback__))
        try:
            print(f"[ERROR] {request.method} {request.url.path}\n{text}")
        except UnicodeEncodeError:
            print(f"[ERROR] {request.method} {request.url.path} (see logs/errors.log)")
        try:
            log = Path(__file__).resolve().parents[2] / "logs" / "errors.log"
            log.parent.mkdir(exist_ok=True)
            with log.open("a", encoding="utf-8") as f:
                f.write(f"--- {datetime.now().isoformat()} {request.method} {request.url.path}\n{text}\n")
        except OSError:
            pass
        # Never leak internal details (or health data) in error messages.
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content=_body("server_error", "Something went wrong. Please try again."),
        )
