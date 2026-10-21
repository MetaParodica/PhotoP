# 성능·사진 해상도·룩 지원 확장

기준: 2026-10-21 KST. PhotoP의 기존 Phase1–6 기반을 유지하고 성능·촬영 요청·스타일 가져오기 범위를 확장했다. 실제 iPhone 검증은 별도 대기하며, 자동 검증에 성공한 뒤 다음 구현 단위로 진행한다. 아래 처리 상한은 실측 FPS·배터리·발열 개선량이 아니다.

## 1. 구현 기능

- device+function별 immutable Metal compute pipeline 캐시. 중립 preview는 LUT compute pass와 별도 graded texture를 생략한다. mutable 프레임 자원은 공유하지 않는다.
- 발열·저전력 상태에 따라 preview 해상도/처리 admission과 Vision/histogram 빈도를 조절한다. 센서 FPS·사진 activeFormat·원본 해상도는 이 정책으로 변경하지 않는다.
- 활성 포맷의 실제 supportedMaxPhotoDimensions 중 사진별 요청 상한을 선택하고, 일반 사진의 실제 파일 픽셀 크기를 ImageIO에서 읽어 별도로 표시한다.
- 단독1D cube(2~65536개 RGB행)를 채널별 직접 선형 보간한다. 기존3D cube(2~65)는 trilinear를 유지한다. mixed shaper+3D는 계속 거부한다.
- 자체 스타일24종과 외부 slay5종, 총29종. 카테고리/검색/합성 색상표, 전체 룩 preset과 LUT-only 즐겨찾기, 최대32개 순차 가져오기와 파일별 성공/실패 보고.
- 외부 LUT 원본5개·CC BY4.0 전문·제작자/credit/source/hash/profile assumption을 번들에 포함한다. 즐겨찾기·프리셋·recipe·JPEG caption에 attribution을 보존한다.

## 2. 실제 오픈소스·공식 API 조사

