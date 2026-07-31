#!/bin/bash
set -e
echo "Installing Ground Control..."
curl -fsSL "https://github.com/050177/ground-control/releases/latest/download/GroundControl.zip" -o /tmp/gc-install.zip
unzip -q -o /tmp/gc-install.zip -d /tmp/gc-install
cp -R "/tmp/gc-install/Ground Control.app" /Applications/
rm -rf /tmp/gc-install /tmp/gc-install.zip
echo "Done. Opening Ground Control..."
open "/Applications/Ground Control.app"
