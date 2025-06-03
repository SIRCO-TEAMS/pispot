#!/bin/bash
SETTINGS="/workspaces/pispot/settings.txt"
LOG="/workspaces/pispot/setup.log"

echo "==== PiSpot Current Settings ===="
if [ -f "$SETTINGS" ]; then
    cat "$SETTINGS"
else
    echo "No settings found."
fi

echo
echo "==== PiSpot Setup Log ===="
if [ -f "$LOG" ]; then
    cat "$LOG"
else
    echo "No log found."
fi
