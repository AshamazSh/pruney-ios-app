# Agent instructions

These instructions apply to the repository. Read `README.md` for the implemented behavior and the distinction between current features and planned work.

## Product scope

- Pruney helps users free photo and video storage. English is the source and fallback language. The interface follows the device's supported language preference, with English, Spanish, Brazilian Portuguese, German, French, Japanese, Korean, Simplified Chinese, Italian, and Russian localizations in Localizable.xcstrings and InfoPlist.xcstrings, including onboarding, permission explanations, accessibility labels, and the Photos usage description.
- Write all new project text in English, including interface copy, accessibility labels, permission descriptions, documentation, and code comments. Create or update translations only when the user gives a separate, explicit instruction to translate; do not automatically add translations while implementing a feature.
- Use String(localized:) for UI-facing String values created outside SwiftUI literal lookup, including model labels, interpolated descriptions, errors, and UIKit accessibility actions. Keep format placeholder types consistent in the catalogs. Keep accessibility identifiers independent of translated text. Purchase metadata and prices come from StoreKit; do not replace them with app-catalog translations or hardcoded prices.
- Implement the requested feature incrementally. Do not treat proposed review or compression behavior as finalized requirements.
- Keep documentation aligned with the code. Label planned features clearly and record material behavior changes in `README.md`.

## Implementation conventions

- Use SwiftUI for the interface, Observation for observable state, and public PhotoKit APIs for library access.
- Keep Photos authorization and scan orchestration in `LibraryAnalysis`, resource reading in `LibraryScanner`, and presentation in SwiftUI views. Extract components when complexity warrants it.
- Keep UI-facing state on MainActor. Respect the project's default actor isolation and explicitly isolate background work and shared value types where necessary.
- Preserve cancellation and generation checks so an obsolete scan cannot replace current results. Keep streamed byte accumulation thread-safe.
- Read resources in bounded chunks without retaining whole videos. Do not use private properties or KVC to obtain resource sizes.
- Preserve the current policy of disabling network access during analysis unless the requested feature explicitly changes it.

## Behavior to preserve

- Request Photos access after the user taps Continue, not automatically on launch.
- Full and limited access are both valid analysis states. Limited access must be clearly described as a subset of the library.
- Distinguish not-yet-requested, denied, and restricted access, and provide the appropriate recovery action.
- Treat overview categories as mutually exclusive: Photos excludes Live Photos, and Videos contains only standalone videos.
- Count a Live Photo's readable photo and motion resources under Live Photos.
- Do not present measured file sizes as exact device storage usage or guaranteed reclaimable space. Keep partial measurement visible.
- Maintain empty-library handling, progress reporting, foreground authorization refresh, library-change observation, and scan cancellation on backgrounding.
- Persist onboarding completion. Keep `-resetOnboarding` restricted to Debug builds.
- The current analysis flow must not delete, compress, or otherwise modify assets. Add mutation behavior only within an explicitly requested feature, with its user-facing behavior defined.
- Keep analysis, swipe decisions, and resize settings read-only. After all items are reviewed, a deletion-only session applies one batch when the user taps Delete X, relying on Photos' system confirmation, then returns to the library. Sessions with resize candidates go through Resize settings and Continue to the final overview where Start immediately begins execution without an additional in-app confirmation; retain Photos system confirmations. There is no Delete settings screen. Delete selected candidates first; a failed deletion batch must stop compression.
- Show the Recently Deleted notice on the main library screen after returning from either flow when assets were actually removed, including resize originals. Explain that files remain there for up to 30 days and users must empty the folder themselves to free space immediately. Do not repeat that notice on the final overview or result screen.
- Build swipe queues using the shared SupportedMediaFormats policy before showing cards. Exclude unsupported image/video types and RAW-containing assets from all review actions, progress totals, and undo history. Show exclusions separately from user Keep decisions. Keep library overview totals inclusive of all accessible assets. Metadata eligibility is not a guarantee that later encoding will succeed.
- User filters combine enabled conditions within a tile using AND and tiles using OR. Photos excludes Live Photos. Date bounds include the selected calendar day; size bounds are strict decimal-byte comparisons. Never download cloud resources for size filtering, and do not treat partial measurements as full sizes. Preserve filtered queue scope through undo/reset and use the existing confirmed action flow.
- Resizing replaces originals with smaller outputs. Photo levels retain 90/80/70/50% of the dimensions. Preserve any non-RAW image format that Image I/O can encode on the current device; do not maintain a JPEG/HEIC/PNG-only allowlist. Lossy formats use quality 95 where supported. Preserve source frames, animation properties, orientation, and transparency. Request HDR gain map preservation and validate that existing gain maps remain. Skip RAW/ProRAW and unsupported formats without falling back to JPEG. Validate the output format, frame count, reduced dimensions, transparency, and GIF/APNG timing before replacing originals. Video levels use compatible smaller standard export resolutions. Live Photos support only Make static: copy the current still resource without re-encoding, resizing, or compression levels, and import it without the motion resource. Apply all must ignore Live Photos; report static conversions separately from resizing. Validate the copied still format and readability before replacing the original. Preserve these agreed choices unless the user changes them.
- Prepare all validated replacements before changing the library: smaller outputs for resizing and unchanged still resources for Live Photo static conversion. Save every prepared replacement and delete their originals in one shared PhotoKit transaction, rather than one transaction per item, to reduce system confirmation prompts. Import closed, app-owned output files with PHAssetResourceCreationOptions.shouldMoveFile enabled to avoid intermediary copies. Keep outputs available until PhotoKit finishes, then clean up remaining temporary files and directories, tolerating files already moved. Count resize and static-conversion successes separately, only after the batch succeeds. Keep resize originals on encoding or batch failures; earlier successful deletion batches remain applied. Report partial completion accurately and do not automatically retry destructive actions.

