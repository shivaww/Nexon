#!/usr/bin/env python3
"""
Legacy wrapper for TermuxForgeBridge.
This script is kept for backwards compatibility with existing startup scripts.
It imports and runs the new termux_forge_bridge.py which now supports the
legacy /mcp HTTP POST endpoint directly alongside WebSockets.
"""
import sys
import os

# Ensure the directory containing this script is in sys.path
BRIDGE_DIR = os.path.dirname(os.path.abspath(__file__))
if BRIDGE_DIR not in sys.path:
    sys.path.insert(0, BRIDGE_DIR)

from termux_forge_bridge import main

if __name__ == '__main__':
    main()
