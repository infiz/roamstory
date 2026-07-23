# RoamStory

A writing-first iOS travel journal for combining long-form stories with photos, galleries, video, and travel context.

See the [product requirements and technical design](docs/PRODUCT_REQUIREMENTS_AND_DESIGN.md).

## Current implementation

The first SwiftUI/SwiftData version includes:

- persisted trip creation, editing, deletion, and section reordering;
- trip sorting by localized title, creation date, or modification date in either direction;
- titled sections categorized as places, activities, food and drink, accommodation, transit, events, nature and wildlife, reflections, or other stories;
- ordered paragraph, heading, quote, code, divider, photo, gallery, playable video, and map blocks;
- optional paragraph titles and selection-based font family, size, bold, italic, underline, and link controls;
- iPhone Photos references using `PHAsset.localIdentifier`, without copying originals;
- descriptions and links for media/location blocks;
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
