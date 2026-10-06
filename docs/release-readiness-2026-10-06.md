# Release readiness audit — 2026-10-06

## Decision

Do not treat this audit as release approval. The simulator checks substantially improve coverage, but the unverified purchase lifecycle still needs attention before submission. The missing privacy manifest was resolved in the user-authorized follow-up below. During the original audit, product fixes were deferred and only tests and documentation changed; earlier video-card changes and the user's InfoPlist catalog edits were preserved.

## Confirmed findings

| Priority | Finding | Evidence and impact | Proposed next step, not implemented |
| --- | --- | --- | --- |
| P1 — resolved in follow-up | Missing required-reason privacy manifest at audit time | `ContentView` persists onboarding with `@AppStorage`; `PruneyApp` also references UserDefaults. No `PrivacyInfo.xcprivacy` exists in the repository or unsigned Release app bundle. This use needs a declared approved reason. App Store upload validation was not attempted, so an actual rejection has not been observed. | Added `Pruney/PrivacyInfo.xcprivacy` with UserDefaults reason `CA92.1`; verified Debug and Release bundle inclusion. Signed archive/upload validation remains outstanding. |
| P2 | Review information clips at accessibility text sizes | iPhone SE (3rd generation), iOS 17.5, maximum accessibility text size: counter numerals clip, and the date and file size truncate. Review action buttons remain visible. Reproduces in dark appearance with two accessible items. | Adapt the counter and metadata layout to large text; recheck small screens. |

Apple requires apps that use required-reason APIs to describe those uses in a privacy manifest: [Apple documentation](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest).

Evidence screenshots remain outside the source tree:

- `/tmp/pruney-qa-small-accessibility.png`: clipped counters and metadata.
- `/tmp/pruney-qa-small-limited.png`: limited-access overview, one photo and one video.
- `/tmp/pruney-qa-small-dark-video.png`: normal-size dark video review.
- `/tmp/pruney-qa-small-empty-review.png`: no accessible items after editing limited access.

## Purchase verification blocker

Three opt-in StoreKit integration tests were added for purchase/restore/refund, Ask to Buy approval, and product-load failure/retry. They could not run through the purchase lifecycle: the local StoreKitTest session fails with `SKInternalErrorDomain Code=3` while configuring/resetting the simulated environment on Xcode 26.6 / iOS 26.5. This is a test-environment failure, not evidence of a Pruney purchase defect. No real purchase was attempted. Tests require a distinctive simulated product display name before attempting a purchase.

