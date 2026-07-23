# RoamStory Product Requirements and Technical Design

**Status:** Draft for implementation  
**Version:** 0.1  
**Last updated:** 2026-07-22  
**Platform:** iOS first; architecture should permit future iPadOS and macOS clients

## 1. Product summary

RoamStory is a writing-first travel journal organized as trips. Each trip contains titled sections representing a location, meal, view, animal, or experience. A section tells that part of the trip with ordered paragraphs, photos, galleries, videos, and maps. Text is the primary narrative; media and location context support the writing rather than replacing it.

The product should let a traveler:

1. Create a trip.
2. Add titled sections for locations, meals, views, animals, and experiences.
3. Compose the story using reorderable content blocks.
4. Reference original media in iPhone Photos and preserve relevant travel metadata without modifying or duplicating the originals.
5. Export a faithful static document or a richer interactive bundle.
6. Publish or privately share a trip later without changing its authoring format.

Working brand language:

- **RoamStory**
- **Write the journey.**
- Alternative: **Your travels, beautifully told.**

The name is a working product name, not a claim of trademark availability. The prior product discussion identified existing use of “RoamStory” as a feature name in another product, so legal, trademark, domain, and App Store clearance remains required.

## 2. Product principles

### 2.1 Writing first

The trip is a story, not a photo feed. The default creation flow should start with writing and make text editing excellent. Photos, video, maps, and places enrich the narrative.

### 2.2 Structured, not format-bound

DOCX, PDF, HTML, and a published web page are outputs. None is the source of truth. The canonical trip is a versioned, structured document model plus media references.

### 2.3 Semantic authoring

Store intent such as `heading1`, `quote`, `caption`, or `gallery`, not only visual properties such as a font size or pixel layout. Each exporter can then render that intent appropriately.

### 2.4 Local-first durability

Writing and editing must work without a network connection when referenced media is available locally. RoamStory stores its document data independently, but V1 references originals in the iPhone Photos library instead of copying them into app storage. Export may therefore need to download an iCloud-hosted original through Photos.

### 2.5 Graceful export

Interactive features should degrade intentionally. A gallery may be swipeable in the app and HTML, a grid in PDF, and a table or vertical sequence in DOCX. A video may become a linked poster frame or QR code in static formats.

## 3. Goals and success criteria

### 3.1 V1 goals

- Make long-form travel writing comfortable on iPhone and iPad.
- Support rich paragraphs, headings, quotes, dividers, photos, galleries, and videos.
- Distinguish paragraph boundaries from soft line breaks.
- Preserve originals and important capture metadata.
- Save reliably during editing and recover cleanly after interruption.
- Export complete trips to PDF, DOCX, and a self-contained HTML bundle.
- Produce a portable RoamStory archive containing the structured document, media references, and optionally resolved originals.

### 3.2 Product success signals

- A new user can create a trip, title a section, and add a formatted paragraph plus photo without instruction.
- No committed edit is lost when the app is backgrounded or terminated normally.
- A representative 100-section trip remains responsive during editing and navigation.
- Every supported block has an explicit rendering in PDF, DOCX, and HTML.
- An exported archive can be imported on another device with content and metadata intact.
- Export failures identify the affected media reference or block and do not corrupt the trip.

### 3.3 Non-goals for V1

- Real-time multi-user editing.
- A public social feed, likes, followers, or discovery ranking.
- Desktop-grade freeform page layout.
- Arbitrary HTML import or round-trip DOCX editing.
- Full video editing.
- Automatic cloud publishing, GPX route generation, or AI-written prose.
- Cross-platform Android or web editing.

## 4. Target users and core jobs

### Primary user

A traveler who wants to produce a thoughtful narrative of a trip and include high-quality photography, video, and place context without building a website or laying out a book manually.

### Core jobs

- “Let me capture a thought quickly while traveling.”
- “Let me turn notes and media into a polished story later.”
- “Keep my story connected to my original media and travel metadata without duplicating my Photos library.”
- “Let me share a beautiful result in the format my audience needs.”
- “Keep my work portable if the app or service changes.”

## 5. Information architecture

