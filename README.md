# PhotoP

An iPhone-first professional camera platform, with native Android planned after the photo pipeline is validated.

**Status: initial implementation; iPhone validation is still required.** The first slice contains an AVFoundation preview, physical-camera selection, HEIF/JPEG capture, original-byte preservation, add-only Photos export, a thirds grid, basic manual ISO/shutter/EV/focus/WB controls, touch AF/AE, independent AE/AF/WB locks, and live device readouts. A strict 3D `.cube` parser, CPU reference interpolation and Metal renderer support an SDR/sRGB editor for the last photo. User LUT import requires an explicit sRGB input/output declaration; originals remain unchanged. An SDR live LUT preview and persistent user LUT favorites are also implemented. Basic monochrome grain and saved-edit reopening are implemented. Phase 2 development scope is complete within the SDR limits below; device acceptance is pending. Phase 3 adds dynamically gated Bayer RAW/Apple ProRAW DNG capture, SDR RGB/luma histograms, zebra, focus peaking, and native three-frame exposure brackets. Long exposure, composition AI and video recording remain future work.

## Start here

- [Product requirements](docs/01-PRD.ko.md)
- [Technical design and module contracts](docs/02-TECHNICAL-DESIGN.ko.md)
- [Open-source due diligence](docs/03-OPEN-SOURCE-AUDIT.ko.md)
- [Phased roadmap and acceptance criteria](docs/04-ROADMAP.ko.md)
- [Build, tests and device checklist](docs/05-BUILD-AND-VALIDATION.ko.md)
- [LUT sources and asset policy](docs/06-LUT-CATALOG.ko.md)
- [Implementation report](docs/07-IMPLEMENTATION-REPORT.ko.md)
- [Step validation log](docs/08-STEP-VALIDATION.ko.md)
- [Phase 2 source review and implementation decisions](docs/09-PHASE2-SOURCE-REVIEW.ko.md)
- [Phase 3 design, source review and validation](docs/10-PHASE3-DESIGN-AND-VALIDATION.ko.md)

## Camera controls

Manual ISO/shutter, manual focus and manual WB wait for the device completion callbacks. Capture and lens changes are blocked while those changes are pending. Interruption and a bounded timeout cancel pending work; late callbacks from an older operation cannot complete a newer one.

The camera screen and PRO sheet show current device ISO, exposure duration, EV bias, normalized lens position and WB estimates at up to 4 Hz. These values are separate from editable requests and are not the saved photo's EXIF. Automatic AE/AF/AWB can continue adjusting after a configuration callback.

Processed captures use Apple's speed prioritization in custom/locked exposure mode to honor manual ISO/duration. Automatic exposure retains quality prioritization. This prioritization choice does not change JPEG compression or the requested dimensions; its computational image-quality tradeoff still needs device evaluation.

## Build on a Mac

Install Xcode with the iOS SDK and XcodeGen, then:

```sh
cd ios
xcodegen generate
open PhotoP.xcodeproj
```

Select a unique bundle ID and your signing team in Xcode; choose a physical iPhone running iOS 17 or later. The Simulator can run model tests but cannot validate the camera. No Apple account secrets belong in this repository.

The baseline is iOS 17, built in Swift 5 language mode with complete concurrency diagnostics. A serial queue owns AVFoundation state. Strict Swift 6 migration is a later, separately validated change.

Original HEIF/JPEG bytes are retained in the app's Documents/Originals directory before Photos export. Deleting the app also deletes those app-local originals. A successful Photos export creates a separate Photos asset.

All 14 requested modes remain the product roadmap; the initial app exposes photo capture only. Frame duration, RAW/ProRAW, Log and maximum resolution depend on the device and active capture configuration.

Third-party project and LUT rights are tracked separately. No third-party source code, LUT binaries, model weights or commercial UI assets are bundled in this initial implementation.


## SDR LUT photo editor

After capture, choose **LUT 사진 편집**. Confirm that your LUT expects and outputs sRGB, import a UTF-8 3D `.cube`, adjust strength and compare with the SDR original. The camera session pauses while this editor is open. Preview is limited to 1024px; full-resolution derivative export currently supports up to 12.6MP and explicitly rejects larger photos.

The processing order is oriented SDR base decode → embedded ICC to sRGB → encoded-sRGB trilinear LUT → strength mix → basic monochrome grain → SDR clamp → sRGB JPEG. HDR gain maps and original EXIF are omitted from the derivative. This is not a RAW/Log/HDR developer. The original retains its bytes and metadata.

