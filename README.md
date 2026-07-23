# RoamStory

A writing-first iOS travel journal for combining long-form stories with photos, galleries, video, and travel context.

See the [product requirements and technical design](docs/PRODUCT_REQUIREMENTS_AND_DESIGN.md).

## Current implementation

The first SwiftUI/SwiftData version includes:

- persisted trip creation, editing, deletion, and section reordering;
- trip sorting by localized title, creation date, or modification date in either direction;
- titled sections categorized as places, activities, food and drink, accommodation, transit, events, nature and wildlife, reflections, or other stories;
- ordered paragraph, heading, quote, divider, photo, gallery, video, and map blocks;
- optional paragraph titles and selection-based font family, size, bold, italic, and underline controls;
- iPhone Photos references using `PHAsset.localIdentifier`, without copying originals;
- descriptions below photo, gallery, and video blocks; and
- focused unit tests for sorting and SwiftData cascade deletion.

Open `RoamStory.xcodeproj` in Xcode 26 or build from the command line:

```sh
xcodebuild -project RoamStory.xcodeproj \
  -scheme RoamStory \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  test
```
