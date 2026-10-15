# Pruney

Pruney is an iOS app for reviewing photos and videos and freeing up storage. English is the source and fallback language; the interface follows the device's supported language preference.

## Localization

The app supports English (en), Spanish (es), Brazilian Portuguese (pt-BR), German (de), French (fr), Japanese (ja), Korean (ko), Simplified Chinese (zh-Hans), Italian (it), and Russian (ru). Localizable.xcstrings contains interface, accessibility, filter, compression, review, execution, and purchase fallback copy. InfoPlist.xcstrings localizes the Photos permission explanation; the original English build-setting value remains identical in Debug and Release. No in-app language selector is added. iOS can expose its per-app language setting now that supported languages are bundled.

String-valued model labels, composed descriptions, and UIKit accessibility actions use String(localized:) explicitly. Dates and measured byte counts retain platform locale formatting. Catalog format placeholders preserve value types; English item counts include singular variants, and translations use neutral count labels where appropriate. Stable accessibility identifiers do not derive from translated headings. Existing English UI assertions explicitly launch the app in English; system permission buttons still follow the device language.

The purchase's name, description, and price continue to come from StoreKit when available; app translations cover fallback copy, controls, and benefits. StoreKit product metadata is managed separately in App Store Connect and is not overwritten by the app's catalogs. Native system errors are displayed using their localizedDescription. Pruney and Live Photos brand labels remain unchanged in applicable localizations.

Catalog Swift symbol generation is disabled in both app build configurations because English source keys include format-only strings and colliding punctuation; runtime String(localized:) lookup is used instead. New project text must still be authored in English. Translate newly added or revised strings only after a separate explicit request; keep existing localized resources when changing unrelated features.

All 238 interface keys and the three InfoPlist keys (Photos permission and both bundle-name keys) have translated values for every supported language. The five home/purchase/cache additions were translated at the user's explicit release request; Pruney remains unchanged as the brand name. Existing translations and format arguments were preserved. The latest unsigned device Release build succeeded, and all new translations plus InfoPlist values were checked in each of its ten compiled language bundles. The overview UI assertion now accepts both the fresh and cached size headings. The Russian home labels and cache explanation popover were visually checked on the dedicated iPhone 17 Pro / iOS 26.5 QA simulator; new text layouts in the other languages remain unverified. Automated tests were not run for this translation update. Catalog format placeholders and compiled localization resources were checked. The simulator build succeeded. Main-library rendering was visually checked in Russian, German, and Japanese on iPhone 17 Pro / iOS 26.5, together with the Russian new-filter form and German onboarding. Other languages and screens, permission-dialog rendering, dynamic text sizes, older OS versions, and purchase metadata in each storefront remain unverified. Tests were not run.

The current implementation covers onboarding, Photos permission handling, a library size overview, swipe review, user-configured filters, resize settings, and action execution. Confirmed deletion and resizing are implemented. Unsupported-type filtering is also implemented in swipe review.

## Appearance

The app icon uses the approved simplified lilac plum, mint leaf, and white sparkle on a full-bleed purple background. The opaque 1024 × 1024 PNG is installed in the AppIcon asset catalog; a separate identical App Store export is available at `branding/Pruney-AppStore-1024.png`. iOS applies the icon's corner mask. The transparent PruneyMark asset is also used on onboarding.

`LaunchScreen.storyboard` displays the plum mark and Pruney wordmark centered on white in light appearance and deep plum in dark appearance, using adaptive LaunchBackground and LaunchForeground color assets. Both build configurations use this native launch screen; there is no artificial splash delay or extra permission request. Brand artwork was prepared with the built-in imagegen tool from the approved simplified-plum reference; generation prompts are recorded in `branding/README.md`. The launch screen was visually checked in both appearances on the iPhone 17 Pro simulator running iOS 26.5. Other screen sizes, older iOS versions, and onboarding rendering remain unverified. The simulator build succeeded; tests were not run.

The brand accent adapts to the system appearance: purple `#7543A3` in light mode and lavender `#C5A3F5` in dark mode. Accent-filled primary buttons and the Start swiping tile use white foregrounds in light mode and dark purple `#271638` in dark mode. Color assets provide automatic updates when appearance changes. Semantic Keep, Resize/Make static, and Delete colors are unchanged. Theme rendering still requires simulator or device verification.

## Current behavior

1. On the first launch, show a welcome screen with a **Continue** button.
2. Request Photos access only after the user taps Continue.
3. Save onboarding completion after the permission request finishes, including when access is denied.
4. With full or limited access, analyze the accessible photo library and show the total file size, a segmented color bar, and a legend with sizes and item counts.
5. Show scan progress while analyzing. Handle an empty library separately.
6. With limited access, explain that the totals cover only selected assets and offer a Settings link.
7. With denied access, explain how to enable access and offer a Settings link. With system restrictions, explain Screen Time or device administration restrictions.

With photo access, the overview shows two action tiles only after library analysis finishes successfully. Both tiles remain hidden during the initial scan, rescans, and interrupted or failed analysis. **Start swiping** pushes the swipe review screen for supported items in the accessible library. **Set up filters** pushes the filter list. With limited access, review and filtering cover only the shared photos and videos.

