"""
TermuxForge JSON-RPC 2.0 Protocol
===================================

Implements the JSON-RPC 2.0 specification for communication between
the Flutter app and the Python bridge over WebSocket.

See: https://www.jsonrpc.org/specification
"""

import json
import logging
import os
from dataclasses import dataclass, field
from enum import IntEnum
from typing import Any, Callable, Coroutine, Optional

logger = logging.getLogger("termux_forge.protocol")


# ── JSON-RPC 2.0 Error Codes ─────────────────────────────────────────

class ErrorCode(IntEnum):
    """Standard and custom JSON-RPC 2.0 error codes."""

    # Standard JSON-RPC 2.0 errors
    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603

    # Custom TermuxForge errors (-32000 to -32099)
    COMMAND_BLOCKED = -32001
    COMMAND_TIMEOUT = -32002
    COMMAND_FAILED = -32003
    FILE_NOT_FOUND = -32004
    PERMISSION_DENIED = -32005
    TOOL_NOT_FOUND = -32006
    MCP_ERROR = -32007
    WORKFLOW_ERROR = -32008
    CHECKPOINT_ERROR = -32009
    GITHUB_ERROR = -32010
    MEDIA_ERROR = -32011
    VALIDATION_ERROR = -32012
    APPROVAL_REQUIRED = -32013


ERROR_MESSAGES: dict[int, str] = {
    ErrorCode.PARSE_ERROR: "Parse error",
    ErrorCode.INVALID_REQUEST: "Invalid request",
    ErrorCode.METHOD_NOT_FOUND: "Method not found",
    ErrorCode.INVALID_PARAMS: "Invalid params",
    ErrorCode.INTERNAL_ERROR: "Internal error",
    ErrorCode.COMMAND_BLOCKED: "Command blocked by security policy",
    ErrorCode.COMMAND_TIMEOUT: "Command timed out",
    ErrorCode.COMMAND_FAILED: "Command execution failed",
    ErrorCode.FILE_NOT_FOUND: "File not found",
    ErrorCode.PERMISSION_DENIED: "Permission denied",
    ErrorCode.TOOL_NOT_FOUND: "Tool not found",
    ErrorCode.MCP_ERROR: "MCP server error",
    ErrorCode.WORKFLOW_ERROR: "Workflow execution error",
    ErrorCode.CHECKPOINT_ERROR: "Checkpoint operation error",
    ErrorCode.GITHUB_ERROR: "GitHub operation error",
    ErrorCode.MEDIA_ERROR: "Media operation error",
    ErrorCode.VALIDATION_ERROR: "Validation error",
    ErrorCode.APPROVAL_REQUIRED: "Approval required for this operation",
}


# ── Data Classes ──────────────────────────────────────────────────────

@dataclass
class JsonRpcRequest:
    """
    Represents an incoming JSON-RPC 2.0 request.

    Attributes
    ----------
    method : str
        The RPC method name to invoke.
    params : dict | list | None
        Positional or named parameters for the method.
    id : str | int | None
        Request identifier (None for notifications).
    jsonrpc : str
        Protocol version (must be "2.0").
    """

    method: str
    params: dict | list | None = None
    id: str | int | None = None
    jsonrpc: str = "2.0"

    @classmethod
    def from_dict(cls, data: dict) -> "JsonRpcRequest":
        """
        Parse a JSON-RPC request from a dictionary.

        Raises
        ------
        JsonRpcError
            If the request is malformed.
        """
        if not isinstance(data, dict):
            raise JsonRpcError(
                code=ErrorCode.INVALID_REQUEST,
                message="Request must be a JSON object",
            )

        jsonrpc = data.get("jsonrpc")
        if jsonrpc != "2.0":
            raise JsonRpcError(
                code=ErrorCode.INVALID_REQUEST,
                message='Missing or invalid "jsonrpc" field (must be "2.0")',
            )

        method = data.get("method")
        if not isinstance(method, str) or not method:
            raise JsonRpcError(
                code=ErrorCode.INVALID_REQUEST,
                message='Missing or invalid "method" field',
            )

        params = data.get("params")
        if params is not None and not isinstance(params, (dict, list)):
            raise JsonRpcError(
                code=ErrorCode.INVALID_PARAMS,
                message='"params" must be an object or array',
            )

        return cls(
            method=method,
            params=params,
            id=data.get("id"),
            jsonrpc=jsonrpc,
        )

    @classmethod
    def from_json(cls, raw: str) -> "JsonRpcRequest":
        """
        Parse a JSON-RPC request from a raw JSON string.

        Raises
        ------
        JsonRpcError
            If the JSON is malformed or the request is invalid.
        """
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise JsonRpcError(
                code=ErrorCode.PARSE_ERROR,
                message=f"Invalid JSON: {exc}",
            )
        return cls.from_dict(data)

    def is_notification(self) -> bool:
        """Return True if this request is a notification (no id)."""
        return self.id is None


