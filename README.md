# SportShorts

A polished iPhone app that pulls sports highlights from the YouTube channels of every major broadcaster in your country, then filters them down to just the sports you follow. No accounts, no backend, no ads.

**Latest release:** [download the unsigned IPA](https://github.com/br34gz/sportshorts/releases/latest/download/SportShorts-unsigned.ipa) — sideload with the tool of your choice.

---

## What it does

- **Country-aware channel pool.** Pick a country and the app follows every major sports broadcaster + free-to-air TV channel that serves that country, plus league-official channels (Premier League, UEFA, NBA, NFL, etc.).
- **Sport-level filter.** Choose the sports you care about (Soccer, NBA, NFL, NHL, NBL, AFL, NRL, F1, Tennis, Cricket). The feed is filtered to just those.
- **Optional competition narrowing.** For sports with multiple competitions (soccer especially), you can narrow down to specific ones — e.g. "just EPL and UCL, no La Liga."
- **Match stats overlay.** Tap into a highlight and get score + key stats pulled from ESPN / TheSportsDB (soccer, NBA, NBL, NFL, NHL, AFL, NRL, all four tennis Grand Slams, F1 race results). Spoiler curtain if you haven't watched yet.
- **Spoiler guard.** Score-revealing titles are hidden by default and unlocked by an eye toggle in the toolbar.
- **In-app player** via a CodePen-hosted YouTube embed proxy (avoids the "video unavailable" restrictions publishers put on iframe embeds), with SponsorBlock skip integration.
- **Hide channels from the player.** If a source keeps hitting geoblocks, tap "Hide channel" from the ⋯ menu — never see its videos again.
- **Add your own channels.** Settings → Channels → + paste any YouTube URL or `@handle`.

## Install

1. Download the latest IPA: [SportShorts-unsigned.ipa](https://github.com/br34gz/sportshorts/releases/latest/download/SportShorts-unsigned.ipa)
2. Sideload it onto your iPhone using whichever tool you prefer.
3. Open, pick your country, pick your sports, done.

**Requires iOS 17 or later.**

## Supported countries

Australia, United Kingdom, United States, Ireland, New Zealand, South Africa. Adding more countries is a `channels.json` edit — see below.

## Contributing

- **Add a channel to the catalog.** Edit `channels.json` at the repo root, add your entry, PR it. The app refetches the catalog every 24 hours so all users pick up new channels without a rebuild.
- **Report a broken filter.** File an issue with the video title that got missed or shouldn't have surfaced.
- **Fix a bug or add a feature.** PRs welcome. Local dev instructions below.

## Local dev

```sh
brew install xcodegen
xcodegen generate
open SportShorts.xcodeproj
```

The Xcode project itself is not committed — [XcodeGen](https://github.com/yonaskolb/XcodeGen) regenerates it from `project.yml` to keep git diffs clean.

## Stack

- SwiftUI, iOS 17+
- YouTube channel RSS feeds + `/videos` page scrape (no API key, no quota)
- ESPN + TheSportsDB public APIs for match statistics
- SponsorBlock community API for skip ranges
- WKWebView + CodePen iframe proxy for playback
- No backend, no accounts, on-device only
- XcodeGen for the project file (avoids `.pbxproj` churn in git)

## How the catalog works

`channels.json` at the repo root maps every country to a list of broadcaster YouTube channels, plus a `global_channels` pool of league-official channels used regardless of country. The app fetches this from `raw.githubusercontent.com` on launch and caches locally for 24 hours. A bundled fallback ships with the app for first-run / offline use.

Adding a broadcaster is a two-line PR:

```json
{"channel_id": "UCxxxxxxxxxxxxxxxxxxxxx", "name": "Sky Sports Rugby", "handle": "SkySportsRugby", "sport_hints": []}
```

## Build

The CI workflow in `.github/workflows/build.yml` builds an unsigned IPA on every push to `main` using `macos-26` and Xcode 26. Each build becomes a GitHub Release, and the `latest` alias always points at the most recent one — so the download URL in this README never breaks.

## License

MIT — see [LICENSE](LICENSE). Reuse whatever you want.
