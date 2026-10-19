#!/bin/zsh
# Builds Monitor Minder, installs it to /Applications and relaunches it.
set -euo pipefail
cd "${0:A:h}/.."
scripts/bundle.sh "${1:-release}"
pkill -x MonitorMinder 2>/dev/null || true
ditto "build/Monitor Minder.app" "/Applications/Monitor Minder.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Monitor Minder.app"
open "/Applications/Monitor Minder.app"
echo "Installed /Applications/Monitor Minder.app"
