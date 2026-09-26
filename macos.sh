#!/usr/bin/env bash
# macOS defaults. Run once per machine, then log out and back in.
set -euo pipefail

defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write NSGlobalDomain WebKitDeveloperExtras -bool true
defaults write -g NSRequiresAquaSystemAppearance -bool true

defaults write com.apple.menuextra.battery ShowPercent -bool true
defaults write com.apple.menuextra.clock DateFormat -string "EEE d MMM HH:mm:ss"
defaults write com.apple.screencapture location -string "$HOME/Downloads"

defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

defaults write com.apple.dock expose-animation-duration -float 0.15

defaults write com.apple.Safari IncludeDevelopMenu -bool true
defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled -bool true

killall Finder Dock SystemUIServer cfprefsd 2>/dev/null || true
