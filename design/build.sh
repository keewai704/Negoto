#!/usr/bin/env bash
# Builds design/Negoto.fig with OpenPencil and exports every page as PNG.
#   needs: bun  (NixOS: `nix shell nixpkgs#bun nixpkgs#nodejs --command design/build.sh`)
set -euo pipefail
cd "$(dirname "$0")"
work="${OPENPENCIL_DIR:-$(mktemp -d)}"
if [ ! -x "$work/node_modules/.bin/openpencil" ]; then
  (cd "$work" && bun add @open-pencil/cli@0.15.1 @open-pencil/core >/dev/null)
fi
OP="$work/node_modules/.bin/openpencil"
echo '<div></div>' > "$work/empty.html"
"$OP" import "$work/empty.html" -o "$work/base.fig" >/dev/null
cp build.ts negoto-design.js "$work/"
(cd "$work" && bun build.ts base.fig "$OLDPWD/Negoto.fig")
mkdir -p exports
for page in Foundations iPhone iPad Dark; do
  "$OP" export Negoto.fig --page "$page" -o "exports/$page.png" -s "${SCALE:-1}" >/dev/null
done
echo "Exported design/exports/*.png"