## Review filters

- Filters appear as descriptive tiles with a trailing remove button. **OR** appears between tiles: an asset needs to match any one filter, and all enabled conditions inside that filter must match. An asset matching several filters enters the queue only once.
- The bottom bar has a secondary **Add** button and a primary **Apply** button. Apply is disabled when the list is empty. Add presents the New filter form as a bottom sheet with a drag indicator and Cancel button. Its primary Add button appends the filter and dismisses the sheet; cancelling or dismissing leaves the list unchanged. At least one condition must be enabled before adding.
- Each condition has a left checkmark aligned vertically with its heading that enables or disables its controls. Controls sit directly below the heading row without an extra vertical gap; spacing between controls is retained. Menus use explicit leading-aligned labels without the standard menu picker's inset; the date picker and size controls also align to the heading's leading edge. Type is Photos, Live Photos, or Videos, with mutually exclusive categories. Date is From or To with a creation-date picker; both include the selected calendar day in the current time zone. Assets without a creation date cannot match a date condition.
- Size is Less than or Greater than, with a slider from 1 MB to 1 GB in 1 MB steps (decimal units). Comparisons are strict. Disabled condition values remain in the form but are omitted from the added filter.
- Apply snapshots the filters and pushes swipe review. Supported-type checks still run first. Type and date conditions use metadata; resource bytes are read only when a possible match requires a size condition. An asset matching a filter without a size condition needs no size read during preparation. Reads remain bounded and local, with no iCloud downloads. Live Photo size includes its readable still and motion resources using the same measurement policy as the overview.
- Incomplete sizes cannot match size conditions, and their exclusions are shown separately. Preparation shows progress, preserves cancellation/generation safeguards, and caches measured sizes for review and sorting. No matches displays **No matching items** with guidance to adjust filters. Undo and reset remain scoped to the filtered queue. Completion returns to the main library screen using the same action flow and Recently Deleted notice as full-library review.
- Filters remain in memory while their screen is in the navigation stack; they are not saved between separate filter sessions or launches. The interface and matching have been build-checked only; date boundaries, size filtering, OR combinations, cancellation, limited access, empty results, and navigation need simulator or device verification. Tests have not been run for this feature.

## Swipe review

- System swipe-back navigation is disabled while the swipe review screen is visible, including the content-area back gesture on iOS 26. The navigation bar Back button remains available except during deletion. Previous gesture states are restored when leaving review so subsequent screens retain their navigation behavior. Gesture blocking requires simulator or device verification.
- Assets initially appear newest first, using a snapshot of the accessible library when the screen opens. The labeled sort menu in the top row can reorder only the remaining queue by date (newest first) or locally measured size (largest first). Previously selected assets and their decisions retain their history order.
- Before cards appear, a background metadata pass filters the snapshot through the shared `SupportedMediaFormats` policy. Photos and Live Photos require a non-RAW original still format that Image I/O can read and encode on the current device, with a known file extension. RAW/ProRAW and RAW+JPEG assets are excluded. Videos require an available video resource whose movie type is in AVFoundation's supported audiovisual content types; iOS 17–25 use the compatible file-type API.
- Format preparation shows progress, does not read resource contents or download from iCloud, and is cancelled on leaving the screen or becoming inactive. An unfinished preparation restarts on return; generation checks prevent stale results from replacing the current queue.
- Excluded items appear as a separate count, never as user Keep decisions. Only eligible items enter cards, next-card prefetching, progress totals, sorting, bulk actions, action settings, and undo/reset history. If every available item is excluded, show **No supported items** instead of an empty-library message. Library overview counts and sizes still include all accessible assets.
- Metadata filtering removes known unsupported types. It does not detect unavailable local contents, unsupported video codecs or edited compositions, encoder incompatibilities, or outputs without size savings; execution still validates and reports these cases without removing resize originals.

