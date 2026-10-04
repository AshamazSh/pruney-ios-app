# Pruney

Pruney is an iOS app for reviewing photos and videos and freeing up storage. The default app language is English.

The current implementation covers onboarding, Photos permission handling, a library size overview, and a swipe review screen. Filtering and actual deletion/compression are planned and are not implemented yet.

## Current behavior

1. On the first launch, show a welcome screen with a **Continue** button.
2. Request Photos access only after the user taps Continue.
3. Save onboarding completion after the permission request finishes, including when access is denied.
4. With full or limited access, analyze the accessible photo library and show the total file size, a segmented color bar, and a legend with sizes and item counts.
5. Show scan progress while analyzing. Handle an empty library separately.
6. With limited access, explain that the totals cover only selected assets and offer a Settings link.
7. With denied access, explain how to enable access and offer a Settings link. With system restrictions, explain Screen Time or device administration restrictions.

With photo access, the overview also shows two action tiles: **Start swiping** pushes the swipe review screen for the entire accessible library. **Set up filters** remains an interface placeholder with no action. With limited access, the swipe tile describes reviewing only the shared photos and videos.

## Swipe review

- Assets initially appear newest first, using a snapshot of the accessible library when the screen opens. The labeled sort menu in the top row can reorder only the remaining queue by date (newest first) or locally measured size (largest first). Previously selected assets and their decisions retain their history order.
- Size sorting measures uncached remaining assets locally, shows progress, and can be cancelled without changing the queue. Fully measured assets precede partially measured or unavailable assets. No cloud downloads are performed. Review actions are blocked until size sorting finishes or is cancelled.
- The top row shows red Delete, yellow Resized, and green Skipped counters from left to right, with a sort button on the right showing **By date** or **By size**. Resize and delete counts represent selected decisions, not completed file operations.
- The current photo is shown without cropping. Live Photos have a corner badge; this version displays their still image rather than Live Photo playback.
- Videos use the native player with playback controls and a seekable timeline. They start paused and pause when advancing, leaving the screen, sharing, or moving out of the active app state.
- Creation date and locally measured size appear below the media on the left, with the number of remaining items aligned to the right. Unavailable or partially measured resources are clearly identified. Preview and sharing requests do not download from iCloud.
- The bottom row contains undo, equally sized 64 pt red delete, yellow resize and green skip buttons from left to right, and a share button. Undo reverses the last decision and places its asset at the front of the current queue, even after changing sort order or reaching the final item. Other remaining items retain their order.
- Holding undo for 1.5 seconds fills a circular progress ring and opens a reset confirmation. A short tap still undoes one decision; releasing the hold early cancels the ring. Confirming reset clears all session decisions and counters and rebuilds the full queue in the selected sort order. Cancelling the alert preserves selections. An equivalent reset action is available to accessibility users. No originals are modified.
- The navigation bar’s **forward** button opens a choice of Skip all, Resize all, or Delete all for remaining items, including the current card. The chosen action records a decision for each remaining asset without changing earlier decisions or modifying originals. Undo restores those selections one item at a time, in reverse selection order.
- Button decisions and completed photo drags animate the current card offscreen: right for skip, up for resize, left for delete. The queue advances after the animation, with repeated decisions, undo, and sharing blocked during departure. Reduce Motion replaces departure with a short fade.
- One upcoming photo or video poster is prefetched locally and displayed beneath the current card. Dragging reveals it; an insufficient drag returns the current card to its original position. Prefetching does not download cloud resources or start video playback.
- On photos, swipe right to skip, left to mark for deletion, or up to mark for resizing. Video gestures are reserved for native playback controls; use the buttons to record video decisions.
- Sharing exports accessible asset resources to temporary files and opens the system share sheet. Live Photos share their still image and motion video as separate files. Temporary exports are removed after dismissal; originals are unchanged.
- The footer explains that this screen only selects actions and final changes happen later. Decisions exist only for the current review session. They are lost when leaving the screen and starting a new session. Completing the queue shows a summary state without modifying assets.

The overview uses three mutually exclusive categories:

| Category | Contents |
| --- | --- |
| Photos | Still photos, including screenshots, excluding Live Photos |
| Live Photos | Live Photo assets, including their photo and motion resources |
| Videos | Standalone video assets |