```text
Library
└── Trip
    ├── Trip metadata and cover
    ├── Section (location, meal, view, animal, or experience)
    │   ├── Title, kind, date/time, and optional location
    │   └── Ordered blocks
    │       ├── Heading
    │       ├── Paragraph / Quote
    │       ├── Divider
    │       ├── Photo
    │       ├── Gallery
    │       ├── Video
    │       ├── Map (modelled for future use)
    │       └── Place (modelled for future use)
    └── Assets and location metadata
```

A trip is the export and sharing boundary. A titled section is the primary narrative container and represents one location, meal, view, animal, or experience—for example, “Dinner at Nishiki Market” or “Elephants in Amboseli.” Blocks inside the section preserve the author's intended order and are the editing and rendering boundary. A separate nested entry-container block is not required for V1 because the section itself provides that grouping.

## 6. Functional requirements

Priority uses **P0** for V1 launch requirements, **P1** for the next intended increment, and **P2** for future exploration.

### 6.1 Trip library and lifecycle

| ID | Priority | Requirement |
|---|---:|---|
| FR-001 | P0 | The user can create, rename, duplicate, archive, and delete a trip. |
| FR-002 | P0 | A trip supports title, subtitle, cover asset reference, start/end dates, and optional summary. |
| FR-003 | P0 | The library shows cover, title, date range, last edited time, and local/sync state. |
| FR-004 | P0 | The user can import and export a portable RoamStory archive. |
| FR-005 | P0 | Deletion requires confirmation and should be recoverable through a Recently Deleted area for a defined retention period. |
| FR-006 | P1 | The user can tag and search trips. |
| FR-007 | P0 | The primary library screen presents trips in a list view. Each row shows at least the trip title and enough metadata to distinguish it, such as date range, cover thumbnail, and last modified date. |
| FR-008 | P0 | From the Trips list, the user can create a trip, open and edit an existing trip, or delete a trip. |
| FR-009 | P0 | The user can sort the Trips list by title (alphabetical), creation date, or modification date, with ascending and descending order available for every sort field. |
| FR-009A | P0 | The selected sort field and direction persist across app launches. The default is modification date descending so the most recently edited trip appears first. |

### 6.2 Sections and organization

| ID | Priority | Requirement |
|---|---:|---|
| FR-010 | P0 | The user can add, title, reorder, duplicate, and delete sections within a trip. |
| FR-011 | P0 | Every section has a user-provided title and a kind: location, meal, view, animal, experience, or other. It may also have a date/time, location, and cover/hero asset reference. |
| FR-012 | P0 | A new trip starts with one untitled section and prompts the user to provide its title before export or publishing. |
| FR-013 | P1 | The app can suggest a section from a date, detected place, or media group without applying it automatically. |

### 6.3 Block editor

| ID | Priority | Requirement |
|---|---:|---|
| FR-020 | P0 | The editor is block-based and preserves a deterministic block order. |
| FR-021 | P0 | V1 editable blocks inside a section are heading, paragraph, quote, divider, photo, gallery/slideshow, video, and map. |
| FR-022 | P0 | The user can insert, select, reorder, duplicate, and delete blocks. |
| FR-023 | P0 | Pressing Return at the end of a paragraph creates a new paragraph block. |
| FR-024 | P0 | A soft line break remains inside the current paragraph and is stored distinctly from a paragraph boundary. |
| FR-025 | P0 | The app saves edits automatically; explicit save is not required. |
| FR-026 | P0 | Undo/redo covers text edits and block-level mutations during the editing session. |
| FR-027 | P1 | Multi-select supports moving or deleting several blocks together. |
| FR-028 | P1 | The user can copy/paste blocks within and between trips. |
| FR-029 | P0 | A section directly owns its ordered content blocks; V1 does not support nested block containers. |

### 6.4 Rich text

| ID | Priority | Requirement |
|---|---:|---|
| FR-030 | P0 | Inline styles support font family, font size, bold, italic, underline, strikethrough, text color, and links. |
| FR-031 | P0 | Paragraph styles support body, title, heading levels, quote, and caption. |
| FR-032 | P0 | Paragraph properties support alignment and semantic spacing. |
| FR-033 | P0 | Inline formatting is stored as normalized text runs. |
| FR-034 | P1 | Text and highlight colors use a controlled palette with accessible contrast. |
| FR-035 | P0 | The user can change the font family and size for selected text while the paragraph retains a semantic base style for export and accessibility. |

### 6.5 Photos and galleries

