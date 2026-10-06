#!/usr/bin/env python3
"""Exports XCTest screenshot attachments from .xcresult bundles into PNG files named after the attachment.

Usage: export_screenshots.py <output dir> <result.xcresult>...
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
for bundle in sys.argv[2:]:
    tmp = tempfile.mkdtemp()
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", bundle, "--output-path", tmp], check=True)
    manifest = json.load(open(os.path.join(tmp, "manifest.json")))
    for test in manifest:
        for att in test.get("attachments", []):
            name = att.get("suggestedHumanReadableName", att["exportedFileName"])
            name = re.sub(r"_\d+_[0-9A-Fa-f-]{36}", "", name)
            if not name.lower().endswith(".png"):
                name += ".png"
            shutil.copy(os.path.join(tmp, att["exportedFileName"]), os.path.join(out, name))
            print("exported", name)
