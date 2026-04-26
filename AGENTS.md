# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Commands

```bash
# Install dependencies
flutter pub get

# Run app (debug)
flutter run

# Run tests
flutter test

# Run a single test file
flutter test test/path/to/test_file.dart

# Build Android APK
flutter build apk --release

# Build iOS (macOS only)
flutter build ios --release

# Lint
flutter analyze
```

## Architecture

This is a Flutter app using **BLoC** for state management, **SQLite** (sqflite) for persistence, and **Google ML Kit** for OCR.

### Feature-First Structure

`lib/` is organized by feature under `features/`, with shared infrastructure in `core/` and `shared/`:

- **`features/canvas/`** — Infinite handwriting canvas. `CanvasBloc` manages drawing strokes, undo/redo stacks, and tool selection (pen/pencil/eraser). `CanvasPainter` renders strokes via `CustomPainter` under a `viewTransform` (Matrix4) that maps **World → Screen**.

  **Coordinate systems:**
  - All strokes (`DrawingStroke.points`) are stored in **World coordinates**, independent of viewport.
  - `_transformController` (`TransformationController` in `CanvasScreen`) holds the current view transform.
  - `_screenToWorld(Offset)` inverts the transform to map finger taps back to World coords before appending to the active stroke.

  **Gestures (`RawGestureDetector` + `ScaleGestureRecognizer`):**
  - 1 finger drag → draw (in World coords)
  - 2+ finger drag/pinch → pan + zoom; clamped to `[0.25x, 4x]` via `_minScale`/`_maxScale`
  - 1→2 finger transition mid-stroke → drop the in-progress stroke and switch to pan mode
  - Multi-finger taps (no movement) still trigger undo/redo via the surrounding `Listener`.

  **Capture pipeline (`features/canvas/services/offscreen_canvas_renderer.dart`):**
  - All snapshot/OCR/thumbnail captures use `OffscreenCanvasRenderer.render()` which renders the **entire ink bounding box** with padding into a `PictureRecorder`-backed PNG, independent of the on-screen viewport.
  - `OffscreenCanvasRenderer.computeInkBounds(strokes, padding:)` is reused by `_fitToInk()` to center old notes on first layout.

  **Old-note compatibility:**
  - On `_loadExistingNote`, `_pendingFitToInkOnLayout = true`. The next `LayoutBuilder` pass schedules a post-frame `_fitToInk()` so legacy notes (whose strokes happen to live in old screen-coord ranges) auto-center.

  **Toolbar viewport controls (`canvas_toolbar.dart`):**
  - `_ZoomBadge` listens to the controller and shows live zoom %; tapping it resets the view (100%, origin).
  - "适配笔迹" runs `_fitToInk`; "复位视图" runs `_resetCanvasTransform`.
- **`features/notelist/`** — Main screen listing notes. `NoteListBloc` handles load, search, create, delete via `DatabaseHelper`.
- **`features/notedetail/`** — Read-only note detail with OCR results.
- **`features/search/`** — Search screen filtering notes by OCR-recognized text.

### Core Layer

- **`core/storage/database_helper.dart`** — Singleton SQLite helper. Three tables: `notebooks`, `notes`, `note_entries`. `notes` stores canvas strokes as BLOB, a snapshot image path, and recognized OCR text. `note_entries` stores parsed results (expenses, events, todos, memos).
- **`core/storage/image_storage.dart`** — Static utility managing `snapshots/` and `thumbnails/` under `ApplicationDocumentsDirectory/images/`.
- **`core/ocr/`** — OCR abstraction: `ocr_engine.dart` defines the interface; `mlkit_ocr.dart` implements via Google ML Kit; `vision_ocr.dart` is for Apple Vision (iOS-only).
- **`core/parser/`** — Post-OCR parsing: `entry_parser.dart` classifies recognized text into entry types; `expense_extractor.dart` extracts expense amounts.

### Navigation

No named routes or go_router. Navigation is imperative via `Navigator.push`. `NoteListScreen` is the initial route. Both `NoteListBloc` and `CanvasBloc` are provided globally at app root via `MultiBlocProvider` in `app/app.dart`.

### Key Data Flow

1. User draws on canvas → `CanvasBloc` accumulates `DrawingStroke` objects
2. On save: strokes serialized to BLOB + screenshot captured → stored via `DatabaseHelper` + `ImageStorage`
3. OCR runs on the screenshot → recognized text stored back to the note
4. `NoteListBloc` reloads → `note_entries` parsed from OCR text via `entry_parser`
