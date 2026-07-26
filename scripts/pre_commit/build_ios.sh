#!/usr/bin/env bash
set -euo pipefail

exec xcodebuild \
  -project RoamStory.xcodeproj \
  -scheme RoamStory \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "${TMPDIR:-/tmp}/roamstory-pre-commit-derived-data" \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=YES \
  ARCHS=arm64 \
  build
