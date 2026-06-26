import urllib.request
import json
import time

def call_mcp(method, params):
    req = urllib.request.Request(
        'http://localhost:8390/mcp',
        data=json.dumps({"method": method, "params": params}).encode('utf-8'),
        headers={'Content-Type': 'application/json'},
        method='POST'
    )
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode('utf-8'))
    except Exception as e:
        return {"error": str(e)}

tests = [
    ("dir_create", {"path": "test_mcp_dir"}),
    ("file_write", {"path": "test_mcp_dir/test.txt", "content": "Hello World\nLine 2\nLine 3"}),
    ("file_read", {"path": "test_mcp_dir/test.txt"}),
    ("file_append", {"path": "test_mcp_dir/test.txt", "content": "\nLine 4"}),
    ("str_replace", {"path": "test_mcp_dir/test.txt", "old": "World", "new": "MCP"}),
    ("file_edit", {"path": "test_mcp_dir/test.txt", "start_line": 2, "end_line": 2, "replacement": "Line Two"}),
    ("file_info", {"path": "test_mcp_dir/test.txt"}),
    ("dir_list", {"path": "test_mcp_dir"}),
    ("code_search", {"path": "test_mcp_dir", "query": "MCP"}),
    ("file_search", {"path": "test_mcp_dir", "pattern": "test"}),
    ("multi_read", {"path": "test_mcp_dir/test.txt", "ranges": "1-2,3-4"}),
    ("shell_exec", {"command": "echo hello"}),
    ("git_status", {"cwd": "test_mcp_dir"}),
    ("symbol_search", {"path": "test_mcp_dir", "symbol": "Hello"}),
    ("file_delete", {"path": "test_mcp_dir/test.txt"}),
    ("file_delete", {"path": "test_mcp_dir"}),
]

for method, params in tests:
    print(f"Testing {method}...")
    res = call_mcp(method, params)
    print(f"Result: {json.dumps(res, indent=2)}")
    print("-" * 40)
    time.sleep(0.1)