- Size sorting measures uncached remaining assets locally, shows progress, and can be cancelled without changing the queue. Fully measured assets precede partially measured or unavailable assets. No cloud downloads are performed. Review actions are blocked until size sorting finishes or is cancelled.
- The top row shows red Delete, yellow Resized, and green Kept counters from left to right, with a sort button on the right showing **By date** or **By size**. Resize and delete counts represent selected decisions, not completed file operations.
- The current photo is shown without cropping. Live Photos have a corner badge; this version displays their still image rather than Live Photo playback.
- Videos use an AVPlayerLayer surface with separate play/pause, mute, and seek controls below it. The video surface accepts review drags; the control area does not select review actions. Videos start paused and pause when dragging, advancing, leaving the screen, sharing, or moving out of the active app state. Playback controls and video dragging still need manual verification on the simulator or device; tests were not run for this fix.
- Creation date and locally measured size appear below the media on the left, with the number of remaining items aligned to the right. Unavailable or partially measured resources are clearly identified. Preview and sharing requests do not download from iCloud.
- The bottom row contains undo, equally sized 64 pt red delete, yellow resize and green keep buttons from left to right, and a share button. Undo reverses the last decision and places its asset at the front of the current queue, even after changing sort order or reaching the final item. Other remaining items retain their order.
- Holding undo for 1.5 seconds fills a circular progress ring and opens a reset confirmation. A short tap still undoes one decision; releasing the hold early cancels the ring. Confirming reset clears all session decisions and counters and rebuilds the full queue in the selected sort order. Cancelling the alert preserves selections. An equivalent reset action is available to accessibility users. No originals are modified.
- The navigation bar’s **forward** button opens a choice of Keep all, Resize all, or Delete all for remaining items, including the current card. The chosen action records a decision for each remaining asset without changing earlier decisions or modifying originals. Undo restores those selections one item at a time, in reverse selection order.
- Button decisions and completed photo or video drags animate the current card offscreen: right for keep, up for resize, left for delete. The queue advances after the animation, with repeated decisions, undo, and sharing blocked during departure. Reduce Motion replaces departure with a short fade.
- One upcoming photo or video poster is prefetched locally and displayed beneath the current card. Upcoming videos and current videos awaiting their local player use the same video-card layout, including the playback panel and known asset duration; controls stay inactive until playback is ready. Loading the player replaces the poster within the existing media surface without adding a panel or resizing the preview. Dragging reveals it; an insufficient drag returns the current card to its original position. Prefetching does not download cloud resources or start video playback.
- On photos and the video surface, swipe right to keep, left to mark for deletion, or up to mark for resizing (Make static for Live Photos). Video playback pauses when dragging starts, including drags that return the card to its original position.
- Drag translation is measured in the stationary media container so card movement and rotation do not feed back into the gesture. Finger tracking updates without implicit animation; return and departure animations remain enabled. Video controls ignore touches during dragging without changing their enabled appearance.
- Sharing exports accessible asset resources to temporary files and opens the system share sheet. Live Photos share their still image and motion video as separate files. Temporary exports are removed after dismissal; originals are unchanged.
- Swipe review and resize settings omit the “No changes applied yet” footer. Both screens still only select actions; final changes happen later. Decisions exist only for the current review session. They are lost when leaving the screen and starting a new session. Completing a queue with resize or Make static candidates shows **Continue** to **Resize & make static** settings. Without replacement candidates, show **Delete X** for the deletion count; tapping it starts one deletion batch with only the system Photos confirmation and returns directly to the library after success. If every item was kept, show **Back to library**. While deleting, show progress and disable back navigation and review controls. A rejected or failed deletion shows an error and preserves the review choices for retry.

## Action settings

- If any assets were marked for resizing or making static, **Continue** opens **Resize & make static** settings. There is no Delete settings screen; deletion candidates come directly from swipe decisions.
- **Resize & make static** shows a three-column grid split into Photos, Live Photos, and Videos. Empty sections are omitted. Assets retain the order they were added to the corresponding decision list within each section.
- All candidate assets start checked. Tapping a tile or its checkmark toggles inclusion without removing it from the grid. Deselected thumbnails fade while their selection controls remain visible. Resize checks are yellow.
- Each selected non-Live Photo or video resize tile has a bottom-right **Compression** menu with four levels: Light, Balanced, High, and Maximum. The tile shows the selected name; Maximum is the default, preserving the intent of the previous 50% setting. Deselected items retain their value, but their compression control is hidden until reselected. Levels retain 90%, 80%, 70%, or 50% of the photo dimensions respectively, with quality 95 for supported lossy formats; PNG uses lossless encoding after resizing. For videos, levels select a compatible standard export resolution at or below the target scale; multiple levels can produce the same resolution. These percentages describe dimensions, not guaranteed file size savings.
- The settings navigation bar has an **Apply all** menu with the same four compression levels when regular photo or video candidates exist. It updates only those candidates, including deselected items. Live Photos have a fixed **Make static** label, no compression menu or level, and are ignored by Apply all. A Live-Photo-only selection has no Apply all menu.
- Compression controls keep a consistent width within each tile, preserving their capsule corners when switching between shorter and longer level names.
- **Continue** uses the same large, full-width primary button style as filter Apply and pushes the final action overview directly from the replacement settings, including when all resize checkmarks have been cleared. No originals are modified in settings.
- Changes persist when returning from the final overview and when reopening settings from an unchanged completed review. Changing the swipe decisions or resetting the review creates a new plan the next time settings are opened.
- The final overview shows selected counts for Delete, Resize, and Make static by media category, plus compression level counts for regular photos and videos only. Unchecked resize items are excluded; deletion choices can be changed using undo before entering settings. The Recently Deleted footnote has been moved to the main library screen.

## Free allowance and lifetime Pro

