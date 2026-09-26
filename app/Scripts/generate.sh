#!/usr/bin/env bash
# Generate the Xcode workspace. Use this instead of a bare `tuist generate`.
#
# Xcode 27 rejects deployment targets below iOS 15 / macOS 12. The package
# targets get a supported floor from Tuist/Package.swift, but Tuist writes its
# generated resource-bundle targets (GRDB_GRDB, swift-sharing_Sharing) with the
# package's own iOS 13 and exposes no setting for them — so raise them here,
# after generation. Bundles hold resources only; the value changes no code.
set -euo pipefail
cd "$(dirname "$0")/.."
tuist install
tuist generate --no-open "$@"
find Tuist/.build/tuist-derived -name project.pbxproj -print0 |
  xargs -0 sed -i '' -E \
    -e 's/IPHONEOS_DEPLOYMENT_TARGET = (1[0-4]|[0-9])(\.[0-9]+)?;/IPHONEOS_DEPLOYMENT_TARGET = 16.0;/' \
    -e 's/MACOSX_DEPLOYMENT_TARGET = 10\.[0-9]+(\.[0-9]+)?;/MACOSX_DEPLOYMENT_TARGET = 13.0;/' \
    -e 's/MACOSX_DEPLOYMENT_TARGET = 11\.[0-9]+(\.[0-9]+)?;/MACOSX_DEPLOYMENT_TARGET = 13.0;/' \
    -e 's/WATCHOS_DEPLOYMENT_TARGET = [0-7](\.[0-9]+)?;/WATCHOS_DEPLOYMENT_TARGET = 9.0;/'
echo "Workspace generated: KanjiWrite.xcworkspace"
