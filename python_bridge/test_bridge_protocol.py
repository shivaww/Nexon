"""
TermuxForge — Cross-Bridge Protocol Conformance Tests (Python side)
====================================================================

Verifies that the Python bridge's error codes, method names, and protocol
shapes are consistent with the Flutter side (bridge_schema.dart).

Run:  python -m pytest test_bridge_protocol.py
  or: python test_bridge_protocol.py
"""

import json
import os
import sys

# Ensure the bridge directory is on the path.
BRIDGE_DIR = os.path.dirname(os.path.abspath(__file__))
if BRIDGE_DIR not in sys.path:
    sys.path.insert(0, BRIDGE_DIR)

from protocol import ErrorCode, JsonRpcRequest, JsonRpcResponse, JsonRpcError
from bridge_schema import (
    CPP_BRIDGE_TOOLS,
    CPP_BRIDGE_LONG_NAMES,
    ALL_PYTHON_METHODS,
    WEBSOCKET_PORT,
    HTTP_PORT,
    HTTP_PATH,
    DEFAULT_HOST,
)


def test_standard_error_codes():
    """Standard JSON-RPC 2.0 error codes must match the spec."""
    assert ErrorCode.PARSE_ERROR == -32700
    assert ErrorCode.INVALID_REQUEST == -32600
    assert ErrorCode.METHOD_NOT_FOUND == -32601
    assert ErrorCode.INVALID_PARAMS == -32602
    assert ErrorCode.INTERNAL_ERROR == -32603


def test_custom_error_codes():
    """Custom TermuxForge error codes must match the Flutter side."""
    assert ErrorCode.COMMAND_BLOCKED == -32001
    assert ErrorCode.COMMAND_TIMEOUT == -32002
    assert ErrorCode.COMMAND_FAILED == -32003
    assert ErrorCode.FILE_NOT_FOUND == -32004
    assert ErrorCode.PERMISSION_DENIED == -32005
    assert ErrorCode.TOOL_NOT_FOUND == -32006


def test_cpp_bridge_tools_count():
    """C++ bridge should expose exactly 20 short-name tools."""
    assert len(CPP_BRIDGE_TOOLS) == 20


def test_cpp_bridge_long_names():
    """Long names must map correctly from short names."""
    assert CPP_BRIDGE_LONG_NAMES["sh"] == "shell_command_tool"
    assert CPP_BRIDGE_LONG_NAMES["read"] == "multi_read_tool"
    assert CPP_BRIDGE_LONG_NAMES["patch"] == "multi_patch_tool"
    assert CPP_BRIDGE_LONG_NAMES["search"] == "multi_search_tool"


def test_python_methods_include_core():
    """Python bridge must include core command methods."""
    assert "execute_command" in ALL_PYTHON_METHODS
    assert "execute_shell" in ALL_PYTHON_METHODS
    assert "run_command" in ALL_PYTHON_METHODS
    assert "ping" in ALL_PYTHON_METHODS
    assert "git_status" in ALL_PYTHON_METHODS


def test_transport_ports():
    """Transport ports must match the Flutter side."""
    assert DEFAULT_HOST == "127.0.0.1"
    assert WEBSOCKET_PORT == 8765
    assert HTTP_PORT == 8390
    assert HTTP_PATH == "/mcp"


def test_jsonrpc_request_serialization():
    """JsonRpcRequest must serialize to valid JSON-RPC 2.0."""
    req = JsonRpcRequest(method="ping", id="test-1")
    resp = JsonRpcResponse(id="test-1", result={"ok": True})
    data = json.loads(resp.to_json())
    assert data["jsonrpc"] == "2.0"
    assert data["id"] == "test-1"
    assert data["result"]["ok"] is True
    assert "error" not in data


def test_jsonrpc_error_serialization():
    """JsonRpcError must serialize with code and message."""
    err = JsonRpcError(code=ErrorCode.COMMAND_TIMEOUT, message="timed out")
    resp = JsonRpcResponse(id="test-2", error=err.to_dict())
    data = json.loads(resp.to_json())
    assert data["error"]["code"] == -32002
    assert data["error"]["message"] == "timed out"
    assert "result" not in data


def test_request_from_json_valid():
    """Valid JSON-RPC request should parse correctly."""
    raw = json.dumps({
        "jsonrpc": "2.0",
        "id": "r1",
        "method": "execute_command",
        "params": {"command": "ls"},
    })
    req = JsonRpcRequest.from_json(raw)
    assert req.method == "execute_command"
    assert req.id == "r1"
    assert req.params == {"command": "ls"}


def test_request_from_json_invalid_version():
    """Invalid jsonrpc version should raise."""
    raw = json.dumps({"jsonrpc": "1.0", "method": "ping", "id": 1})
    try:
        JsonRpcRequest.from_json(raw)
        assert False, "Should have raised"
    except JsonRpcError as e:
        assert e.code == ErrorCode.INVALID_REQUEST


def test_request_from_json_missing_method():
    """Missing method should raise."""
    raw = json.dumps({"jsonrpc": "2.0", "id": 1})
    try:
        JsonRpcRequest.from_json(raw)
        assert False, "Should have raised"
    except JsonRpcError as e:
        assert e.code == ErrorCode.INVALID_REQUEST


if __name__ == "__main__":
    # Simple test runner for environments without pytest.
    tests = [
        test_standard_error_codes,
        test_custom_error_codes,
        test_cpp_bridge_tools_count,
        test_cpp_bridge_long_names,
        test_python_methods_include_core,
        test_transport_ports,
        test_jsonrpc_request_serialization,
        test_jsonrpc_error_serialization,
        test_request_from_json_valid,
        test_request_from_json_invalid_version,
        test_request_from_json_missing_method,
    ]
    passed = 0
    failed = 0
    for test in tests:
        try:
            test()
            print(f"  PASS  {test.__name__}")
            passed += 1
        except Exception as e:
            print(f"  FAIL  {test.__name__}: {e}")
            failed += 1
    print(f"\n{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)