- Free limits apply per execution run: up to 50 selected deletions and 10 selected resize/Make static replacements, independently. There is no cumulative or daily usage limit. Review selections reserve capacity for the current run; undo/reset release reservations. Check before advancing an individual card or selecting a bulk action. Cancel preserves the current card and choices; reject over-limit bulk actions completely. Keep is unlimited. Do not count replacement originals as additional deletions. Revalidate the selected plan before execution. New reviews get full capacity; do not persist or deduct completed usage.
- Pruney Pro is a non-consumable lifetime StoreKit purchase, not a subscription. Grant unlimited access only for verified, non-revoked transactions of the configured product. Keep Restore purchases, localized StoreKit prices, transaction observation, and explicit unavailable/pending/failure handling. Free limits use current session selections only; do not restore cumulative Keychain usage tracking.

## Project and validation

- Use `Pruney.xcodeproj` and the `Pruney` scheme. Source folders are synchronized with the Xcode project; avoid unnecessary manual file references.
- Preserve the app's iOS 17 deployment target. Test targets currently require iOS 26.5. Do not change deployment targets, signing, or bundle identifiers as a side effect of unrelated work.
- The generated Info.plist gets `NSPhotoLibraryUsageDescription` from the app build settings in both Debug and Release. Keep both configurations consistent.
- Do not run tests without an explicit instruction from the user to run them. This includes unit tests, UI tests, and commands or scripts that execute tests. A request to implement or fix a feature does not authorize test execution.
- Use the build commands in `README.md` for Swift changes. Use its test commands only when the user explicitly requests test execution, selecting an available compatible simulator rather than hardcoding a machine-specific ID. Documentation-only edits do not require an app build.
- When tests are explicitly requested, run the relevant tests for the change and report the results. Otherwise, report that tests were not run when summarizing validation.
- Preserve stable accessibility identifiers. If interface copy changes, update affected UI assertions; system permission button labels follow the device language.
- UI tests use normalized coordinates for permission buttons because regular element taps were unreliable in the development simulator. Review actual screenshots and failure attachments when diagnosing those tests.
- Test coverage is not complete: explicitly identify unverified states instead of claiming that limited access, iCloud, large libraries, or older OS versions have been tested.

## Working tree hygiene

- Inspect the existing working tree before editing and preserve unrelated user changes. In particular, do not repair or stage unrelated project moves as part of another task.
- Keep generated builds, result bundles, and screenshots outside the source tree unless a task specifically calls for versioned artifacts.
- Avoid introducing packages, changing project settings, or expanding the architecture without a concrete need in the requested work.