The info button beside **Accessible file size** opens a popover explaining how file sizes are measured, including any incomplete measurements. A short notice remains in the storage card when some items could not be fully measured. The refresh button is in the top-right navigation bar and is disabled during analysis.

Library changes trigger a new scan. Returning to the foreground rechecks authorization and restarts an unfinished scan. A completed scan can also be refreshed manually. Analysis is cancelled when the app enters the background.

## What the size means

Pruney measures bytes delivered by PhotoKit for accessible local asset resources, excluding adjustment data. Resources are read sequentially in chunks without retaining entire images or videos in memory.

Network access is disabled for these requests, so the analysis does not download cloud-only resources. If a resource cannot be read, the asset is marked as incompletely measured; successfully measured resources still contribute to the total. The screen explains when the total is incomplete.

These numbers represent accessible file sizes, not an exact measurement of physical disk usage or guaranteed recoverable space. They may differ from iPhone Settings. The app currently performs no photo library modifications.

## Planned review flow

The agreed direction is to select a media collection using tiles before reviewing its contents with swipes:

| Gesture | Intended action |
| --- | --- |
| Swipe left | Delete |
| Swipe right | Keep |
| Swipe up | Compress |

Proposed collection tiles include Photos, Videos, Live Photos, and Screenshots. Live Photos belong to the broader photo collection, with a separate tile for focused review; they do not belong to standalone videos. Collection tiles may overlap, but a review queue should contain each asset only once.

The exact filters, confirmation and undo behavior, handling of previously reviewed assets, compression quality, and handling of originals still need to be finalized before implementation. Converting a Live Photo to a still image is a proposed option, not an implemented compression feature.

## Project structure

| Path | Responsibility |
| --- | --- |
| `Pruney/PruneyApp.swift` | App entry point and Debug-only onboarding reset |
| `Pruney/ContentView.swift` | Onboarding, overview, push entry to review, storage bar, and access states |
| `Pruney/LibraryAnalysis.swift` | Authorization, observable scan state, PhotoKit scanner, and summary models |
| `Pruney/SwipeReviewView.swift` | Review counters, media player, metadata, action buttons, gestures, and share sheet |
| `Pruney/SwipeReviewModel.swift` | Session queue, decisions, undo, preview requests, local measurement, and temporary sharing exports |
| `Pruney/UndoHoldButton.swift` | Native undo button touch handling, 1.5-second hold recognition, and accessible reset action |
| `PruneyTests/PruneyTests.swift` | Classification, byte totals, partial results, and empty-library unit tests |
| `PruneyUITests/PruneyUITests.swift` | Permission grant/denial, overview, and onboarding persistence UI tests |
| `Pruney.xcodeproj` | Xcode project, scheme, build settings, and Photos usage description |
| `AGENTS.md` | Instructions for agents working in this repository |

## Build and run

The project was developed with Xcode 26.6. The app deployment target is iOS 17; the current test targets/settings require iOS 26.5. Swift language mode is 5, with MainActor default isolation and modern concurrency features, so use a toolchain compatible with the project settings.

Open `Pruney.xcodeproj`, select the **Pruney** scheme, choose an iPhone simulator or a configured device, and run. Device builds require an appropriate signing team.

Build for the simulator:

```sh
xcodebuild -project Pruney.xcodeproj -scheme Pruney \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/pruney-derived-data build
```

List available simulators and use a compatible simulator ID for tests:

```sh
xcrun simctl list devices available
xcodebuild -project Pruney.xcodeproj -scheme Pruney \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' \
  -parallel-testing-enabled NO \
  -derivedDataPath /tmp/pruney-derived-data \
  -only-testing:PruneyTests \
  -only-testing:PruneyUITests/PruneyUITests test
```

The unit tests cover classification and aggregation. UI tests cover full permission access, denied access, and skipping onboarding after a restart. Limited access, system restrictions, cloud-only resources, and large libraries also need manual verification; existing tests do not cover all of these cases.

For a Debug build, the launch argument `-resetOnboarding` clears the `hasCompletedOnboarding` preference. It does not reset Photos permissions. UI tests reset Photos authorization separately and retain screenshots as test attachments.