| ID | Priority | Requirement |
|---|---:|---|
| FR-040 | P0 | The user can select one or multiple photos from the iPhone Photos library. Google Photos, OneDrive, and other file/cloud providers are future integrations. |
| FR-041 | P0 | A photo block supports a description/caption displayed below the photo, alt text, display style, crop/focal-point metadata, and an optional link. |
| FR-042 | P0 | A gallery supports ordered photos, an optional description for each photo, an overall caption, aspect-ratio preference, and a semantic layout style. |
| FR-043 | P0 | V1 gallery styles are grid and slideshow/carousel; exporters may map them to format-appropriate layouts. |
| FR-044 | P0 | For iPhone Photos assets, the app stores the Photos local identifier and required presentation metadata without copying the original photo into RoamStory storage. Regenerable thumbnails may be cached. |
| FR-045 | P0 | When available and authorized, preserve capture date, coordinates, camera metadata, orientation, dimensions, filename, and MIME/UTType. |
| FR-046 | P0 | The user may remove or edit location metadata in the trip without modifying the source in Photos. |
| FR-047 | P1 | The app can suggest chronological groups from photo time and location. |
| FR-048 | P0 | If Photos permission is revoked, the asset is deleted, or the referenced original is otherwise unavailable, the block remains in the section and displays a recoverable missing-media state. |
| FR-049 | P1 | The media reference model supports future provider types such as Google Photos, OneDrive, and other drives without changing block schemas. |

### 6.6 Video

| ID | Priority | Requirement |
|---|---:|---|
| FR-050 | P0 | The user can select one or multiple supported videos from the iPhone Photos library. |
| FR-051 | P0 | A video block supports a description/caption displayed below the video, alt text/transcript placeholder, poster frame, and display style. |
| FR-052 | P0 | Video remains playable in the app and HTML export. |
| FR-053 | P0 | PDF and DOCX render a poster frame, caption, and optional link or QR code rather than embedding playable video. |
| FR-054 | P1 | The app may create a temporary share-optimized transcode for export or publishing without retaining a second permanent original. |
| FR-055 | P0 | For iPhone Photos videos, the app stores the Photos local identifier and presentation metadata without copying the original video into RoamStory storage. Regenerable poster frames may be cached. |

### 6.7 Places, maps, and route context

| ID | Priority | Requirement |
|---|---:|---|
| FR-060 | P0 | The schema reserves typed map and place blocks so future migrations do not require abusing generic embeds. |
| FR-061 | P1 | The user can add a place with name, coordinates, address, notes, and an optional linked block/asset. |
| FR-062 | P1 | A map block can show selected places and a route. |
| FR-063 | P1 | With permission, the app can correlate photo EXIF time/GPS, GPX samples, journal dates, and places to suggest a day timeline. |
| FR-064 | P1 | Suggestions are reviewable and never silently insert content or expose precise location. |

### 6.8 Export and publishing

| ID | Priority | Requirement |
|---|---:|---|
| FR-070 | P0 | The user can export a whole trip as PDF, DOCX, a zipped HTML bundle, or a portable RoamStory archive. |
| FR-071 | P0 | Export offers at least theme, page size (where applicable), image-quality preset, and inclusion of location metadata. |
| FR-072 | P0 | Export runs from an immutable document snapshot so editing can continue safely. |
| FR-073 | P0 | The app reports progress and supports cancellation without leaving a partial file at the chosen destination. |
| FR-074 | P0 | HTML export is self-contained and can include local CSS, JavaScript, images, video, maps rendered from included data, and accessible fallbacks. |
| FR-075 | P0 | PDF and DOCX define a fallback for every V1 block type. |
| FR-076 | P1 | The user can publish to a private unlisted link or a public page. |
| FR-077 | P1 | Republishing creates a new immutable revision and does not modify the local canonical trip. |
| FR-078 | P1 | The user can unpublish a revision and see its sharing status in the app. |

## 7. UX requirements

### 7.1 Trips list