| 프로젝트·revision | 확인 파일·발견 | 라이선스·채택 |
|---|---|---|
| [MetalPetal](https://github.com/MetalPetal/MetalPetal/tree/f9b78897bd4214bb097f352a1bde0a4f4a1e2ddb) | Frameworks/MetalPetal/MTIContext.m: function/render/compute pipeline cache. repo pushed2024-04-10 | MIT LICENSE 원문 확인. immutable pipeline 재사용 원칙을 독립 구현, dependency·코드 복사 없음 |
| [OpenColorIO](https://github.com/AcademySoftwareFoundation/OpenColorIO/tree/22dd9c4faa0d1b7cfb3d64d1a6e9cb454acc6cfd) | src/OpenColorIO/fileformats/FileFormatIridasCube.cpp: standalone1D/3D·domain·행수·red-fastest. repo pushed2026-10-01 | BSD-3-Clause LICENSE 원문 확인. 자체 Swift/Metal parser/보간 확장, 전체 OCIO/ACES 도입 아님 |
| [slaycamera/luts](https://github.com/slaycamera/luts/tree/a1709044efe115640dde1dee17d4185fc059af0d) | README·LICENSE 전문·tools/generate-luts.mjs·5개 cube header/모든 RGB행. repo pushed2026-10-06 | LUT 자체 CC BY4.0, 원저작자 attribution과 share/repack 조건 확인. 원본5개 byte/hash·license·credit 보존. UI/사진/앱 코드/생성기 코드는 복사하지 않음 |
| [lut-vizualizer](https://github.com/pierre-thurau/lut-vizualizer) | repo license metadata 없음, README 검색의 CC0 sample 안내와 commercial redistribution 선호 문구 혼재 | 개별 범위·권리 추가 확인 전 보류. repo 전체 권리를 추정하지 않음 |

slay 생성기는 normalized RGB 곡선/채도/split-tone를 사용하지만 정확한 transfer/gamut은 명시하지 않는다. 따라서 PhotoP는 **sRGB SDR 해석을 가정**하며 manifest의 `profileBasis=assumed-sRGB`와 `requiresSRGBConfirmation=true`, UI 확인·recipe provenance에 기록한다. 공식 Log 변환으로 간주하지 않는다. CC BY가 상표권/제휴/후원을 부여하는 것으로 표시하지 않는다. 원본 LUT를 독립 LUT pack으로 판매하는 기능은 없다.

사진 요청의 공식 계약: [PhotoSettings.maxPhotoDimensions](https://developer.apple.com/documentation/avfoundation/avcapturephotosettings/maxphotodimensions), [PhotoOutput.maxPhotoDimensions](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/maxphotodimensions). 현재 활성 포맷의 지원값과 정확히 일치하고 output 상한의 양축 이하여야 한다. 요청은 최대 크기이며 실제 결과는 더 작을 수 있다. 같은 output 상한의 반복 설정을 피하고 사진별 settings만 변경한다. 없는24/48MP를 생성하거나 특정 기기의 제공을 보장하지 않는다.

## 3. 선택한 접근·성능 계약

| 상태 | 최대 처리 긴 변 | 처리 admission 상한 | 새 Vision 분석 간격 | histogram 간격 |
|---|---:|---:|---:|---:|
| nominal/fair |1024px|60Hz|0.5초|0.25초|
| 저전력 |720px|30Hz|1초|0.5초|
| serious |720px|20Hz|1초|0.5초|
| critical |480px|10Hz|중지|1초|

처리 상한은 실제 sensor/display FPS와 다르다. serious의 정사각형 기준 pixel-rate budget은 nominal의 약16.5%로 줄지만, 이는 산술 상한이며 speed-up 실측이 아니다. 한 프레임 in-flight·원본 buffer의 GPU 완료까지 수명·기존 색변환을 유지한다. 중립 모드에서도 CI 색변환·회전·표시 pass는 필요하다. off로 전환한 film scratch/graded texture는 해제한다. PSO만 공유하고 mutable buffers/textures는 renderer별로 유지한다.

일반 사진 해상도 선택은 PRO에 위치한다. 렌즈/스트림 구성 변경 후 지원목록에서 빠진 선택값은 최대 상한으로 복귀한다. RAW/브래킷은 이번에 세부 해상도 선택을 제공하지 않고 기존 최대 상한 정책을 유지한다. 12.6MP 초과 원본은 촬영/보존할 수 있지만 현재 SDR 편집본 내보내기 한도는12.6MP다.

1D LUT를 낮은 크기의3D cube로 굽지 않는다. 채널별 curve 데이터를 그대로 보존하고 CPU/Metal 모두 직접 선형 보간한다. user cube/favorite/preset/recipe는 원본 table bytes를 유지한다. batch는 한 장씩 읽고 저장하며, 최대32개·파일당32MiB/Hald8MiB 제한을 적용한다. 부분 성공을 별도로 보고하며 실패를 완료로 표시하지 않는다.

## 4. 스타일·출처 보존

자체 추가12종: Cyanotype, Sepia Paper, Selenium Dusk, Platinum Soft, Teal & Amber, Neon Rose, Desert Copper, Sakura Air, Emerald Dusk, Bleach Silver, Ocean Mist, Autumn Rust. 음영/명부 색을 독립적으로 조절하는 창작 수식을 추가했다. 기존12종의 기본 tonal 값은0으로 유지한다. 자체 스타일은 브랜드 필름/유제의 측정 재현이 아니며 좁은 profile-data 사용 허가는 `Film/STYLE-PERMISSION.txt`에 있다.

외부5종: slay Amber/Fade/Neon/Film/Portrait. 모든35937행/33³를 확인했고 원본 Git blob SHA와 일치하는 파일을 포함했다. 개별 SHA256·license 파일 SHA256·credit/source가 `assets/luts/manifest.json`에 있다. 앱 runtime과 Python gate에서 hash/profile/권리를 확인한다. SDK app에 복사된 `luts` 폴더도 CI에서 원본 manifest 및 해시를 대조한다. 타사 preview 사진은 포함하지 않고 실제 LUT에서 계산한 색상표만 표시한다.

외부 룩의 출처를 즐겨찾기에서 잃던 경로를 수정했다. 동일 cube의 기존 출처 없는 즐겨찾기는 검증된 provenance를 다시 저장할 때 metadata만 갱신한다. LUT-only는 강도/마감값을 저장하지 않고 full-look preset은 해당 값을 함께 저장한다. 내보낸 JPEG의 IPTC Caption/Abstract와 recipe에는 credit/license URI/source/색공간 가정을 남긴다. 플랫폼/편집기에서 metadata를 제거할 수 있으므로 UI에도 공유 시 유지할 credit을 표시한다. 원본 파일의 EXIF/개인정보를 파생 JPEG로 복사하지 않는다.

## 5. 주요 생성·수정 파일

- 성능: MetalPipelineCache.swift, PreviewBudget.swift, MetalLUTRenderer/MetalLUTTextureRenderer, FilmFinish, LivePreviewImageProcessor/LiveLUTPreview, CompositionAnalyzer, PreviewBudgetTests/LivePreviewTests.
- 촬영: PhotoResolution.swift, CameraTypes/CameraService/CapturedPhoto/CameraModel, ManualControls, PhotoResolutionTests.
- LUT: CubeLUT, MetalLUTResources, LUT.metal, OneDLUTTests/CubeLUTTests.
- 룩/저장/UI: FilmStyleLibrary/STYLE-PERMISSION, BundledFilmLibrary, LUTBatchImporter, LUTLibrary, LUTPhotoEditor/SDRImage, FilmStylesView/LUTEditorView/LUTFavoritesView/LiveLUTControls, FilmStyleLibraryTests/BundledFilmLibraryTests/LUTBatchImporterTests.
- 자산/빌드: assets/luts/manifest.json·slay/*.cube·LICENSE.txt, ios/project.yml, check_lut_bundle.py/test_lut_bundle.py, ios.yml.

## 6. 실행·테스트 증거

| 단위 | revision | CI | 결과 |
|---|---|---|---|
| pipeline/cache·중립·thermal |6d7d2eae672735dff4122bc5e4372010672066b1|[39544188467](https://github.com/MetaParodica/PhotoP/actions/runs/39544188467)|unsigned SDK·Swift124·Python7 성공|
| 사진별 해상도 요청·실제 metadata |6977d87b5a7275211ff76ebf1a11c70429d97d37|[39544511878](https://github.com/MetaParodica/PhotoP/actions/runs/39544511878)|unsigned SDK·Swift128·Python7 성공|
| 단독1D cube CPU/Metal |f274a26e2936951299d5ef89380982fc046d6569|[39544857433](https://github.com/MetaParodica/PhotoP/actions/runs/39544857433)|unsigned SDK·Swift132·Python7 성공|
|29종·batch·credit·정밀도 수정·실제 app bundle|3abee4006a3298a49eb63dde8dae710a37c747c9|[39550566621](https://github.com/MetaParodica/PhotoP/actions/runs/39550566621)|unsigned SDK·Swift139·Python11·source/app자산5개 hash 성공, skip0|

로컬은 Linux이며 Python11 및 상용 자산 gate5개는 성공했다. iOS build/XCTest는 GitHub macOS CI에서 수행한다. 기기 실행으로 표시하지 않는다. 중립/identity 픽셀·PSO identity·시간/thermal 정책, 해상도 목록/양축상한/없는값/RAW/bracket·실제JPEG크기, 1D65536 원본행/범위/채널/CPU·사진GPU·textureGPU 일치를 검증했다. 룩 통합은 hash/권리/합성chart·GPU/CPU·변조/profile 확인·favorite/preset/recipe/JPEG credit·batch 부분 성공을 검사한다.

## 7. 제약과 다음 검증

실제 FPS/CPU/GPU 시간·resident memory·배터리·발열, 24/48MP delivery·shot-to-shot latency·EXIF, 피부/고채도/야경의 미학·banding/halo는 미검증이다. 수치 통과가 실측 필름 재현이나 상용 품질 승인이라는 뜻은 아니다. 100+ 스타일, HDR/Log/RAW 현상·mixed shaper·고해상도 편집·가로 UI·영상/Android는 후속이다. 이번 범위 밖의 원본 촬영/장노출/구도 제한은 기존 문서대로 유지한다.


### 발견한 색상 정확도 오류와 수정

첫 통합 `c355558`의 SDK는 성공했으나 Swift138개 중1개가 실패했다. Neon Rose의 고채도 입력(0.9,0.8,0.1)에서17³ 표의 청색 보간0.0221702가 analytic0.0061282와 약0.01604 차이로 기존0.015 허용 오차를 넘었다. 허용 오차는 유지하고 해당 스타일만33³로 높였다. 기존12종의17³ 표는 유지한다. 독립 수치 진단과 특정 near-clipped blue 회귀 테스트를 추가했다. 다른 경로의137개 테스트는 첫 통합에서 성공했다.

수정 후 `3abee4006a3298a49eb63dde8dae710a37c747c9`의 전체 gate는 성공했다. Neon Rose 전용 회귀를 포함해Swift139·Python11, source와 실제 unsigned app의5개 LUT/license hash 모두 통과했다. 실기기 품질/성능 승인과 분리한다.