@dataclass
class JsonRpcResponse:
    """
    Represents a JSON-RPC 2.0 response.

    Either ``result`` or ``error`` must be set, never both.
    """

    id: str | int | None
    result: Any = None
    error: Optional[dict] = None
    jsonrpc: str = "2.0"

    def to_dict(self) -> dict:
        """Serialize the response to a dictionary."""
        response: dict[str, Any] = {
            "jsonrpc": self.jsonrpc,
            "id": self.id,
        }
        if self.error is not None:
            response["error"] = self.error
        else:
            response["result"] = self.result
        return response

    def to_json(self) -> str:
        """Serialize the response to a JSON string."""
        return json.dumps(self.to_dict(), default=str)


class JsonRpcError(Exception):
    """
    JSON-RPC 2.0 error with code, message, and optional data.

    Can be raised inside method handlers to send structured errors
    back to the client.
    """

    def __init__(
        self,
        code: int | ErrorCode,
        message: str | None = None,
        data: Any = None,
    ) -> None:
        self.code = int(code)
        self.message = message or ERROR_MESSAGES.get(self.code, "Unknown error")
        self.data = data
        super().__init__(self.message)

    def to_dict(self) -> dict:
        """Serialize to a JSON-RPC error object."""
        error: dict[str, Any] = {
            "code": self.code,
            "message": self.message,
        }
        if self.data is not None:
            error["data"] = self.data
        return error


# ── Method Handler Type ───────────────────────────────────────────────

MethodHandler = Callable[..., Coroutine[Any, Any, Any]]


# ── Method Router ─────────────────────────────────────────────────────

class MethodRouter:
    """
    Routes JSON-RPC method names to async handler functions.

    Usage::

        router = MethodRouter()

        @router.method("echo")
        async def echo(params):
            return params

        result = await router.dispatch(request)
    """

    def __init__(self) -> None:
        self._methods: dict[str, MethodHandler] = {}

    def method(self, name: str) -> Callable[[MethodHandler], MethodHandler]:
        """
        Decorator to register an async method handler.

        Parameters
        ----------
        name : str
            The JSON-RPC method name.
        """
        def decorator(func: MethodHandler) -> MethodHandler:
            self._methods[name] = func
            return func
        return decorator

    def register(self, name: str, handler: MethodHandler) -> None:
        """Register a handler function for a method name."""
        self._methods[name] = handler

    def has_method(self, name: str) -> bool:
        """Check if a method is registered."""
        return name in self._methods

    def list_methods(self) -> list[str]:
        """Return all registered method names."""
        return sorted(self._methods.keys())

    async def dispatch(self, request: JsonRpcRequest) -> JsonRpcResponse:
        """
        Dispatch a JSON-RPC request to the appropriate handler.

        Parameters
        ----------
        request : JsonRpcRequest
            The parsed request.

        Returns
        -------
        JsonRpcResponse
            The response with either a result or an error.
        """
        handler = self._methods.get(request.method)
        if handler is None:
            logger.warning("Method not found: %s", request.method)
            return JsonRpcResponse(
                id=request.id,
                error=JsonRpcError(
                    code=ErrorCode.METHOD_NOT_FOUND,
                    message=f"Method not found: {request.method}",
                    data={"available_methods": self.list_methods()},
                ).to_dict(),
            )

        try:
            if isinstance(request.params, dict):
                # Pre-process parameters to expand tilde paths ('~') for path-related arguments
                path_keys = {'path', 'cwd', 'directory', 'dir', 'dir_path', 'dest', 'src', 'path_a', 'path_b', 'output_dir'}
                processed_params = {}
                for k, v in request.params.items():
                    if k in path_keys and isinstance(v, str):
                        processed_params[k] = os.path.expanduser(v)
                    else:
                        processed_params[k] = v
                result = await handler(**processed_params)
            elif isinstance(request.params, list):
                result = await handler(*request.params)
            else:
                result = await handler()
            return JsonRpcResponse(id=request.id, result=result)
        except JsonRpcError as exc:
            logger.error("RPC error in %s: %s", request.method, exc.message)
            return JsonRpcResponse(id=request.id, error=exc.to_dict())
        except TypeError as exc:
            logger.error("Invalid params for %s: %s", request.method, exc)
            return JsonRpcResponse(
                id=request.id,
                error=JsonRpcError(
                    code=ErrorCode.INVALID_PARAMS,
                    message=str(exc),
                ).to_dict(),
            )
        except Exception as exc:
            logger.exception("Internal error in %s", request.method)
            return JsonRpcResponse(
                id=request.id,
                error=JsonRpcError(
                    code=ErrorCode.INTERNAL_ERROR,
                    message=str(exc),
                ).to_dict(),
            )


# ── Helpers ───────────────────────────────────────────────────────────

def success_response(request_id: Any, result: Any) -> str:
    """Build a success JSON-RPC response string."""
    return JsonRpcResponse(id=request_id, result=result).to_json()


def error_response(
    request_id: Any,
    code: int | ErrorCode,
    message: str | None = None,
    data: Any = None,
) -> str:
    """Build an error JSON-RPC response string."""
    return JsonRpcResponse(
        id=request_id,
        error=JsonRpcError(code=code, message=message, data=data).to_dict(),
    ).to_json()