- The Trips list is the default destination after launch.
- A prominent create action opens the new-trip flow.
- Selecting a row opens that trip for viewing and editing.
- Each row exposes an accessible delete action; deletion uses the confirmation and recovery behavior in FR-005.
- A sort control offers **Title**, **Created**, and **Modified**.
- A direction control offers **Ascending** and **Descending**, and the active field and direction are visibly indicated.
- Title sorting uses localized, case-insensitive comparison appropriate to the user's locale.
- Creation and modification sorting uses stored timestamps rather than formatted display strings.
- Trips with equal primary sort values use title and then stable trip ID as deterministic tie-breakers, preventing rows from moving unpredictably.
- Empty state explains that no trips exist and includes a create-trip action.

### 7.2 Primary flows

**Browse and sort trips**

1. Launch the app into the Trips list.
2. Review existing trips and their summary metadata.
3. Select Title, Created, or Modified as the sort field.
4. Select ascending or descending order.
5. Open a trip to edit it, create a new trip, or invoke delete on an existing trip.

**Create and write**

1. Create a trip and enter its title and optional date range.
2. Add a section, choose its kind, and provide a title.
3. Add one or more paragraphs, photos, galleries, videos, or maps in the desired order.
4. Use a formatting bar to change the paragraph style, font family, font size, and inline styles.
5. Add a description below each photo or video when desired.
6. Add and reorder additional sections for other locations, meals, views, animals, or experiences.
7. Leave the editor at any time; autosave preserves the work.

**Add several photos**

1. Choose iPhone Photos.
2. Select multiple items.
3. Choose separate photo blocks or one gallery.
4. Reorder, caption, and select layout.
5. RoamStory stores Photos references and presentation metadata; it does not copy the originals.
6. Thumbnail loading and any iCloud download show visible progress or availability status.

**Export**

1. Select format.
2. Configure only options relevant to that format.
3. Preview representative output when practical.
4. Export with progress and cancellation.
5. Present the standard iOS share/save sheet only after a valid artifact exists.

### 7.3 Editing behavior

- Selection and keyboard behavior should follow native iOS expectations.
- Formatting controls reflect the current selection and mixed states.
- Media import must not block text editing.
- Blocks with missing or processing assets remain editable and show an actionable state.
- Destructive block actions participate in undo.
- Reordering should work with touch and keyboard/VoiceOver alternatives.

### 7.4 Accessibility

- Support Dynamic Type without clipping core controls.
- Every control and block exposes a meaningful VoiceOver label and action.
- Authors can provide alt text and captions.
- Color is not the only status signal.
- Export themes use accessible defaults and preserve heading structure in HTML/DOCX where supported.

## 8. Canonical document model

### 8.1 Model overview

```swift
Trip
├── id, schemaVersion, metadata, dates
├── coverMediaReferenceID
├── sections: [Section]
└── mediaReferences: [MediaReference]

Section
├── id, title, kind, date/time, location
└── blocks: [Block]

Block
├── heading
├── paragraph / quote
├── divider
├── photo
├── gallery
├── video
└── map

Paragraph
└── runs: [TextRun]

MediaReference
├── identity and type
├── provider and provider-specific identifier
├── cached regenerable preview references
├── technical metadata
└── optional capture time and location
```

Use stable UUIDs for trips, sections, blocks, media references, and revisions. Ordering should be represented explicitly, either by an ordered relationship with tested persistence behavior or by a sortable position value designed for insertion and reordering.

### 8.2 Section container rules

A section is the semantic container for one travel moment, subject, stop, or experience. It contains an ordered mixture of paragraphs, photos, galleries, videos, and maps.

- A section requires a title before export or publishing.
- Section kind is one of `location`, `meal`, `view`, `animal`, `experience`, or `other`.
- Section metadata may include local date/time, time zone, place name, coordinates, and a hero media reference.
- A section directly owns zero or more leaf blocks; blocks do not contain other blocks in V1.
- Empty sections are allowed temporarily while editing but should be flagged before export.
- Moving a block between sections preserves its ID, content, media references, and formatting.
- Renderers treat a section as a semantic unit and should avoid separating its title from its first content block where the destination format permits.

### 8.3 Illustrative JSON

This is a design example, not yet a locked wire format.

