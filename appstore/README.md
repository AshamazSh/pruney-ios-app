# App Store assets

Each language folder contains five upload-ready, opaque RGB PNGs at **1242 × 2688** for the **6.5-inch iPhone** slot, plus `metadata.txt` with Name, Subtitle, Promotional Text, Description, and Keywords. Upload the numbered images in order:

1. Library overview and accessible file-size breakdown.
2. Swipe review with keep, delete, and resize actions.
3. Filters with alternative condition tiles.
4. Per-item resize settings, including deselection and video examples.
5. Final action overview before execution.

| Folder | App Store language |
| --- | --- |
| `en` | English (U.S.) |
| `es` | Spanish (Spain) |
| `pt-BR` | Portuguese (Brazil) |
| `de` | German |
| `fr` | French |
| `it` | Italian |
| `ru` | Russian |
| `ja` | Japanese |
| `ko` | Korean |
| `zh-Hans` | Simplified Chinese |

`english-preview.png` shows all five English images. `all-languages-preview.png` shows the first image for every language. These contact sheets are previews, not upload assets. `manifest.json` records the screenshot dimensions and order.

## Content and presentation

The phone displays actual localized SwiftUI screens from a Debug build. Dedicated, read-only screenshot fixtures provide representative library totals, review decisions, filters, and action selections. These are illustrative examples, not measured storage savings. No deletion or conversion is performed. The fixture is excluded from Release builds and disables interaction. Normal launches use the regular app flow.

`source-screens/` retains the original unframed simulator captures. `source-media/` contains three AI-generated demonstration photos and a short silent video derived from the coast photo; no personal photo library is used. The video is a static demonstration clip, not a feature of Pruney. `tools/create-demo-video.swift` can recreate the three-second silent H.264 clip from the coast PNG using macOS AVFoundation; its arguments are the source PNG path and a new output MOV path.

The metadata describes the implemented per-session allowance (50 deletions and 10 resize/static conversions) and optional one-time lifetime Pro purchase. Prices are deliberately omitted. Photo resize percentages refer to dimensions, not guaranteed file size reduction.

## Reproduce

Use a dedicated **iPhone 11 Pro Max** simulator running iOS 17.5, or another simulator producing native 1242 × 2688 captures. Build and install the Debug app using the repository README commands. Import the demonstration media into that simulator, duplicating the three PNGs to names `00.png` through `11.png` and the MOV to `video-0.mov` through `video-2.mov`; the fixture selects these filenames. Do not import into a personal library. Grant Photos access and set light appearance before capturing.

```sh
xcrun simctl status_bar <SIMULATOR_UUID> override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
python3 appstore/tools/capture.py --device <SIMULATOR_UUID>
```

The capture script requires an explicit device UUID, launches the five read-only Debug fixtures in each language, and writes the raw PNGs. Optional `--language en` captures one language. If a Photos permission prompt appears on first launch, allow access to the dedicated demonstration library before running the capture script again.

`tools/content.json` is the source for localized promotional copy and metadata. `tools/render.mjs` composites the captures into the phone artwork and validates metadata character limits and the **100-byte UTF-8 keyword limit**. It needs Node.js and Sharp; it does not install packages or run tests. Set `SHARP_MODULE` to an existing Sharp module directory if it is not resolvable normally:

```sh
SHARP_MODULE=/path/to/node_modules/sharp node appstore/tools/render.mjs
```

Apple references: [screenshot dimensions](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/), [metadata limits](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/), and [product-page guidance](https://developer.apple.com/app-store/product-page/).

## Validation

Both Debug and Release simulator builds succeeded. The generated artwork was inspected visually, and the renderer checked screenshot dimensions, metadata lengths, and keyword bytes. Tests were not run. The fixtures do not validate real destructive execution, encoding results, iCloud behavior, or store purchase behavior.

## Privacy policy

`privacy-policy.md` contains the English Privacy Policy for the implemented app, naming Ashamaz Shidov and the contact address provided by the developer. It covers on-device Photos processing, the local measurement cache, local preferences and temporary files, user-initiated sharing, Apple purchases and diagnostics, support correspondence, and user choices. Publish it at a publicly accessible URL for App Store Connect. The policy is not yet linked inside the app, and creating this document does not publish it or change App Store Connect privacy answers. Review and update the support-handling commitments if operational practices change. No translations were created.

## App Review notes

`review-notes.txt` contains English text for App Store Connect's Review Notes field. It covers permission setup, local test-media requirements, swipe and execution steps, per-run free limits, the non-consumable lifetime product ID, restoration, and the developer's review contact. The text was prepared from the current implementation; creating it does not submit or publish the notes.