- The bottom of the main library screen has a **Remove all limits** button that opens the existing lifetime purchase sheet. This control is hidden during library analysis, including rescans, and becomes available when analysis stops; it is also available when Photos access is unavailable. An active verified entitlement replaces the button with **Pruney Pro is active**, which is likewise hidden during analysis. The home entry shows the standard free allowances without review-specific remaining-selection or cancellation copy; the existing in-review entry retains that context and pending-selection behavior. Purchase, restore, verification, and revocation still use the shared `ProAccess` state. The home-entry copy is localized in all supported languages.
- The home entry was build-checked and manually checked on the dedicated iPhone 17 Pro / iOS 26.5 QA simulator: opening the purchase sheet and cancelling returned to the library. Unit/UI tests were not run for this change. Actual purchase, restoration, and the active-Pro presentation remain unverified for this entry.

- The free plan allows up to 50 selected deletions and 10 selected resize or Make static replacements per execution run. The limits are independent: one run may contain both 50 deletions and 10 conversions. There is no cumulative or daily limit, so users can start further free reviews with the full allowance. Keep, analysis, sharing, and all filters remain free and unlimited. Removing an original as part of a replacement does not count as another deletion.
- Swipe/button decisions reserve capacity within the current review only. A single action that would exceed its per-run limit presents a Pruney Pro purchase sheet before the card advances. Cancel or sheet dismissal returns the card to its original position and preserves all choices. A verified purchase or restoration resumes that single pending selection only if the same asset is still current. Pending, cancelled, unavailable, failed, and unverified purchases do not unlock Pro or advance the card.
- Bulk Delete or Resize / Make static is checked against the entire remaining queue plus current choices. An over-limit bulk action is cancelled completely; nothing is selected partially. It stays cancelled after unlocking, and the user can explicitly choose it again. Keep all bypasses limit checks. Undo/reset release session reservations. The review footer shows remaining capacity for this run.
- Execution rechecks the selected plan against the same 50/10 limits before making Photos changes, including when a lifetime entitlement has been revoked. Deselecting replacement candidates reduces the execution count. No usage is accumulated or persisted after success, failure, or cancellation; Pro removes both per-run limits.
- Lifetime Pro uses StoreKit 2 and a non-consumable product, verified current entitlements, transaction updates, and a user-initiated Restore purchases action. Purchase and entitlement checks respect revocation. There is no subscription or recurring charge. The purchase sheet uses the approved PRO artwork without an infinity symbol, displays the product's localized name, description, and price from StoreKit, and lists unlimited Delete, Resize, and Make static benefits. English fallback copy appears before product data arrives. Purchase and restore controls stay in a bottom inset; loading, purchasing, restoring, unavailable, and Retry states remain explicit. Product data is requested on presentation and refreshed when the visible sheet returns to the foreground outside a purchase or restore. Purchasing is disabled while product data loads or is unavailable; it never substitutes a fake unlock. Existing selection cancellation and verified-unlock behavior are preserved.
- Previous cumulative free-usage Keychain records are no longer read or written and have no effect on the new limits. Review choices remain session-only; purchase ownership continues to come from StoreKit.

### Store setup

Create **Pruney Pro Lifetime** in App Store Connect as a **Non-Consumable** In-App Purchase with product ID `com.ashamazsh.pruney.pro.lifetime`, matching `ProAccess.productID`. Configure its localized name/description, price, availability, and review information under this app. The owner reports completing the product information in App Store Connect; these external settings and live StoreKit availability have not been independently verified here. The price is not hardcoded in the app. Configure the same product ID/type in an Xcode StoreKit configuration if local purchase simulation is desired; no StoreKit configuration is enabled by this change. Real purchases require the App Store Connect product and appropriate signing/distribution setup.

The implementation has been build-checked only. Purchase/restore, pending approval, cancellations, refunds, unavailable products, quota boundaries, undo/reset, bulk rejection, per-run limit renewal, and final-plan validation require simulator/device and StoreKit sandbox verification. Tests have not been run.

Friends can receive lifetime Pro through a free offer on the existing non-consumable purchase using [Apple Offer Codes](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-offer-codes-for-in-app-purchases). Redemption can happen through the App Store or a redemption URL without a custom in-app code field. Production codes require the app to be Ready for Distribution and the In-App Purchase to be Approved. No custom redemption UI, bypass, or offer creation is implemented by the home purchase entry.

## Debug Pro simulation

The user-defined app target Build Setting `PRUNEY_SIMULATE_PRO` controls lifetime Pro simulation for Debug builds. It defaults to `NO`. In Xcode, select the **Pruney target > Build Settings > All > User-Defined > PRUNEY_SIMULATE_PRO**, set **Debug** to `YES` to enable simulation or `NO` to disable it, then rebuild. This setting generates the Swift compilation condition `PRUNEY_SIMULATE_PRO_YES` or `PRUNEY_SIMULATE_PRO_NO`, retaining inherited conditions. The old manually added `PRUNEY_SIMULATE_PRO` compilation condition is no longer needed and can be removed. No Info.plist key is used.

In this mode `ProAccess` starts unlocked, all per-run quota checks permit unlimited selections, and the home screen shows the existing active-Pro status after analysis. Entitlement refresh cannot overwrite the simulated state. StoreKit product loading, transaction observation and restoration are bypassed; no purchase is made and no simulated entitlement is persisted. Returning to an ordinary build uses verified StoreKit entitlements again. Release ignores this setting because its compilation conditions do not include the generated simulation flag and `DEBUG` is absent from that configuration. Use the ordinary Debug configuration for quota and StoreKit lifecycle tests.

