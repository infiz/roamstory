# RoamStory

A writing-first iOS travel journal for combining long-form stories with photos, galleries, video, and travel context.

See the [product requirements and technical design](docs/PRODUCT_REQUIREMENTS_AND_DESIGN.md).
API models must follow the [JSON API conventions](docs/JSON_API_CONVENTIONS.md).

## Current implementation

The first SwiftUI/SwiftData version includes:

- persisted trip creation, editing, deletion, and section reordering;
- trip sorting by localized title, creation date, or modification date in either direction;
- titled sections categorized as places, activities, food and drink, accommodation, transit, events, nature and wildlife, reflections, or other stories;
- ordered paragraph, heading, quote, code, divider, photo, gallery, playable video, and map blocks;
- optional paragraph titles and selection-based font family, size, bold, italic, underline, and link controls;
- iPhone Photos references using `PHAsset.localIdentifier`, without copying originals;
- descriptions and links for media/location blocks;
- a Setup screen with Google, Apple, and Facebook login against
  `https://roamstory.infiz.com`, Keychain-backed RoamStory sessions, and logout
  that leaves local trip data untouched;
- Word-compatible DOCX and offline HTML ZIP export for a section, a whole trip, or selected trip sections; and
- focused unit tests for sorting, SwiftData cascade deletion, media ordering, date ranges, links, and DOCX packaging.

Open `RoamStory.xcodeproj` in Xcode 26 or build from the command line:

```sh
xcodebuild -project RoamStory.xcodeproj \
  -scheme RoamStory \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Before provider login works, configure the Google and Facebook build settings
shown in the server repository's `docs/AUTHENTICATION_SETUP.md` and enable Sign
in with Apple for bundle ID `com.infiz.roamstory`. A development build with
missing provider settings remains available for local trip editing; selecting
an unconfigured provider reports a setup error instead of initializing its SDK
with an invalid value.

Google and Facebook values must be added to the **RoamStory app target** under
**Build Settings** for the active Debug and Release configurations. Values in
the server's `stage.env` are not available to Xcode until the configuration
script below generates the app's local configuration. For Apple login, enable
the capability for the App ID in the Apple Developer portal, let Xcode refresh
automatic signing, and use a device or simulator signed in to an Apple Account.

To use the shared stage values and generate the app's ignored local Xcode
configuration, run:

```sh
./scripts/configure_stage_auth.sh
```

The script reads the sibling `roamstory-server/docker-compose/env/stage.env`,
prompts for missing iOS-only values, derives the reversed Google URL scheme,
and generates `Config/Authentication.local.xcconfig`. Set
`ROAMSTORY_SERVER_ROOT` when the server repository is stored elsewhere.
