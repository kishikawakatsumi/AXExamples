# AXExamples

Five small macOS sample apps that explore the **Accessibility (AX) API** — reading the
UI/text of *other* running apps (TextEdit, Safari) and visualizing it with on-screen overlays.
They are teaching material: each one builds on the previous, from "just dump the tree" to
"read a whole web page's text with the TextMarker API."

## Requirements
- macOS 13+ / Xcode
- **Accessibility permission.** On launch each app calls `AXIsProcessTrustedWithOptions` with
  the prompt option, so macOS shows the permission dialog the first time. Grant the app under
  **System Settings › Privacy & Security › Accessibility**, then relaunch.
  (When run from Xcode, the permission is attached to the running app/Xcode; if you rebuild and
  the identity changes you may need to re-grant.)
- The target app must be running with something on screen:
  - `01`–`03` inspect **TextEdit** (open a document with some text)
  - `04`–`05` inspect **Safari** (open a page; for `05` a text-heavy page / HTML mail view)

## How to run
Open the `AXExamples.xcodeproj` inside a folder and Run. Console examples print to Xcode's
console; overlay examples draw borderless windows on top of the target app.

## The five examples
| # | Folder | Target | What it shows |
|---|--------|--------|----------------|
| 1 | `01-DumpTree` | TextEdit | **Basics.** Request permission → get the app element → focused window → walk `kAXChildren`, printing each node's `role / subrole / title / value / description / chars` to the console. |
| 2 | `02-ShowElements` | TextEdit | **Element frames.** Walk the tree, read each element's `AXPosition`/`AXSize`, convert AX (top-left) → Cocoa coordinates, and draw a colored, role-labeled box over every element. |
| 3 | `03-ContentOverlay` | TextEdit | **Editable text.** Filter to editable text elements (`AXValue` is settable **and** it has a caret / selected-range, or is a text role) and overlay each region with its role + the retrieved `AXValue`. |
| 4 | `04-WebContentOverlay` | Safari | **Web text is fragmented.** Collect text-bearing elements (`AXStaticText`/`AXTextArea`/…; text via `AXValue → AXTitle → AXDescription`) across the page and draw a box + role header + a footer showing each fragment's text. Shows how web content is split into many leaf nodes. |
| 5 | `05-TextMarker` | Safari | **TextMarker API.** Find the WebArea (the element that has `AXStartTextMarker`) and read the **entire** text in one shot: `AXStartTextMarker`/`AXEndTextMarker` → `AXTextMarkerRangeForUnorderedTextMarkers` → `AXStringForTextMarkerRange`, without walking the leaves. The overlay is placed on the *net text rectangle* from `AXBoundsForTextMarkerRange` (not the full WebArea frame). |

## Key ideas across the samples
- Everything reads through two raw calls: `AXUIElementCopyAttributeValue` (plain attributes such
  as role/value/children/position/size) and `AXUIElementCopyParameterizedAttributeValue`
  (attributes that take an argument, e.g. TextMarker ranges, `AXBoundsForRange`).
- **Where the text lives depends on the element/role**: native text controls expose the whole
  string on the parent (`AXTextArea.AXValue`); rendered/read-only content (web, Mail) is split
  across many `AXStaticText` leaves (and some carriers use `AXDescription`).
- **TextMarker** (examples 04 vs 05) is the WebKit-only API that lets you read/navigate web text
  across element boundaries as one stream, instead of stitching leaves together yourself.