Example simulator build with simulation enabled:

```sh
xcodebuild -project Pruney.xcodeproj -scheme Pruney -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/pruney-simulated-pro \
  PRUNEY_SIMULATE_PRO=YES build
```

Validation: ordinary Debug, simulated Debug, and unsigned device Release built successfully for the original simulation implementation. The new Build Setting also built successfully with Debug defaulting to `NO`, Debug overridden to `YES`, and unsigned device Release overridden to `YES`. Compiler invocations confirmed the expected Debug condition and no simulation condition in Release. The active-Pro state was manually observed on the dedicated QA simulator. Automated tests were not run. This developer-only simulation does not validate real purchases, restoration or revocation.

## Applying actions

- In sessions that enter replacement settings, **Start** on the final overview immediately begins execution without an additional in-app confirmation. It uses the same large, full-width primary button style as filter Apply. PhotoKit retains its system confirmations. Starting is disabled when no items are selected.
- The selected plan is snapshotted at Start, or at Delete X in the deletion-only path. The deletion batch runs first; replacement preparation starts only after successful deletion. A rejected or failed deletion stops the run and shows an issue rather than claiming success.
- Resize candidates are processed sequentially. For unedited photos, the actual local photo resource is written to a temporary file, preserving access to animation frames and HDR data rather than requesting a rendered still. Edited photos use the current local editing input.
- The original resource determines the output format. Any non-RAW image format in the current device’s Image I/O encoder list is eligible, including JPEG, HEIC, PNG, GIF, TIFF, BMP, and JPEG 2000 when supported. No third-party dependency is needed for this path. Lossy formats use quality 95 where supported. Unsupported formats and RAW/ProRAW are kept unchanged rather than converted to JPEG.
- Image I/O scales frames directly from the source, copying available metadata, orientation, GIF/APNG frame timings and loop settings, and requesting HDR gain map preservation. Output format, frame count, maximum pixel dimensions, alpha presence, GIF/APNG timings, and existing Apple/ISO HDR gain maps are checked before replacement. This does not guarantee preservation of all HDR encodings, depth data, or auxiliary data; edit history is not preserved. Photos-level creation date, location, favorite status, and editable album memberships are copied to the replacement asset.
- Live Photos support only **Make static**. The current still resource (full-size edited photo when present, otherwise the photo resource) is copied byte-for-byte to a temporary file and validated as a readable image of the declared format. No re-encoding, dimension reduction, or compression level is applied. The replacement is imported as an ordinary photo without the paired motion resource. It shares the confirmed replacement transaction and metadata/album preservation with resized items. Unavailable or invalid still resources leave the original intact. Still bytes need not be smaller than the still source, because savings come from removing motion; immediate device-space recovery is not guaranteed until Recently Deleted is emptied. Edited Live Photos, HDR, and static conversion require device or simulator verification.
- Videos use the current local AVAsset and compatible standard export presets (4K, 1080p, 720p, 540p, or 640×480 bounds) without retaining entire videos in memory. Unsupported edited video compositions, unavailable local originals, incompatible formats or image sequences, outputs that fail validation, or outputs that are not smaller are reported and kept unchanged. No cloud downloads are requested.
- Replacement processing prepares and validates smaller resized files or unchanged Live Photo still files without changing the library. After all candidates have been processed, every successfully prepared replacement is created and all corresponding originals are deleted in one PhotoKit transaction. The run uses at most two `performChanges` calls: the initial nonempty deletion batch and the nonempty replacement batch. iOS controls system confirmation dialogs; they cannot be suppressed, but no per-item deletion transaction is made. A failed or rejected replacement batch keeps all resize originals intact, while any successful earlier deletion batch remains applied. Resize and Make static success counts are updated only after the replacement transaction succeeds.
- Prepared outputs accumulate on disk before the replacement batch, so temporary storage grows with their total size. PhotoKit imports these closed, app-owned files with `shouldMoveFile = true`, moving them into Photos without an intermediary copy of each output. This reduces import storage overhead but does not eliminate space needed for encoding or system processing. Unedited source copies are removed after successful encoding. After the batch completes, remaining temporary files and directories are cleaned up on success or failure; cleanup also handles outputs already moved by Photos. Encoding failures clean up their own directories. File moving and low-storage behavior require device or simulator verification.
- Processing shows overall item progress and intermediate video-export progress, reserves the final 10% for saving resize replacements, displays a separate saving status, asks the user to keep Pruney open, disables back navigation, and temporarily prevents automatic screen locking. New items wait while the app is inactive; an in-flight operation can continue or be suspended by iOS. Force-quitting is not supported, completed actions are not rolled back, and there is no automatic recovery or retry after termination.
- Completion shows separate successful deletion, resize, and Make static counts. Failures are listed separately as **Finished with issues**; complete success shows **All done!**. **Back to library** returns to the root overview and refreshes its measurements.
- After either flow returns to the main library screen with successful deletions (including replaced originals), an alert explains that deleted files remain in Recently Deleted for up to 30 days and that users must empty it themselves in Photos to free space immediately. No alert is shown after a session where every item was kept or an execution with no successful removals. Pruney does not permanently empty Recently Deleted.
- The execution flow has been build-checked only. Actual deletion, replacement, deletion-only return flow, Recently Deleted alert presentation, batched system confirmations and their cancellation, encoding results, limited access, HDR media, GIF/APNG animations, multipage images, device-specific encoder support, excluded-format counts and all-excluded review states, interrupted execution, and behavior on iOS 17 require device or simulator verification; tests have not been run for this feature.

