# Agent instructions

These instructions apply to the repository. Read `README.md` for the implemented behavior and the distinction between current features and planned work.

## Product scope

- Pruney helps users free photo and video storage. Its interface defaults to English, including onboarding, permission explanations, accessibility labels, and the Photos usage description.
- Write all new project text in English, including interface copy, accessibility labels, permission descriptions, documentation, and code comments. Create or update translations only when the user gives a separate, explicit instruction to translate; do not automatically add translations while implementing a feature.
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