```json
{
  "schemaVersion": 1,
  "type": "trip",
  "id": "A96F68EC-8A59-4B41-928F-0A6534A65A83",
  "title": "Japan 2026",
  "subtitle": "Tokyo to Kyoto",
  "createdAt": "2026-07-22T18:30:00Z",
  "modifiedAt": "2026-07-22T19:00:00Z",
  "startDate": "2026-07-10",
  "endDate": "2026-07-20",
  "coverMediaReferenceId": "5A75E4B0-6921-4521-9302-FA5A21C4ACAF",
  "sections": [
    {
      "id": "1B2B8D19-AD83-407F-BDEA-2C2A84BB6EBE",
      "title": "Arrival at Shibuya Crossing",
      "kind": "location",
      "localDate": "2026-07-11",
      "timeZone": "Asia/Tokyo",
      "location": {
        "name": "Shibuya Crossing",
        "latitude": 35.6595,
        "longitude": 139.7005
      },
      "blocks": [
        {
          "id": "3905B0F1-2C21-4529-9E2A-08A4208D50B5",
          "type": "paragraph",
          "paragraphStyle": "body",
          "runs": [
            { "text": "We arrived in ", "marks": [], "fontFamily": "New York", "fontSize": 17 },
            { "text": "Tokyo", "marks": ["bold"], "fontFamily": "New York", "fontSize": 17 },
            { "text": " around noon.\nThe city was already humming.", "marks": [], "fontFamily": "New York", "fontSize": 17 }
          ]
        },
        {
          "id": "7F041000-F8A1-4745-A6AA-54D16FF5CEB3",
          "type": "gallery",
          "layout": "slideshow",
          "mediaReferenceIds": [
            "5A75E4B0-6921-4521-9302-FA5A21C4ACAF",
            "289CA825-0EB1-47B9-BADF-F2FB86F49395"
          ],
          "description": "Shibuya after dark"
        }
      ]
    }
  ],
  "mediaReferences": [
    {
      "id": "5A75E4B0-6921-4521-9302-FA5A21C4ACAF",
      "kind": "image",
      "source": {
        "provider": "applePhotos",
        "localIdentifier": "8A3A7E5C-.../L0/001"
      },
      "originalFilename": "IMG_1234.HEIC",
      "contentType": "image/heic",
      "pixelWidth": 8640,
      "pixelHeight": 5760,
      "orientation": 1,
      "capturedAt": "2026-07-11T20:14:30+09:00",
      "location": {
        "latitude": 35.6595,
        "longitude": 139.7005,
        "horizontalAccuracyMeters": 12.0
      }
    }
  ]
}
```

### 8.4 Text invariants

- Separate paragraphs are separate blocks.
- A soft line break is represented within a paragraph's text content.
- Runs must be normalized: no empty runs, and adjacent runs with identical marks should merge.
- Marks must not carry arbitrary platform-specific attributed-string keys into the archive.
- Semantic paragraph style is required; visual overrides are optional and constrained.

### 8.5 Media-reference invariants

- JSON never contains original media as base64 or another inline binary representation.
- RoamStory identity is independent from provider identifiers and filenames.
- An Apple Photos reference stores a durable Photos `localIdentifier`, not a temporary picker URL and not a copied original.
- The app resolves the identifier through PhotoKit each time original bytes or an appropriate rendition are required.
- An asset may require an iCloud download; UI, export, and publishing must expose progress, cancellation, and network failure.
- Cached thumbnails, poster frames, and temporary export renditions are regenerable and are not authoritative originals.
- Removing a block does not remove the source item from Photos and does not remove a media reference still used elsewhere.
- Permission revocation, deletion from Photos, device migration, or provider unavailability can break a reference. The document must retain its layout, description, and metadata while presenting a relink action.
- Provider-specific fields live inside the typed `source` object. Future sources may include `googlePhotos`, `oneDrive`, and `fileProvider` without changing photo, gallery, or video blocks.
- Export validates and resolves all required media references before committing the output artifact.

## 9. Portable archive format

Use a package-style directory with a custom extension such as `.roamstory` (final UTType and extension require validation).

```text
Japan-2026.roamstory/
├── manifest.json
├── document.json
├── media-references.json
├── derivatives/
│   ├── thumbnails/
│   └── posters/
├── embedded-media/          # optional "include originals" archive mode only
└── metadata/
    └── locations.json       # optional, if separated from document.json
```

`manifest.json` should contain at least:

- archive format version;
- document schema version;
- trip ID and title;
- creation timestamp;
- application/build identity;
- media-reference inventory and whether each item is referenced or embedded;
- required versus optional entries.