The overview uses three mutually exclusive categories:

| Category | Contents |
| --- | --- |
| Photos | Still photos, including screenshots, excluding Live Photos |
| Live Photos | Live Photo assets, including their photo and motion resources |
| Videos | Standalone video assets |

The info button beside **Accessible file size** opens a popover explaining how file sizes are measured, including any incomplete measurements. A short notice remains in the storage card when some items could not be fully measured. The refresh button is in the top-right navigation bar and is disabled during analysis.

Library observation follows the same asset snapshot used by the scanner. Insertions, removals, media category changes, and asset-content changes trigger a cache-backed scan; unrelated notifications, album changes, favorites, and metadata-only changes do not. If PhotoKit cannot provide incremental changes, the app conservatively forces a fresh scan. Returning to the foreground rechecks authorization and restarts an interrupted scan, while an already running scan is preserved. Analysis is cancelled on backgrounding; relevant background changes invalidate the result and wait until foregrounding to rescan. A completed scan can also be refreshed manually. Notification filtering and foreground/background timing require device or simulator verification.

## Persistent overview measurements

The overview now persists completed per-asset byte measurements in an app-owned Caches JSON file. After the initial scan, it uses a securely serialized `PHPersistentChangeToken` and [PhotoKit's persistent change history](https://developer.apple.com/videos/play/wwdc2022/10132/) to invalidate inserted, updated, and deleted assets across launches. It also reconciles currently accessible identifiers and checks public asset metadata before reuse. Cache hits avoid both resource enumeration and byte reads. New or invalidated assets are streamed using the original local-only measurement policy. Library overview totals remain inclusive of unsupported media; photo, Live Photo and video categories remain mutually exclusive.

The history token is captured before fetching the observed asset snapshot and saved with invalidations atomically, so edits during a scan remain eligible for the next replay. Cold scans checkpoint every 200 newly measured assets and preserve completed measurements on cancellation. Partial or unavailable results are never persisted as complete measurements. Missing, incompatible, corrupt, or expired-history caches rebuild safely; a cache write failure does not fail the analysis. Cache loading, reconciliation, serialization and resource reads execute on the scanner actor, with throttled main-actor progress updates and cancellation/generation checks. Revoking access clears displayed results and requests cache removal; limited access prunes entries outside the current accessible subset.

Cached sizes describe previous successful measurements of unchanged assets. They cannot establish whether iOS subsequently evicted a local iCloud resource. The storage card therefore uses **Measured file size** when cached values are included, displays a saved-measurement notice, and explains the limitation in its info popover. **Refresh totals** forces a full local remeasurement. No cloud downloads are enabled. Review, size filtering and sorting deliberately retain fresh reads and their existing session caches rather than accepting historical measurements as proof of current local availability. A shared cache for those flows remains separate planned work.

`LibraryScanner.swift` now contains resource streaming and overview cache orchestration; `LibraryMeasurementCache.swift` contains the versioned persisted value types. The cache stores identifiers, public metadata/resource descriptors, byte totals and the change token, without copying photo/video content. The English Privacy Policy documents this local cache. Cache interface copy is localized in all supported languages.

Validation: Debug simulator and unsigned device Release builds succeeded. On the dedicated iPhone 17 Pro / iOS 26.5 QA simulator, an initial scan persisted 67 measurements; terminating and reopening the app reused all 67. A forced refresh read all 67 files (about 0.381 seconds in the scanner), whereas the cached scan reused 67 and read zero (about 0.016 seconds). Importing one demonstration PNG updated totals to 68 items and read only that new item, reusing the other 67 (about 0.018 seconds). These are small-fixture scanner timings, including cache preparation but excluding the app's full startup and initial PhotoKit snapshot fetch; they do not predict large-library performance on a phone. Local debug metrics are in `/tmp/pruney-cache-manual-metrics.log`. Five cache unit-test methods were added for persistence/token pairing, edit invalidation, partial results, accessible-subset pruning, corrupt/incompatible files and summary accounting. Their target was compiled with `build-for-testing`; tests were not executed. Large libraries, physical-device performance, iCloud eviction, expired history, limited-access transitions and interrupted checkpoint recovery still require verification.

## What the size means

Pruney measures bytes delivered by PhotoKit for accessible local asset resources, excluding adjustment data. Resources are read sequentially in chunks without retaining entire images or videos in memory.

Network access is disabled for these requests, so the analysis does not download cloud-only resources. If a resource cannot be read, the asset is marked as incompletely measured; successfully measured resources still contribute to the total. The screen explains when the total is incomplete.

These numbers represent accessible file sizes, not an exact measurement of physical disk usage or guaranteed recoverable space. They may differ from iPhone Settings. Onboarding, analysis, swipe review, and settings perform no photo library modifications. Only actions started by the user from the final overview or Delete X modify the library, subject to Photos system confirmation.

## Planned review flow

The agreed direction is to select a media collection using tiles before reviewing its contents with swipes:

| Gesture | Intended action |
| --- | --- |
| Swipe left | Delete |
| Swipe right | Keep |
| Swipe up | Compress |

Proposed collection tiles include Photos, Videos, Live Photos, and Screenshots. Live Photos belong to the broader photo collection, with a separate tile for focused review; they do not belong to standalone videos. Collection tiles may overlap, but a review queue should contain each asset only once.

Additional collection filters and handling of assets reviewed in previous sessions remain planned. Preserving Live Photo motion during resizing is not implemented; the confirmed Make static action preserves the current still image bytes and dimensions while removing motion.

## Project structure

| Path | Responsibility |
| --- | --- |
| `Pruney/PruneyApp.swift` | App entry point and Debug-only onboarding reset |
| `Pruney/PruneyStyle.swift` | Shared appearance-aware brand accent, foreground, and background colors |
| `Pruney/Localizable.xcstrings` | English source strings and nine interface/accessibility translations |
| `Pruney/InfoPlist.xcstrings` | Localized Photos permission explanation |
| `Pruney/ProAccess.swift` | Verified lifetime entitlement, StoreKit purchase/restore, and per-run free-limit validation |
| `Pruney/ProPurchaseView.swift` | In-review lifetime purchase sheet and restore controls |
| `Pruney/ContentView.swift` | Onboarding, overview, push entry to review, storage bar, and access states |
| `Pruney/LibraryAnalysis.swift` | Authorization, observable scan state, change observation, and summary models |
| `Pruney/LibraryScanner.swift` | Bounded resource streaming, cached overview scans, and persistent-history invalidation |
| `Pruney/LibraryMeasurementCache.swift` | Versioned per-asset measurements, metadata fingerprints, and atomic cache storage |
| `Pruney/SwipeReviewView.swift` | Review counters, media player, metadata, action buttons, gestures, and share sheet |
| `Pruney/ReviewVideoCard.swift` | Draggable video surface, separate playback controls, and playback observer lifecycle |
| `Pruney/ReviewNavigationGestureGuard.swift` | Scoped system back-gesture suppression during swipe review |
| `Pruney/ReviewFilter.swift` | Filter values, descriptions, and type/date/size matching |
| `Pruney/ReviewFiltersView.swift` | Filter tiles, condition form, and entry to filtered swipe review |
| `Pruney/SupportedMediaFormats.swift` | Shared image/video format eligibility and background loading of the filtered review queue |
| `Pruney/SwipeReviewModel.swift` | Session queue, decisions, undo, preview requests, local measurement, and temporary sharing exports |
| `Pruney/UndoHoldButton.swift` | Native undo button touch handling, 1.5-second hold recognition, and accessible reset action |
| `Pruney/ReviewActionPlan.swift` | Draft action candidates, resize selections, per-item compression settings, and action groups |
| `Pruney/FinalActionView.swift` | Final selected-action overview, direct Start execution, progress, and result UI |
| `Pruney/ActionExecution.swift` | Sequential execution state, progress, foreground waiting, and issue reporting |
| `Pruney/PhotoActionProcessor.swift` | Local photo/video encoding and confirmed PhotoKit deletion/replacement transactions |
| `Pruney/ReviewActionSettingsView.swift` | Three-column resize grid, local thumbnails, selection and compression controls, and navigation to final review |
| `PruneyTests/PruneyTests.swift` | Classification, byte totals, partial results, and empty-library unit tests |
| `PruneyTests/LibraryMeasurementCacheTests.swift` | Cache persistence, invalidation, partial results, scope pruning, and recovery units |
| `PruneyUITests/PruneyUITests.swift` | Permission grant/denial, overview, and onboarding persistence UI tests |
| `PruneyTests/ReleaseReadinessTests.swift` | Filter boundaries, action settings, quotas, execution refusal, and format-policy units |
| `PruneyTests/PhotoPreparationIntegrationTests.swift` | Opt-in generated-media preparation, validation, and cleanup checks |
| `PruneyTests/StoreKitReadinessTests.swift` | Opt-in local purchase, pending approval, refund, and product retry checks |
| `PruneyUITests/ReleaseReadinessUITests.swift` | Opt-in disposable-library review, quota, playback, and mutation scenarios |
| `docs/release-readiness-2026-10-06.md` | Release QA evidence, findings, blockers, and reproduction instructions |
| `Pruney/PrivacyInfo.xcprivacy` | Required-reason UserDefaults declaration for app-local onboarding preferences |
| `Pruney.xcodeproj` | Xcode project, scheme, build settings, and Photos usage description |
| `AGENTS.md` | Instructions for agents working in this repository |
| `scripts/import-simulator-media.py` | Import local photo/video folders into an iOS Simulator Photos library |
| `scripts/create-qa-media.swift` | Generate disposable PNG, GIF, JPEG, and HEIC fixtures for release QA |

## Build and run

The project was developed with Xcode 26.6. The app deployment target is iOS 17; the current test targets/settings require iOS 26.5. Swift language mode is 5, with MainActor default isolation and modern concurrency features, so use a toolchain compatible with the project settings.

Open `Pruney.xcodeproj`, select the **Pruney** scheme, choose an iPhone simulator or a configured device, and run. Device builds require an appropriate signing team.

Build for the simulator:

```sh
xcodebuild -project Pruney.xcodeproj -scheme Pruney \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/pruney-derived-data build
```

## Import simulator media

Use macOS with Xcode and Python 3. From the repository root, import files into the only booted iOS simulator:

```sh
./scripts/import-simulator-media.py "/path/to/media folder"
```

Select a simulator by UUID or exact name, and optionally include subfolders:

```sh
xcrun simctl list devices available
./scripts/import-simulator-media.py "/path/to/media folder" --device "SIMULATOR_UUID" --recursive
```

An explicitly selected simulator is booted if needed. If multiple simulators are booted or a name matches multiple runtimes, use a UUID. Preview the file list and command without changing the simulator:

```sh
./scripts/import-simulator-media.py "/path/to/media folder" --device "SIMULATOR_UUID" --dry-run
```

The script includes common photo, RAW, and video extensions, ignores other files, handles spaces and uppercase extensions, and leaves source files unchanged. Simulator support depends on the file format and runtime; Pruney may filter out imported unsupported formats. All media is passed to one `simctl addmedia` call so paired Live Photo still/motion files can be discovered together. Both original paired files, including their pairing metadata, must be present. Repeated imports can create duplicates. Failed imports may be partial; inspect Photos before retrying. Very large path lists must be split into smaller folders, keeping Live Photo pairs together.

The script has been syntax-checked only; no actual import or tests have been run.

## Tests

Run tests only when explicitly requested. List available simulators and use a compatible simulator ID:

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

## App Store presentation

The `appstore/` folder contains five promotional screenshots and a metadata text file for each of the ten supported languages. Screenshots use the 6.5-inch 1242 × 2688 format, localized titles, a phone frame, and actual app screens with read-only demonstration states. See [appstore/README.md](appstore/README.md) for language mappings, source artwork, and regeneration commands.

Debug builds recognize `-appStoreScreenshot overview|swipe|filters|resize|final` for asset capture. This presentation disables interaction, uses representative library totals and selections, and never executes changes. It requires demonstration media in a dedicated simulator for previews. The fixture and launch argument are excluded from Release builds; regular launches retain the normal onboarding and Photos access flow.

## Release readiness audit

The user explicitly authorized release testing on 2026-10-06. See [the audit report](docs/release-readiness-2026-10-06.md) for current results, confirmed findings, reproduction instructions and unverified states; earlier feature-specific validation notes above describe their historical checks.

Added pure release-readiness unit coverage, opt-in real-media preparation tests, opt-in StoreKit lifecycle tests, and an opt-in UI suite that includes recoverable mutations on a dedicated disposable simulator. `scripts/create-qa-media.swift` generates reproducible synthetic image fixtures. The baseline tests, expanded pure units, real image/video preparation and focused UI scenarios passed as detailed in the report. Local StoreKit lifecycle checks are blocked by a simulator test-session setup error. Simulator and unsigned device Release builds succeeded. The audit identifies a missing required-reason privacy manifest and clipping at maximum accessibility text size; no product fixes were applied during the audit.

## Privacy manifest

`Pruney/PrivacyInfo.xcprivacy` declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`: reading and writing information accessible only to Pruney itself. This covers the app-local onboarding completion preference used by `@AppStorage` and its Debug reset. The manifest is included as an app resource through the synchronized source folder, without additional project references. It declares required-reason API use; it does not replace the App Store Connect privacy questionnaire or the Photos permission explanation.

The high-priority manifest finding from the release audit was resolved in a follow-up authorized by the user. The plist was linted, Debug simulator and unsigned device Release builds succeeded, and the manifest contents were verified in the root of both built app bundles. Unit and UI tests were not rerun for this resource-only fix. Signed archive validation and App Store Connect upload remain unverified.

## Supported orientations

The app supports iPhone and iPad. iPhone uses portrait orientation. iPad declares portrait, upside-down portrait, landscape left, and landscape right in both Debug and Release so its orientation declarations meet the iPad multitasking requirement. The existing native launch storyboard remains in use.

The previous iPad portrait-only declaration caused an App Store Connect invalid-bundle error. The declaration was corrected without disabling multitasking or removing iPad support. See the release audit follow-up for bundle verification; iPad landscape and multitasking layouts still require visual verification.
