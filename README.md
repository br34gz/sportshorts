# SportShorts

A polished, on-device iPhone app that aggregates sports-highlight videos from YouTube channels — curated by the user's country, so each viewer sees the broadcasters and channels that actually serve their region.

Spec, architecture, and decision log live in the [Obsidian vault](obsidian://open?vault=Notes&file=SportShorts%2FSPEC) (private). Channel catalog is editable in `channels.json` at the repo root.

## Status

v0.1 in development. Distributed as an unsigned IPA via GitHub Actions → LiveContainer. No App Store track in v0.1.

## Build

The CI workflow builds an unsigned IPA on every push to `main` using `macos-26` and Xcode 26.

To download: go to the **Actions** tab, pick the latest successful run, and download the `SportShorts-unsigned-ipa` artifact.

## Local dev

```sh
brew install xcodegen
xcodegen generate
open SportShorts.xcodeproj
```

## Stack

- SwiftUI, iOS 26+, Liquid Glass design language
- YouTube channel RSS feeds (no API key, no quota)
- No backend, no accounts, on-device only
- XcodeGen for the project file (avoids project.pbxproj churn in git)

## Curation

The `channels.json` file at the repo root maps `country → [{ sport, competition, channel_id, handle, note }]`. The app fetches this on launch from `raw.githubusercontent.com` and caches locally for 24h.

Edit `channels.json` to add/remove channels — users get the change at next launch without rebuilding the app.