Each export creates `Documents/Edits/<id>/photo.jpg`, `look.cube` and `recipe.json`, including source and LUT SHA-256 hashes. ShareLink shares the JPEG; the LUT and recipe stay app-local. Imported LUTs are user documents and are not added to the distributable app bundle. Choose **편집 기록** from the camera screen to reopen an earlier edit after restarting the app. The app checks recipe version/profile, original/LUT hashes, bounded files and local paths before restoring the LUT, strength and grain seed. Version 1 recipes load with grain disabled; unsupported or changed inputs are rejected. Re-export creates a new bundle. Full gallery browsing remains future work.


## Basic grain

Grain has an independent 0–100% amount and deterministic seed, stored in version 2 recipes. Set LUT strength to zero to apply grain alone after importing a LUT. Still and live paths share the same Metal function. Noise coordinates use a 512-cell long edge to preserve the field across resizing; different resolution sampling and JPEG encoding can change individual pixels. This is a basic creative effect, not a measured film-stock simulation. Same-input buffer/texture agreement is tested within 1/255 per channel.

## Live LUT preview and favorites

Open **LUT** on the camera screen, confirm sRGB input/output and import a `.cube`, or load a saved favorite. The LUT applies to the preview only; capture continues saving the original HEIF/JPEG. Strength, basic monochrome grain and original-color comparison are available. Turn LUT off before switching lenses, touch AF/AE or importing another LUT; manual PRO controls remain available.

The native 8-bit NV12 stream accepts BT.709 primaries, 709/sRGB transfer and 601/709 matrix metadata. Core Video derives the video matching profile; Core Image converts it to encoded sRGB on the GPU before the shared Metal LUT and aspect-fit display pass. Unknown/HDR/Log profiles disable the LUT with an explanation. Camera device color/HDR settings are not forcibly changed. Front portrait rotation/mirroring is requested through the supported connection APIs.

One frame is allowed in flight; late frames are dropped. Two intermediate textures are reused at up to 1024px on the long edge. The capture buffer stays alive through GPU completion. This live path performs no CPU pixel readback or GPU completion wait. Actual camera delivery, screen color match, FPS and thermal performance still require device measurements.

Favorites are saved only when requested, under Application Support/UserLUTFavorites with SHA-256 IDs, original `.cube` bytes and sRGB profile metadata. Both the editor and live preview can load them after restarting the app. Changed file hashes or unsupported metadata are rejected. Removing a favorite does not delete the original imported source or existing photo edit bundles. Favorites are user documents and never become distributable bundle assets.

Development proceeds after each automated test stage passes; outstanding iPhone validation is tracked separately and does not block the next implementation stage.


## RAW and advanced shooting (Phase 3)

Select **Bayer RAW** or **Apple ProRAW** only when offered by the current lens/output. The app configures ProRAW where supported and requests a DNG without a processed substitute. RAW flags, DNG directory metadata and original bytes are checked; RAW development is not part of the SDR editor. ProRAW currently requires AUTO exposure; Bayer RAW permits manual exposure. Turn live LUT/monitoring off before RAW capture. These are declared initial execution restrictions, with hardware combination testing still pending.

Open **보조** for RGB/luma histograms, zebra and focus peaking. Enable one or more tools and choose **모니터 켜기**, or apply them to the active LUT preview. Analysis uses the encoded SDR input before the creative LUT. Histograms use 64 bins and at most a 256px sample grid, updated at up to 4 Hz. Zebra checks the brightest SDR channel; peaking marks Sobel contrast edges. They do not measure RAW sensor clipping or guarantee focus. The histogram reads back only 1 KiB of counts after GPU completion. Overlays are never saved into the capture original.

Under **PRO → 노출 브라케팅**, enable three-frame bracketing and select ±0.5/1/2 EV. Supported AUTO/processed/livestream-off configurations capture three separate originals around the device's current EV, within actual device limits. A manifest stores filenames, SHA-256 hashes and requested EV values; frame EXIF remains in each original. All originals can be shared or added to Photos together. RAW brackets and HDR fusion remain future work.

Automated validation: unsigned iPhone SDK build, 90 Swift tests and 7 Python tests passed. Real capture, EXIF agreement, RAW-developer compatibility, display color, FPS, memory and thermal acceptance remain unverified. The repository contains no bundled third-party LUTs or models.
