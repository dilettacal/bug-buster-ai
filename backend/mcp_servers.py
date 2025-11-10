"""
MCP server configurations and setup for security analysis tools.
"""

import os
from typing import Dict, Any
from agents.mcp import MCPServerStdio, create_static_tool_filter

def get_semgrep_server_params() -> Dict[str, Any]:
    """Get configuration parameters for the Semgrep MCP server."""
    semgrep_app_token = os.getenv("SEMGREP_APP_TOKEN")
    
    # Enhanced environment for debugging
    env = {
        "SEMGREP_APP_TOKEN": semgrep_app_token,
        "PYTHONUNBUFFERED": "1",  # Ensure output is not buffered
    }
    
    return {
        "command": "uvx",
        "args": [
            "--with", "mcp==1.12.2", 
            "--quiet",  # Reduce uvx output noise
            "semgrep-mcp"
        ],
        "env": env,
    }

def create_semgrep_server() -> MCPServerStdio:
    """Create and configure the Semgrep MCP server instance."""
    params = get_semgrep_server_params()
    return MCPServerStdio(
        params=params,
        client_session_timeout_seconds=120,
        tool_filter=create_static_tool_filter(allowed_tool_names=["semgrep_scan"]),
    )