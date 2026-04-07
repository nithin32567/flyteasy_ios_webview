#!/bin/sh

# Fail this script if any subcommand fails.
set -e

# The default execution directory of this script is the ci_scripts directory.
# Move to the project root.
cd $CI_PRIMARY_REPOSITORY_PATH

# Install Flutter using git if not already present.
if [ ! -d "flutter" ]; then
    echo "Cloning Flutter SDK..."
    git clone https://github.com/flutter/flutter.git --depth 1 -b stable ./flutter
fi

export PATH="$PATH:`pwd`/flutter/bin"

# Precache and install dependencies.
echo "Preparing Flutter environment..."
flutter clean
flutter precache --ios
flutter pub get

# Setup Flutter configuration.
echo "Building iOS configuration..."
# Disable parallel code signing to avoid Code 70 internal errors in Xcode Cloud
export COCOAPODS_PARALLEL_CODE_SIGN=false
# Change to --release to ensure App.framework is fully built for the App Store.
flutter build ios --release --no-codesign

# Install CocoaPods.
echo "Installing CocoaPods..."
cd ios
pod install --repo-update

exit 0

