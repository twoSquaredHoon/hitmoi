# Viewer

Lightweight local manga/comic viewer for iPad (SwiftUI).

## Features

- Import a **folder of images** (JPG/JPEG/PNG/WebP/HEIC) or a **multi-page PDF**
- Same library grid and reader UI for both formats
- RTL reading by default (manga); toggle to LTR in the library toolbar
- Pinch-zoom, page scrubber, remembers last page per book
- Files are copied into the app sandbox so access stays stable

## Requirements

- Xcode 15+ (iOS 17 deployment target)
- iPad or iPhone (designed for iPad)

## Run

1. Open `Viewer.xcodeproj` in Xcode
2. Select your Team under Signing & Capabilities
3. Choose your iPad and Run

## Use

1. Tap **+** (or **Add Book**)
2. Pick a folder of page images, or a PDF
3. Tap the book in the library to read
	- Left/right thirds turn pages (RTL: left = next)
	- Center tap shows/hides chrome
	- Double-tap or pinch to zoom
	- Long-press a cover to delete