The normal lightweight archive preserves Photos references but does not copy original media, so it is not guaranteed to be self-contained on another device. An explicit **Include original media** archive option may resolve and embed originals when the user needs a portable backup. Import must stage the package, validate paths and hashes, reject unsafe paths, migrate the document if required, and only then commit it to the working store. Export must write to a temporary sibling and atomically move the completed artifact into place.

## 10. Application architecture

```text
SwiftUI views and navigation
          │
          ▼
Editor commands / use cases
          │
          ▼
Domain model and validation
          │
    ┌─────┴──────────┐
    ▼                ▼
SwiftData/SQLite   Media resolver + cache
working state      Photos references + derivatives
    │                │
    └─────┬──────────┘
          ▼
Immutable TripSnapshot
          │
  ┌───────┼───────────┬───────────┐
  ▼       ▼           ▼           ▼
Archive   PDF         DOCX        HTML / Publisher
codec     renderer    renderer    renderer
```

### 10.1 Layers

**Presentation**

- SwiftUI library, editor, media browser, export flow, and settings.
- UIKit/TextKit integration is acceptable for production-quality rich text where SwiftUI text editing is insufficient.

**Domain**

- Platform-light types for trips, sections, blocks, runs, media references, locations, themes, and export options.
- Validation, normalized rich text, block commands, and snapshot creation.

**Persistence**

- SwiftData or SQLite-backed working database for incremental autosave and queries.
- PhotoKit-backed resolver for Apple Photos references and a file-backed cache for regenerable derivatives.
- Provider abstraction for later Google Photos, OneDrive, and file-provider integrations.
- Schema migrations tested against fixtures for every released version.

**Services**

- Media importer and metadata extractor.
- Thumbnail/poster/transcode pipeline.
- Archive importer/exporter.
- One renderer per output format.
- Optional sync and publishing clients isolated behind protocols.

### 10.2 Why the database is not the archive

The working database optimizes frequent edits, indexing, relationships, and recovery. The portable archive optimizes interoperability, long-term durability, and user ownership. Serializing a versioned document snapshot keeps those responsibilities separate.

### 10.3 Autosave and consistency

- Debounce ordinary text persistence while guaranteeing a flush on section change and app lifecycle transitions.
- Commit a block mutation and its references transactionally.
- Resolve media through explicit states: `referenced`, `requestingPermission`, `downloading`, `processing`, `ready`, `missing`, and `failed`.
- Keep the document, block descriptions, and last usable thumbnail readable when media resolution or derivative generation fails.
- Use background tasks only where iOS permits; resume unfinished processing after relaunch.

### 10.4 Concurrency

- UI-bound editor state remains main-actor isolated.
- Media IO, hashing, metadata extraction, and export run off the main actor.
- Export operates on a frozen `TripSnapshot`, not live persistence objects.
- Progress reporting is structured and cancellation-aware.

## 11. Export design

Define a shared renderer contract:

```swift
protocol TripRenderer {
    associatedtype Options: Sendable

    func render(
        snapshot: TripSnapshot,
        options: Options,
        destination: URL,
        progress: @Sendable (RenderProgress) -> Void
    ) async throws
}
```

Each renderer must declare supported blocks and fallback rules. The export coordinator validates the snapshot before rendering and produces a structured report of warnings.

### 11.1 PDF

- Paginated, print-oriented layout with themes, page size, margins, headers/footers, and controlled image quality.
- Avoid orphan headings and split captions.
- Gallery fallback: configured grid or sequential figures.
- Video fallback: poster frame, caption, and optional QR/link.
- Maps render as static images with attribution where required.

### 11.2 DOCX

- Preserve semantic headings, paragraphs, links, captions, and basic inline marks.
- Use stable styles instead of per-run visual formatting where possible.
- Gallery fallback: compatible table/grid or vertical figures.
- Document limitations may create warnings but must not silently omit content.

### 11.3 HTML bundle

```text
Japan-2026/
├── index.html
├── assets/
├── css/journal.css
├── js/gallery.js
└── data/                    # optional structured data for maps or search
```

- No network dependency is required to read the basic story.
- Galleries and video remain interactive.
- Generated HTML uses semantic headings, figures, captions, and alt text.
- Filenames and generated markup are sanitized.
- External maps, fonts, analytics, or embeds must be explicit options because they affect offline behavior and privacy.

