#!/usr/bin/env python3
"""Dump the UI tree from the emulator and list elements with text/content-desc and centre coordinates.

Usage:  ui_dump.py            # list all labelled nodes
        ui_dump.py Increment  # print the centre of the first node whose desc/text contains the argument
        ui_dump.py Increment --tap   # ... and tap it
"""
import re, subprocess, sys, pathlib

def dump():
    subprocess.run("adb shell uiautomator dump /sdcard/ui.xml >/dev/null && adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null", shell=True, check=True)
    return pathlib.Path("/tmp/ui.xml").read_text()

def nodes(xml):
    for m in re.finditer(r'<node [^>]*>', xml):
        n = m.group(0)
        text = re.search(r' text="([^"]*)"', n); desc = re.search(r' content-desc="([^"]*)"', n)
        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
        label = (desc.group(1) if desc else "") or (text.group(1) if text else "")
        if label and b:
            x1, y1, x2, y2 = map(int, b.groups())
            yield label, (x1 + x2) // 2, (y1 + y2) // 2

xml = dump()
if len(sys.argv) == 1:
    for label, cx, cy in nodes(xml):
        print(f"{cx:5d} {cy:5d}  {label}")
else:
    needle = sys.argv[1].lower()
    for label, cx, cy in nodes(xml):
        if needle in label.lower():
            print(f"{label} -> physical ({cx},{cy}) logical ({cx/2.625:.0f},{cy/2.625:.0f})")
            if "--tap" in sys.argv:
                subprocess.run(["adb", "shell", "input", "tap", str(cx), str(cy)], check=True)
                print("tapped")
            break
    else:
        sys.exit(f"no node matching {needle!r}")
