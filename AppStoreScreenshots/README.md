# RoamStory App Store screenshots

The seven iPhone promotional images match VocabHero's screenshot dimensions and
composition: **1284 × 2778 pixels**, RGB PNG without alpha, a warm textured
background, centered benefit headlines, rounded native captures, and soft shadows.
The shared background and iPhone compositor come from the local VocabHero project.
RoamStory's brand label uses cyan to match its app icon.

Upload the numbered files in `iPhone/Promotional` to the **6.5-inch iPhone** slot.
The iPad-enabled app also has a native **2064 × 2752** set in `iPad/Promotional`
for the **13-inch iPad** slot. These dimensions follow Apple's
[screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

| File | Actual app screen |
| --- | --- |
| `01-trips.png` | Trip library |
| `02-organize.png` | Sections within a trip |
| `03-write.png` | Paragraphs, quotes, and writing |
| `04-photo.png` | A photo alongside a story |
| `05-gallery.png` | Photos grouped in a gallery |
| `06-map.png` | A map and place context |
| `07-export.png` | Word export with section selection |

`contact-sheet.png` and `contact-sheet-ipad.png` are review overviews; do not upload
them. Native, unaltered simulator captures are retained in each device's `Raw`
directory.

## Brazil journey and retained photos

The screenshots use **Brazil, river to river**, an eight-chapter journal based on
Jimmy's **2026-06 Brazil** Apple Photos album. The album contains June and July
photos; these selected chapters cover June 17 through July 3, 2026, rather than
claiming to establish the full trip's arrival and return dates.

- `Assets/Brazil2026/journey.json` is the authoritative source loaded by the app
  fixture. It includes the prose, dated chapters, captions, map, and capture routes.
- `Assets/Brazil2026/journey.md` is the readable illustrated journal, generated from
  that JSON by `scripts/render_screenshot_journey.py`.
- `Assets/Brazil2026/Photos/` retains nine selected photos as regular Git assets.
  They are oriented JPEGs with a maximum edge of 2400 pixels, saved at quality 94.
  Capture regeneration needs neither the Photos library nor an external download.
- `Assets/Brazil2026/photos.json` records source album, exported filename, recorded
  camera date/offset, visible subject, dimensions, and source/retained SHA-256 hashes.
  Embedded EXIF is omitted from the retained JPEGs.

The journal is an editorial draft grounded in the reviewed pictures: Teatro
Amazonas in Manaus, river swimming in the Amazon region, Pantanal wildlife,
and Iguazu Falls. Regional labels follow the album's visible sequence; exact
routes, lodges, uncertain species, meals, and conversations are not invented.
Camera UTC offsets are preserved as recorded, rather than treated as verified
location evidence. The map uses a general Iguazu landmark pin, not the private
camera position. The source album and its originals are unchanged.

The fictional Pantanal sample and borrowed wildlife assets have been replaced.
Only this Brazil journey appears in the sample library.

## Regenerate

Requires Xcode, an iOS simulator runtime, Python, Pillow, and the macOS system fonts.
From the repository root:

```sh
python3 scripts/render_screenshot_journey.py
python3 scripts/capture_app_store_screenshots.py
python3 scripts/generate_iphone_app_store_screenshots.py
python3 scripts/capture_app_store_screenshots.py --device ipad
python3 scripts/generate_ipad_app_store_screenshots.py
python3 scripts/package_app_store_screenshots.py
```

To reuse an existing Debug simulator build, pass `--app /absolute/path/RoamStory.app`
to the capture script. Each run creates and deletes its own simulator, copies the saved journey
and photos into the app's disposable capture container, selects light
appearance and Small Dynamic Type, and overrides the status bar to 9:41.
Use `--screen gallery` (or repeat `--screen` for multiple screens) to recapture a
subset without replacing the other raw images.

The Debug-only `--app-store-screenshot=<screen>` argument opens actual app views
using an in-memory SwiftData fixture. It never edits the normal persistent store or
publishes content. Retained photos populate the thumbnail cache directly so capture
does not depend on simulator Photos permissions. The capture mode, photo cache
seeding, and fixture are excluded from Release builds.
The capture script waits for the app's readiness marker before capturing; failed
captures save a diagnostic image in the system temporary directory.

## Refresh the website gallery

From this repository, export the same iPhone images to the sibling site checkout:

```sh
python3 scripts/sync_app_store_screenshots_to_site.py --site ../apps-pages
python3 ../apps-pages/scripts/build-site.py ../apps-pages/public ../apps-pages/dist
```

The export writes the full-size WebP files and their 384, 640, and 768 pixel
responsive variants. It does not deploy the site.

## Product, support, and legal URLs

- Product: <https://apps.infiz.com/roamstory/>
- Support: <https://apps.infiz.com/roamstory/support/>
- Privacy: <https://apps.infiz.com/roamstory/privacy/>
- Terms: <https://apps.infiz.com/roamstory/terms/>

The pages are maintained in the sibling `apps-pages` repository. The app's Setup
screen links to Support, Privacy Policy, and Terms of Use. Deploy those website
changes before using the URLs in an App Store submission.