An [Apple Developer Forums thread with DTS responses](https://developer.apple.com/forums/thread/826971) reports a related CLI StoreKitTest problem. Its discussion is contextual evidence, not proof that every failure here has the same cause or that a workaround works. Verify purchase, restoration, cancellation, pending approval, revocation, and transaction updates using a working StoreKit environment and a real-device Sandbox/TestFlight build before release.

## Environment and isolation

- Xcode 26.6; app deployment target remains iOS 17; test target remains iOS 26.5.
- Dedicated `Pruney Release QA` simulator: iPhone 17 Pro / iOS 26.5. Seeded with generated 1200 × 900 PNG, two-frame GIF, JPEG, HEIC, 54 JPEG copies, three short local videos, and simulator sample media (68 assets before mutation checks).
- Dedicated `Pruney QA Small iOS 17` simulator: iPhone SE (3rd generation) / iOS 17.5. Five imported fixtures and default samples; two items selected through limited authorization.
- Mutations were limited to the dedicated QA library. Files were not permanently purged from Recently Deleted. The user's working simulator library was not used for destructive checks.
- Debug simulator build-for-testing and unsigned physical-device Release build succeeded. Signing, Organizer archive validation, App Store Connect upload, and TestFlight installation were not verified.

## Automated results

| Coverage | Result | Result bundle |
| --- | --- | --- |
| Final complete release UI suite | All eight passed in one run, zero failures | `/tmp/pruney-qa-ui-complete.xcresult` |
| Existing three unit tests and two permission/onboarding UI tests | Passed | `/tmp/pruney-qa-baseline.xcresult` |
| Existing units plus 12 new unit-test methods, including parameterized cases | Passed | `/tmp/pruney-qa-unit.xcresult` |
| Real JPEG, alpha PNG, animated GIF, HEIC and video preparation | Passed initially; four photo inputs plus one video input | `/tmp/pruney-qa-photo.xcresult` |
| Bulk quota cancellation, filter tile validation/OR display, 50-delete boundary, 10-resize boundary with undo capacity recovery, deletion cancellation and successful return | Five passed | `/tmp/pruney-qa-ui-settled.xcresult` |
| Sort/undo/hold-reset/Keep-all completion and a committed photo replacement with Recently Deleted notice | Two passed | `/tmp/pruney-qa-ui-final-v2.xcresult` |
| Video playback, mute, seeking, drag, queue advancement and stable next-video panel | Passed; its combined run initially lacked a previously deleted HEIC fixture | `/tmp/pruney-qa-media-video.xcresult` |
| Final pure-unit and real-media preparation run after reseeding | 17 test methods passed (including parameterized cases); three opt-in StoreKit methods skipped | `/tmp/pruney-qa-units-media-final.xcresult` |
| StoreKit lifecycle | Blocked by local session setup failure | `/tmp/pruney-qa-integration.xcresult` |

These are results across focused runs, not a claim that every intermediate run was green. Initial new UI runs exposed test-harness assumptions: SwiftUI container identifiers replace child identifiers, button taps return before the decision animation completes, and hidden video preview controls also appear in XCTest queries. Tests now wait for queue changes and locate enabled controls by their English accessibility labels. These changes do not alter product code. A size-slider/date fixture selection also produced no matching items; the mutation smoke test now selects one ordinary photo using the type filter.

All eight added UI scenarios also passed together in the final complete UI run (283.6 seconds), alongside the separately passed two existing permission UI tests. A later preparation rerun found `QA-photo.heic` missing after the destructive smoke checks; that is fixture exhaustion, not an encoding failure. After reseeding, all preparation and pure unit methods passed in the final run. Reseed before rerunning preparation tests. The strengthened video integration check verifies smaller readable dimensions, duration, a decoded frame, cleanup, and preservation of the original.

## What was checked

Unit checks cover mutually exclusive media categories; AND conditions; inclusive calendar days; strict decimal-byte limits; rejection of partial size measurements; action settings, deselection and Apply all ignoring Live Photos; independent per-run quotas; refusal of over-limit execution before mutation; empty execution; and image eligibility matching device encoders rather than a JPEG-only allowlist.

Real image preparation checks verify format, 600 × 450 output dimensions, a decodable frame, PNG alpha, two GIF frames with 0.15-second timing, temporary-file cleanup, and preservation of originals before committing. They do not prove every pixel's alpha, every metadata field, or HDR preservation. The video fixture is about 3 MB and three seconds, not a large-video stress test.

UI checks exercise onboarding permission timing, full access and denial, onboarding persistence, filters as a sheet, OR tiles, deletion and resize limits, bulk rejection without partial selection, Pro cancellation, undo, sorting, long-press reset, read-only completion, Photos deletion cancellation/retry, deletion return, one-photo replacement, success and Recently Deleted presentation.

Manual iOS 17.5 checks confirm onboarding, limited-access explanation and subset totals, review presentation, photo-to-video transition, playback, small-screen normal text and dark appearance. Editing the limited selection from two items to zero in Settings and returning to Pruney refreshed the totals to zero and displayed the empty-library explanation. Starting review then displayed an empty state with mutation controls disabled. The maximum-text defect is recorded above. Frame-by-frame transition animation quality and VoiceOver focus were not comprehensively evaluated.

## Remaining release verification

- Real-device purchase and restoration, storefront metadata, entitlement revocation, offline behavior and transaction verification.
- Real Live Photo Make static, HDR gain maps, RAW exclusion, APNG timing, multipage images and the less common device-supported image encoders.
- A mixed deletion/replacement batch, several replacements in one transaction, system cancellation of the shared replacement batch, and partial failures after a successful deletion batch.
- Limited-access mutation, restricted authorization, cloud-only media, changes to access while reviewing and background/interruption during execution.
- Disk exhaustion, long/large videos (including approximately 400 MB), large libraries, memory pressure and thermal behavior.
- Full visual review of all ten languages, all accessibility sizes and VoiceOver. Previously observed Russian resize-title and compression-label truncation remains a localization-review item, not a freshly reproduced normal-text finding in this audit.
- iPad layout: the app targets both iPhone and iPad. Existing 6.5-inch iPhone marketing images do not constitute iPad verification.

## Reproduce the added tests

Do not run the mutation suite on a personal or working library. Create a dedicated disposable simulator and use its ID. Tests remain opt-in except the pure unit coverage.

Generate images into a new empty folder:

```sh
swift scripts/create-qa-media.swift /tmp/pruney-qa-fixtures
```

Add three short local videos named `QA-video-0.mov` through `QA-video-2.mov`. The audit used copies of `appstore/source-media/coast.mov`. Import the fixtures using `scripts/import-simulator-media.py` following its documented usage. Keep more than 50 supported assets for quota checks. Reimport any fixtures removed by mutation checks before subsequent preparation runs.

Build using the README commands and run the baseline unit tests normally. For opt-in suites, make a copy of the generated `.xctestrun` in the same Build/Products directory so `__TESTROOT__` stays valid. In each `TestConfigurations[].TestTargets[]` dictionary, set the corresponding `EnvironmentVariables` entry:

| Target / suite | Variable | Effect |
| --- | --- | --- |
| PruneyTests / PhotoPreparationIntegrationTests | `PRUNEY_PHOTO_INTEGRATION=1` | Reads generated fixtures and prepares/discards outputs; does not commit replacements. |
| PruneyTests / StoreKitReadinessTests | `PRUNEY_STOREKIT_INTEGRATION=1` | Attempts local StoreKit test sessions only. |
| PruneyUITests / ReleaseReadinessUITests | `PRUNEY_RELEASE_UI_INTEGRATION=1` | Resets app Photos authorization/onboarding and includes recoverable deletion/replacement on the disposable library. |

Then use `xcodebuild test-without-building -xctestrun <copy> -destination 'platform=iOS Simulator,id=<QA_ID>' -parallel-testing-enabled NO -resultBundlePath <new-outside-repo-path> -only-testing:<target>/<suite>`. Do not append a second `test` action. Every result bundle path must be new. Photos authorization may require interaction with the dedicated simulator when running integration tests for the first time. Keep screenshots and result bundles outside the repository.

## Authorized follow-up: privacy manifest

The user requested the high-priority fix after reviewing the audit. Added `Pruney/PrivacyInfo.xcprivacy` with `NSPrivacyAccessedAPICategoryUserDefaults` and reason `CA92.1` for app-local onboarding state. No app-group, MDM, disk-space, or unrelated API reasons were added. The manifest is picked up by the synchronized app folder; project settings and existing user edits were preserved.

Validation: `plutil -lint` passed; Debug simulator and unsigned physical-device Release builds succeeded. Both built app bundles contain a root-level manifest with exactly the declared category and reason. Unit/UI tests were not rerun because the change adds only a resource and documentation. Build logs: `/tmp/pruney-privacy-debug.log` and `/tmp/pruney-privacy-release.log`. This closes the missing-manifest finding in source and built bundles, without claiming an App Store submission has been validated.

## Upload-error follow-up: iPad orientations

The user reported an App Store Connect invalid-bundle error: iPad was enabled but its supported orientation array contained only portrait and upside-down portrait. Updated `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad` in both Debug and Release to include landscape left and landscape right, retaining iPhone portrait and iPad support. This matches [Apple's iPad multitasking orientation requirement](https://developer.apple.com/library/archive/documentation/WindowsViews/Conceptual/AdoptingMultitaskingOniPad/QuickStartForSlideOverAndSplitView.html).

Validation: Debug simulator build and unsigned Release archive succeeded. Parsed the actual Info.plist in both products and verified all four values under `UISupportedInterfaceOrientations~ipad`, portrait under the base iPhone key, both device families, and inclusion of the privacy manifest. Archive: `/tmp/pruney-orientations-20261006.xcarchive`; logs: `/tmp/pruney-orientations-debug.log` and `/tmp/pruney-orientations-release.log`. Unit/UI tests were not rerun for this configuration change. iPad landscape and multitasking presentation remain visually unverified. A new signed archive must be created for uploading; the previously created archive retains its old plist. No subsequent App Store Connect validation result has been observed.
