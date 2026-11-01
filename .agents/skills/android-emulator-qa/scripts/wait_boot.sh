#!/usr/bin/env bash
# Blocks until the emulator has fully booted, then prints version and screen facts.
set -euo pipefail
source "$(dirname "$0")/env.sh"
adb wait-for-device
adb shell 'while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; do sleep 2; done; echo BOOTED; getprop ro.build.version.release; getprop ro.build.version.sdk; wm size; wm density'