### 11.4 Publishing

Publishing should use the same versioned snapshot and asset model as export:

```text
POST trip revision metadata
UPLOAD required assets by hash
FINALIZE immutable revision
SET visibility (private/unlisted/public)
```

The server renderer may evolve independently, but a published revision must remain tied to the exact snapshot and renderer/theme version used. Publishing is P1 and requires a separate privacy, abuse, account, deletion, and operational design.

## 12. Sync strategy

Cloud sync is not required for the first vertical slice, but persistence choices must not preclude it.

- Use stable IDs and modification metadata.
- Do not use filesystem paths as durable cross-device identity.
- Treat large assets separately from structured records.
- Define conflict behavior before enabling multi-device edits.
- Prefer conflict visibility and trip/section duplication over silent last-write-wins data loss.
- iCloud/CloudKit is a likely first implementation, but should remain behind repository protocols.

## 13. Privacy and security

Travel journals can reveal precise locations, routines, companions, and dates. Privacy is a product requirement.

- Request Photos and Location permissions only at the feature that needs them.
- Default publishing visibility should be private or unlisted, not public.
- Explain when EXIF coordinates are preserved, removed, or published.
- Export options must make location inclusion explicit.
- Sanitize archive paths and HTML output.
- Validate MIME/UTType, dimensions, duration, and file size before processing untrusted imports.
- Avoid loading active remote content in exported HTML by default.
- Remove local and remote data predictably when a user deletes an account or publication.
- Never require a server copy merely to create, edit, archive, or locally export a trip.

## 14. Non-functional requirements

### Reliability

- Persist edits incrementally and transactionally.
- Crash or termination during export/import must not corrupt the working journal.
- Provide migration fixtures and rollback/backup behavior for every schema upgrade.

### Performance

- Trip library interactions should feel immediate for at least 1,000 trips.
- Opening a section should not decode full-resolution media.
- Use thumbnails and lazy loading in the editor.
- Long trips must use incremental fetching/rendering rather than one giant view or attributed string.
- Large imports and exports must expose progress and remain cancellable.

### Storage

- Show RoamStory storage usage separately from storage owned by Photos.
- Derivative caches may be purged safely.
- V1 must not permanently duplicate a Photos original in RoamStory storage.

### Compatibility

- Unknown optional fields should be preserved or ignored safely according to the schema rules.
- Unknown required block types must fail import with a useful compatibility message rather than disappear.
- A newer archive version must never be imported partially as if successful.

### Observability

- Log structured, privacy-preserving diagnostics for persistence, import, processing, and export stages.
- Do not log journal prose, captions, precise coordinates, or filenames by default.

## 15. Validation and testing strategy

### Unit tests

- Rich-text run normalization and paragraph/soft-break behavior.
- Block command ordering, undo, and reference accounting.
- JSON encoding/decoding and schema migration.
- Archive path/hash validation.
- Export mapping for every block and style.

### Integration tests

- Create, edit, relaunch, and recover a trip with multiple titled section kinds.
- Resolve Photos references and resume an interrupted thumbnail, iCloud download, or derivative job.
- Round-trip `.roamstory` export/import with content-hash verification.
- Export representative fixtures to PDF, DOCX, and HTML.
- Continue editing while exporting a snapshot.

### Golden and visual tests

Maintain fixtures that cover:

- all text styles and Unicode scripts;
- very long paragraphs;
- portrait, landscape, panoramic, transparent, and wide-gamut images;
- missing metadata and missing/corrupt assets;
- galleries with one, many, and mixed-aspect assets;
- video poster fallback;
- right-to-left text and accessibility text sizes.

Compare renderer output structurally and visually where practical. HTML must also receive automated accessibility checks.

## 16. Delivery plan

### Phase 0 — Foundations

- Lock initial domain types and schema rules.
- Build SwiftData/SQLite repositories, PhotoKit media resolver, and derivative cache.
- Implement fixtures, migrations, snapshot creation, and archive round-trip.

**Exit:** A programmatically created trip with Photos media references survives persistence and lightweight archive round-trip; missing references produce a recoverable state.

### Phase 1 — Writing vertical slice

- Library, trip metadata, titled categorized sections.
- Paragraph/heading/quote/divider blocks.
- Rich-text editing, autosave, undo/redo, and reorder.

