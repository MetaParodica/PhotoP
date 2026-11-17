> **검증 기록:** 아래 [CI 39614392835](https://github.com/MetaParodica/PhotoP/actions/runs/39614392835)의 성공과 화면은 과거 기준 코드의 결과입니다. 현재 심도 변경의 SDK 결과·실기기 인수는 [최신 Phase 기록](docs/28-DEPTH-PHASE-IMPLEMENTATION.ko.md)을 확인하세요. [기본 화면](docs/screenshots/camera.jpg) · [구도 카드](docs/screenshots/guide.jpg) · [룩 카드](docs/screenshots/looks.jpg) · [인물 실루엣](docs/screenshots/person.jpg)

# PhotoP

2026-11-17 최적화 작업: [구현·회귀 보고서](docs/30-OPTIMIZATION-IMPLEMENTATION.ko.md). LUT 고정 형식 생성/바이너리 캐시, 깊이 통계/매트/입력 재사용, Flow 재시도 제한, 저장 UI 잠금과 실패 진단을 개선했다. 공통118·Python31 통과, 전체 SDK 회귀 진행 중이며 실기기 성능 인수는 별도다.

2026-11-17 main 통합 범위: 기존 심도·AF 개발분과 [최적화·고도화 개선 보고서](docs/29-OPTIMIZATION-AND-ADVANCEMENT-AUDIT.ko.md)를 함께 반영한다. portable110·Python28, 심도 집중 SDK 검사38개 통과/1개 skip 기록이 있으며 최신 전체 회귀는 시간 초과로 실패했다. 개선 보고서의 제안과 실기기·iOS27 인수는 후속 작업이다. 검증 상태는 [단계별 기록](docs/08-STEP-VALIDATION.ko.md)을 확인한다.

2026-11-16 후속 Phase 개발: [심도 Phase0~7 구현·반복 검증·남은 인수](docs/28-DEPTH-PHASE-IMPLEMENTATION.ko.md). 측정/AI 보정 융합, 선택 인스턴스 매트·경계색 복원, Natural/Portrait/Classic, 선택적 실시간 AI 심도와 안전 복귀, 최대64MP 사진 경로 및 저장 사진의 터치 재초점·보관함·취소/복구를 추가했다. 공통 로직109개/Python28개 통과와 실제 iOS SDK/실기기 검증을 구분한다. [화질 인수 도구](docs/depth-acceptance/README.ko.md)는 실제 평가 증거가 없는 현재 **인수 불가**를 반환한다. 아래 1차 구현의12.6MP/실시간 미구현 설명은 당시 기록이다.

2026-11-16 1차 구현: [외부 모델 확정·AF 제어·Natural 정지 사진 심도·검증/제약](docs/27-AF-NATURAL-DEPTH-IMPLEMENTATION.ko.md). Apache-2.0의 Apple Core ML Depth Anything V2 Small FP16을 고정 버전으로 포함하고, 센서 깊이/AI 대체·최대12.6MP 원형 보케·저장 깊이 f값 재처리, AF-C/AF-S·독립 AF/AE·AF-ON·MF 확대를 연결했다. iOS26 영역/27 추적·Auto ISO는 SDK 및 기기 지원 검사로 분리한다. 기존64MP LUT/센서 기본 심도는 유지한다. **실시간 심도·눈 AF·경쟁 품질·iOS SDK/실기기 인수 완료는 아니다.** Swift97/Python23은 Linux 핵심/자산 검증이며 iOS 테스트 성공과 다르다.

2026-11-16 개발 조사 보고서: [DSLR형 소프트웨어 심도 개발 계획](docs/24-SOFTWARE-DEPTH-DEVELOPMENT-PLAN.ko.md) · [AF·DSLR 추가 기능](docs/25-AF-DSLR-FEATURE-RESEARCH.ko.md) · [iOS 17~27 공식 API·지원 제약](docs/26-IOS17-27-CAPABILITY-RESEARCH.ko.md) · [공식 출처·조회 hash](docs/research/2026-11-16-official-camera-sources.json). 공식 웹 문서와 현재 main 소스를 대조한 **계획**이며, 새 심도/AF 기능 구현·iOS 27 SDK/실기기 검증 완료를 의미하지 않는다.

2026-10-23 최신 요청 반영: [뷰파인더 실시간 LUT·강도/입자/마감·원본 비교](docs/23-LIVE-VIEWFINDER-LOOK.ko.md). 룩 선택 시 실시간 프리뷰가 켜지며 저장 원본은 보존한다. 카드별 예시 미리보기는 계속 끈다. 아래 과거 기록의 “카메라 프리뷰 무보정/촬영 결과 전용” 설명보다 이 동작을 우선한다. iOS SDK/실기기 검증은 대기다.

2026-10-23 LUT 적용 점검·수정: [적용 누락 원인·즐겨찾기 v2·편집 복원·추가 개발 보고](docs/22-LUT-APPLICATION-AND-NEXT-STEPS.ko.md). 선택 사진에 대응하는 원본과 촬영 당시 룩을 편집기에 전달하고, 즐겨찾기에 강도·입자·공간 효과를 함께 저장한다. 원본/효과 결과/실패/강도0/작은 색상 변화/RAW·영상 미적용을 구분한다. 카메라 미리보기는 계속 무보정이다.

2026-10-23 고해상도·외부 LUT 변경안: [64MP 타일 LUT/심도 처리·사용 권한 확인 반영](docs/21-HIGH-RESOLUTION-LUT-DEPTH.ko.md). 24/48MP를 축소하지 않는 촬영 결과·편집기 내보내기를 연결했다. 외부25개는 프로젝트 소유자의 사용·상업 사용·재배포 가능 확인을 기록했다(독립 법률 검증이나 제조사 공식 인증 아님). 기술 LUT 1개는 색 출력 프로파일 미확인으로 원본 제공만 유지한다. 이번 iOS SDK/Metal·실기기 검증은 대기다.

2026-10-22 촬영 개선 변경안: [16개 요청 반영·제한·검증 및 추가 개선 보고](docs/17-CAMERA-FIELD-FIXES.ko.md). 위 CI 기록은 이전 코드의 결과이며 이번 변경의 iOS 빌드·실기기 검증은 아직 미수행입니다.

AI Composition 최신 변경안: [전체 Phase 코드 통합·검증·기기 인수 항목](docs/20-INTELLIGENT-CAMERA-ALL-PHASES.ko.md). 인물 추적에 7개 촬영 의도, 29개 구도 항목(자동 추천/수동 도식), 실제 영상·기울기 기반 줌/노출/각도 코치, 촬영 후 측정 리뷰·전후 비교·선택적 기기 내 선호 기록을 연결했습니다. 실제 존재하는 AUTO/PRO/RAW/LONG/VIDEO 촬영 경로를 통합했습니다. SDK 빌드·실카메라·성능 검증은 대기이며 임의 미학 점수·자동 사물 분류를 주장하지 않습니다. Swift 설치 환경에서 루트의 `swift test`로 같은 핵심 코드를 검사합니다. [Phase 1 당시 기록](docs/18-AI-COMPOSITION-PHASE1.ko.md).

최신 촬영 UI 변경안: [전체 화면 뷰파인더·LUT 결과 전용 적용·PRO f값 심도·장노출 시간 직접 입력](docs/19-FULLSCREEN-CAPTURE-WORKFLOW.ko.md). 현재 동작은 이 문서를 우선합니다. portable Swift 핵심 테스트 26개 통과, 이번 변경의 iOS 빌드·실기기 검증은 미수행입니다.

An iPhone-first professional camera platform, with native Android planned after the photo pipeline is validated.

**Status: initial implementation; iPhone validation is still required.** The first slice contains an AVFoundation preview, physical-camera selection, HEIF/JPEG capture, original-byte preservation, add-only Photos export, a thirds grid, basic manual ISO/shutter/EV/focus/WB controls, touch AF/AE, independent AE/AF/WB locks, and live device readouts. A strict standalone 1D/3D `.cube` parser, CPU reference interpolation and Metal renderer support an SDR/sRGB editor for the last photo. User LUT import requires an explicit sRGB input/output declaration; originals remain unchanged. An SDR live LUT preview and persistent user LUT favorites are also implemented. Basic monochrome grain and saved-edit reopening are implemented. Phase 2 development scope is complete within the SDR limits below; device acceptance is pending. Phase 3 adds dynamically gated Bayer RAW/Apple ProRAW DNG capture, SDR RGB/luma histograms, zebra, focus peaking, and native three-frame exposure brackets. Phases 4–6 add sampled SDR long exposure, on-device composition suggestions and an original film-style library. SDR video recording (optional audio, supported stabilization) is implemented; video LUT monitoring, Log/HDR and Android remain future work.

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

The camera screen’s contextual panels and control rail show current device ISO, exposure duration, EV bias, normalized lens position and WB estimates at up to 4 Hz. These values are separate from editable requests and are not the saved photo's EXIF. Automatic AE/AF/AWB can continue adjusting after a configuration callback.

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

All 14 requested modes remain the product roadmap; the app currently exposes still photos and sampled computational long exposure. Frame duration, RAW/ProRAW, Log and maximum resolution depend on the device and active capture configuration.

Third-party project, model and LUT rights are tracked separately. One unmodified Apache-2.0 Apple Core ML Depth Anything V2 Small FP16 package is now bundled with pinned revision, hashes, LICENSE and NOTICE; see `assets/depth-model/legal`. No third-party application source or commercial UI assets are copied. Five unmodified slay LUTs are included with CC BY 4.0 license, attribution and hashes. Their upstream color profile is unspecified; applying them requires confirming PhotoP’s sRGB SDR interpretation.


## SDR LUT photo editor

After capture, choose **LUT 사진 편집**. Confirm that your LUT expects and outputs sRGB, import a UTF-8 3D `.cube`, adjust strength and compare with the SDR original. The camera session pauses while this editor is open. Preview is limited to 1024px; export preserves source dimensions up to 64MP/16384px long edge, including 24/48MP photos. Temporary disk space is required; larger photos and RAW development are explicitly rejected.

The processing order is oriented SDR base decode → embedded ICC to sRGB → encoded-sRGB channel-linear 1D / trilinear 3D LUT → strength mix → basic monochrome grain → creative fade/vignette/bloom/halation → SDR clamp → sRGB JPEG. Full-resolution export uses halo tiles, global effect coordinates and disk-backed RGBA; the preview/in-memory renderer retains its separate safety limit. HDR gain maps and original EXIF are omitted from the derivative; available LUT attribution is written to the JPEG IPTC caption. This is not a RAW/Log/HDR developer. The original retains its bytes and metadata.

Each export creates `Documents/Edits/<id>/photo.jpg`, `look.cube` and `recipe.json`, including source and LUT SHA-256 hashes. ShareLink shares the JPEG; the LUT and recipe stay app-local. Imported LUTs are user documents and are not added to the distributable app bundle. Choose **편집 기록** from the camera screen to reopen an earlier edit after restarting the app. The app checks recipe version/profile, original/LUT hashes, bounded files and local paths before restoring the LUT, strength, grain seed and film finish. Version 1 recipes load with grain disabled; version 2 has neutral film finish; version 3 stores finish and optional provenance; unsupported or changed inputs are rejected. Re-export creates a new bundle. Full gallery browsing remains future work.


## Basic grain

Grain has an independent 0–100% amount and deterministic seed, stored in version 2 recipes. Set LUT strength to zero to apply grain alone after importing a LUT. Still and live paths share the same Metal function. Noise coordinates use a 512-cell long edge to preserve the field across resizing; different resolution sampling and JPEG encoding can change individual pixels. This is a basic creative effect, not a measured film-stock simulation. Same-input buffer/texture agreement is tested within 1/255 per channel.

## Capture-only LUT selection and favorites

Open **룩** on the camera screen, select a preinstalled look, import a confirmed-sRGB `.cube` or load a saved favorite. The viewfinder shows the selected LUT/strength/grain/finish live; scene-thumbnail/card previews remain disabled. Use **원본 프리뷰와 비교** for a neutral display without changing saved look settings. Capture creates a separate SDR JPEG (up to 64MP) while preserving original bytes. Photos export includes originals and successful derivatives. Stored RAW/video remain ungraded; their viewfinder may show the selected look if the device supports the analysis output. Long-exposure processing pauses live analysis and restores the look after completion. Failures preserve originals and report an error.

The camera explicitly negotiates an sRGB SDR BGRA stream for analysis and long exposure. RGB input does not require a YCbCr matrix; any declared BT.709 transfer is converted to sRGB. Tagged NV12 remains supported by the processor, but untagged YUV, HDR/Log and conflicting primaries are rejected. Previous device colour/HDR configuration is restored when leaving the photo analysis stream. Portrait and both landscape orientations use the supported rotation/mirroring APIs.

Monitoring/AI can still use the neutral Metal preview with one GPU frame in flight and late-frame dropping. Selecting a LUT never starts or replaces that analysis stream. Camera look cards do not request scene samples. Actual camera delivery, FPS and thermal performance still require device measurements.

Favorites are saved only when requested, under Application Support/UserLUTFavorites with SHA-256 IDs, original `.cube` bytes and sRGB profile metadata. Both the editor and capture-look selector can load them after restarting the app. Changed file hashes or unsupported metadata are rejected. Removing a favorite does not delete the original imported source or existing photo edit bundles. Favorites are user documents and never become distributable bundle assets.

Development proceeds after each automated test stage passes; outstanding iPhone validation is tracked separately and does not block the next implementation stage.


## RAW and advanced shooting (Phase 3)

Select **Bayer RAW** or **Apple ProRAW** only when offered by the current lens/output. The app configures ProRAW where supported and requests a DNG without a processed substitute. RAW flags, DNG directory metadata and original bytes are checked; RAW development is not part of the SDR editor. ProRAW currently requires AUTO exposure; Bayer RAW permits manual exposure. Turn monitoring/AI off before RAW capture. Selected capture looks are not applied to DNG. These are declared initial execution restrictions, with hardware combination testing still pending.

Open **보조** for RGB/luma histograms, zebra and focus peaking. Enable one or more tools on the neutral analysis preview. Analysis uses the ungraded encoded SDR input. Histograms use 64 bins and at most a 256px sample grid, updated at up to 4 Hz. Zebra checks the brightest SDR channel; peaking marks Sobel contrast edges. They do not measure RAW sensor clipping or guarantee focus. The histogram reads back only 1 KiB of counts after GPU completion. Overlays are never saved into the capture original.

Under **PRO → 노출 브라케팅**, enable three-frame bracketing and select ±0.5/1/2 EV. Supported AUTO/processed/livestream-off configurations capture three separate originals around the device's current EV, within actual device limits. A manifest stores filenames, SHA-256 hashes and requested EV values; frame EXIF remains in each original. All originals can be shared or added to Photos together. RAW brackets and HDR fusion remain future work.

Automated validation through the previous Phase 6 slice: unsigned iPhone SDK build, 120 Swift tests and 7 Python tests passed. Current expansion evidence is recorded in the report above. Real capture, EXIF agreement, RAW-developer compatibility, display color, FPS, memory and thermal acceptance remain unverified. That historical validation predates the newly bundled depth model and does not validate the current implementation.


## Sampled long exposure (Phase 4)

Choose **장노출**, average or whole-RGB luminance Lighten, 1–300 seconds and optional translation alignment. This samples processed SDR frames at up to 2fps and 1280px, with linear-light streaming accumulation and a 128MiB disk archive of lossless sampled PNGs. It is not a continuous 300-second sensor exposure; moving lights may have gaps. Optional ±8px integer translation rejects ambiguous frames; rotation/perspective and handheld guarantees are not provided. Progress, cancellation, JPEG sharing/Photos export and reprocessing of the latest archived stack are available. Early budget termination records actual duration and reason. Existing results remain unchanged when reprocessed. Cross-restart archive browsing and crash-orphan recovery are future work.

## Composition suggestions (Phase 5)

Open **구도** for advanced geometric grids and nine independently drawn pose targets. The **AI** control now connects on-device human/face detection, spatial tracking, subject selection, thirds targets and stabilized alignment feedback to the existing preview. Analysis is bounded to one 640px job at up to 5Hz (lower or suspended under power/thermal constraints); results expire after 650ms. Existing attention saliency, body joints, rectangle edges and horizon angle remain optional scene aids, not semantic object recognition. No perspective correction, pose-quality certification or server upload is provided. Real iPhone detection accuracy, coordinate alignment and performance remain unverified; see the Phase 1 report above.

## Original film styles and full-look presets (Phase 6)

The style browser offers **59 creative looks plus three technical LUT entries**: 24 original color styles, eight spatial presets and 27 external creative looks. Thirty external original files are bundled (five slay CC BY 4.0 LUTs plus 25 third-party derivatives/mirrors). On 2026-10-23 the project owner confirmed permission for app use, commercial use and redistribution of those 25 files; the manifest records user-confirmed permission, not an independent license audit or manufacturer endorsement. V-Log LUTs use a clearly labelled SDR approximation and a cached 65³ render cube. One unknown-output WDR entry is original-file-only for color-profile reasons, not a rights gate. Spatial presets use separate Metal soft focus, chromatic aberration and horizontal highlight spread rather than a color LUT. Use full-look presets to retain spatial settings. Brand/sensor/film measurements and 100+ quality-reviewed styles remain future work. See [external sources](docs/15-EXTERNAL-LOOKS.ko.md), [spatial effects](docs/16-SPATIAL-STYLES.ko.md) and `ios/PhotoP/Film/STYLE-PERMISSION.txt` for the narrow permission on our own profile data.

Full-look presets and new v2 favorites preserve LUT bytes, strength, grain amount/seed and finish settings. Capture look controls and the editor restore those parameters; the camera image itself remains ungraded. Legacy v1 LUT-only favorites still load; known built-in spatial carriers recover their matching settings, but unknown lost settings cannot be reconstructed. New favorite IDs distinguish the same color table with different spatial parameters. Imported Hald tables support square level 2–8, opaque 8-bit RGB sRGB PNG; rotated, other-profile, non-table and oversized inputs are rejected. The importer requires an explicit sRGB declaration. Creative finishing is an SDR approximation; its spatial taps may differ across resolutions and need photographic evaluation.

Implementation details, source/license comparisons and per-unit CI evidence: [Phases 4–6](docs/11-PHASE4-6-IMPLEMENTATION.ko.md), [official film/LUT sources and quality](docs/12-FILM-SOURCES-AND-QUALITY.ko.md). Real iPhone image quality, capture delivery, Vision accuracy, FPS, memory, battery and thermal validation remain pending.


## Performance, capture requests and look import expansion

Neutral live preview now skips the LUT compute pass and graded texture. Immutable Metal compute pipelines are cached by GPU/function; frame buffers remain isolated. Thermal/Low Power Mode budgets reduce processed dimensions and analysis cadence without changing sensor FPS or original photo resolution. These are workload controls; device speed, battery and thermal improvements have not been measured.

Under **PRO → 사진 해상도 상한**, select an actual size advertised by the active format, or keep its maximum. The selected value is a request ceiling; the output can be smaller. The last processed file’s actual pixel dimensions are displayed separately. RAW/bracket keep their prior maximum policy. This does not add resolutions absent from the active format. LUT/depth derivative export supports up to 64MP; actual depth delivery may restrict capture resolution.

Standalone 1D `.cube` tables retain up to 65,536 exact RGB rows and interpolate each channel directly on CPU/Metal. Mixed 1D+3D shapers remain unsupported. **스타일·프리셋 → 여러 LUT 가져오기** imports up to 32 cube/Hald files sequentially after sRGB confirmation, reporting partial success per file. Twenty-four original profiles include split-tone/toned monochrome families; five external slay LUTs retain original names and attribution. Favorites, full presets, recipes and exported JPEG captions retain available provenance.

[Source review, implementation contracts and test evidence](docs/13-PERFORMANCE-CAPTURE-LOOKS.ko.md). All real iPhone validation remains pending.

Previous expansion validation: [CI39550566621](https://github.com/MetaParodica/PhotoP/actions/runs/39550566621) passed unsigned iPhone SDK build, **139 Swift tests**, **11 Python tests** and hash/license checks for all **five source and copied-app LUTs**, with no skipped Swift tests.
