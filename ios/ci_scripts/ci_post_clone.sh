#!/bin/sh

# Fail this script if any subcommand fails.
set -e

# The default execution directory of this script is the ci_scripts directory.
# Move to the project root.
cd $CI_PRIMARY_REPOSITORY_PATH

# Install Flutter using git into the workspace.
# This ensures it's available on the same volume as the project.
git clone https://github.com/flutter/flutter.git --depth 1 -b stable ./flutter
export PATH="$PATH:`pwd`/flutter/bin"

# Install Flutter artifacts for iOS.
flutter precache --ios

# Install Flutter dependencies.
flutter pub get

# Setup Flutter iOS build configuration (generates Generated.xcconfig)
flutter build ios --config-only --no-codesign

# Install CocoaPods dependencies.
cd ios
pod install

exit 0

