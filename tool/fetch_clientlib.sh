#!/usr/bin/env bash
# Fetches the Trafficnetwork client library (Dart package + Flutter plugin) from its GitHub release, checks the SHA-256
# sums against the release's own checksums.txt, and unpacks them to packages/dart and packages/flutter, where
# pubspec.yaml expects them (the plugin's pubspec points at ../dart).
#
#   tool/fetch_clientlib.sh            # the version pinned below
#   TN_CLIENTLIB_VERSION=1.2.2 tool/fetch_clientlib.sh
#
# Needs the GitHub CLI (`gh`, logged in) or curl. Nothing is built and nothing is changed outside packages/.
set -euo pipefail

VERSION="${TN_CLIENTLIB_VERSION:-1.2.1}"
REPO="Romsmo/Trafficnetwork"
TAG="client-lib-v${VERSION}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FILES=(checksums.txt "trafficnetwork-dart-${VERSION}.tar.gz" "trafficnetwork-flutter-${VERSION}.tar.gz")

echo "Fetching $TAG from github.com/$REPO ..."
for f in "${FILES[@]}"; do
  if command -v gh >/dev/null 2>&1; then
    gh release download "$TAG" --repo "$REPO" --pattern "$f" --dir "$WORK"
  else
    curl -fsSL -o "$WORK/$f" "https://github.com/$REPO/releases/download/$TAG/$f"
  fi
done

echo "Checking SHA-256 sums ..."
( cd "$WORK" && sha256sum -c checksums.txt --ignore-missing )

rm -rf "$ROOT/packages/dart" "$ROOT/packages/flutter"
mkdir -p "$ROOT/packages/dart" "$ROOT/packages/flutter"
tar -xzf "$WORK/trafficnetwork-dart-${VERSION}.tar.gz" -C "$ROOT/packages/dart" --strip-components=1
tar -xzf "$WORK/trafficnetwork-flutter-${VERSION}.tar.gz" -C "$ROOT/packages/flutter" --strip-components=1
echo "Done: packages/dart and packages/flutter are ${VERSION}."