**Exit:** A user can write and reopen a multi-section, formatted trip without loss.

### Phase 2 — Media

- Photo and video import.
- Asset processing and metadata.
- Photo, gallery, and video blocks.

**Exit:** A user can build and reliably reopen a media-rich story without loading originals into every editor view.

### Phase 3 — Export

- Shared export snapshot/coordinator.
- HTML bundle first as the closest fidelity target.
- PDF and DOCX renderers with documented fallback behavior.

**Exit:** Golden fixture trips export successfully in all formats, and every block is represented.

### Phase 4 — Travel intelligence and publishing

- Place/map blocks and EXIF/GPX suggestions.
- Accounts, private/unlisted publishing, revisions, and unpublish.

**Exit:** A user can review travel-derived suggestions and publish a privacy-controlled immutable revision.

## 17. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Canonical content | Versioned structured model | Keeps authoring independent from any export format. |
| V1 media storage | PhotoKit references using Photos local identifiers; no permanent original copy | Avoids duplicating the user's Photos library while retaining access through system APIs. |
| Future media sources | Typed provider abstraction | Allows Google Photos, OneDrive, and other drives later without changing content blocks. |
| Editor model | Ordered semantic blocks | Supports mixed media, reordering, and format-specific rendering. |
| Composite content | A titled, categorized section directly owns ordered leaf blocks | A section naturally groups one location, meal, view, animal, or experience without nested-block complexity. |
| Rich text | Semantic paragraph styles plus normalized inline runs | Predictable editing and export. |
| Working persistence | SwiftData or SQLite plus PhotoKit resolver and derivative cache | Efficient incremental edits without duplicating Photos originals. |
| Portable format | Manifested package/archive | User ownership, integrity validation, and long-term portability. |
| Export | Independent renderers over immutable snapshots | Isolation, consistency, testability, and background execution. |
| HTML | Export/publishing target, not source of truth | High-fidelity sharing without contaminating editing state. |
| Maps/places | Typed in schema before UI launch | Avoids later encoding travel concepts as generic embeds. |

## 18. Open questions requiring product decisions

1. Is V1 iPhone-only, universal iPhone/iPad, or designed for iPad-first long-form editing?
2. What is the minimum supported iOS version?
3. Is CloudKit sync a launch requirement or a post-launch feature?
4. Should the `other` section kind allow user-defined labels, or remain a generic fallback?
5. Which style controls are allowed beyond semantic presets?
6. Should galleries offer both grid and carousel in V1, or only one authoring style with exporter-specific layouts?
7. What maximum video duration/size and journal archive size should V1 support?
8. Should the standard portable archive remain reference-only, or should “Include original media” be the default despite larger files and iCloud downloads?
9. Does DOCX need parity at launch, given implementation and layout complexity, or may it follow HTML/PDF?
10. What publishing business model and privacy defaults are intended?
11. Is the working name RoamStory acceptable pending formal trademark and domain review?
12. Does the first release need GPX import, or only a schema compatible with it?

## 19. V1 release acceptance checklist

- [ ] User can create, edit, reopen, duplicate, archive, and delete a trip.
- [ ] Trips appear in a list and can be sorted by localized title, creation date, or modification date in ascending or descending order.
- [ ] The selected Trips sort field and direction survive app relaunch; modification date descending is used initially.
- [ ] User can create and reorder sections and all V1 blocks.
- [ ] Paragraphs and soft line breaks round-trip distinctly.
- [ ] Inline and semantic paragraph styles survive relaunch and archive import.
- [ ] Multiple photos can become individual blocks or a gallery.
- [ ] Original media and selected metadata remain intact.
- [ ] Missing/failed media presents a recoverable state.
- [ ] A lightweight archive round-trips its trip, sections, blocks, formatting, descriptions, metadata, and Photos references; unavailable references enter a recoverable relink state.
- [ ] An archive exported with “Include original media” round-trips as a self-contained artifact on another installation/device.
- [ ] PDF, DOCX, and HTML represent every V1 block without silent omission.
- [ ] Export cancellation leaves no misleading partial result.
- [ ] VoiceOver, Dynamic Type, keyboard navigation, and alt-text authoring pass the accessibility test plan.
- [ ] Schema migration, archive validation, and representative large-journal performance tests pass.
