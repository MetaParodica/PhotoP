# PhotoP — 작업 가이드

iPhone 전문 카메라 앱(SwiftUI + AVFoundation + Metal). iOS 17+, Swift 5 언어 모드, `SWIFT_STRICT_CONCURRENCY: complete`. Android는 이후 단계.

## 빌드·검증

- Xcode 프로젝트는 생성물이다(`ios/PhotoP.xcodeproj/`는 gitignore). 원본은 `ios/project.yml` → `cd ios && xcodegen generate`.
- Linux 세션에는 Swift/Xcode가 없다. Swift 빌드·XCTest·UI 테스트는 GitHub Actions(`.github/workflows/ios.yml`, macos-15)가 유일한 gate다. push 후 CI 결과로 확인한다.
- 로컬에서 가능한 검사(LUT 자산·아이콘):
  ```sh
  python3 -m unittest discover -s scripts -p 'test_*.py'
  python3 scripts/check_lut_bundle.py
  python3 scripts/check_company_luts.py
  ```
- 시뮬레이터 UI 검토 인자: `--ui-review`, `--review-guide`, `--review-video` (DEBUG+simulator 전용, `CameraView.reviewing`).

## 구조 (`ios/PhotoP/`)

- `Camera/` — `CameraService`(AVFoundation 상태를 직렬 queue가 소유, `@unchecked Sendable`), `CameraModel`(`@MainActor` ObservableObject, UI 상태의 단일 원천). 서비스는 `CameraSnapshot`을 revision 번호와 함께 publish하고, 모델은 오래된 revision을 버린다.
- 정책/검증 로직은 테스트 가능한 `enum …Policy` / 값 타입으로 분리한다(`PhotoCapturePolicy`, `RawCapturePolicy`, `VideoCapturePolicy`, `ExposureBracketPlan`, `CameraControlApplication` 등). 새 기능도 AVFoundation 호출과 판단 로직을 나누고 판단 로직에 XCTest를 붙인다.
- `Processing/` — `.cube`/Hald 파서, CPU 기준 구현과 Metal 렌더러(사진 buffer·라이브 texture 공통 셰이더), 프리뷰 budget/모니터링.
- `Film/` — 자체 스타일, 외부 LUT 라이브러리, V-Log→SDR 어댑터, 마감 효과(`FilmFinish.metal`).
- `Storage/` — 원본·편집 번들·즐겨찾기·프리셋·영상 저장. 해시·버전·경로 검사로 변조/구형 레시피를 거부하거나 호환 복원.
- `LongExposure/`, `Composition/` — 샘플링 장노출, Vision 구도 분석.
- `UI/` — `CameraView` 진입점, `CameraChrome`/`CameraQuickControls` 촬영 화면 패널.

## 지켜온 규칙

- 원본 bytes는 절대 변경하지 않는다. 파생물은 별도 파일로 원자적으로 저장한다.
- 지원하지 않는 장치/포맷 조합은 숨기거나 이유와 함께 명시적으로 거부한다. 가짜 기능(가짜 줌 등)을 만들지 않는다.
- 비동기 장치 설정은 완료 콜백·작업 ID·timeout으로 관리하고 늦은 콜백이 새 작업을 완료시키지 않게 한다.
- 색 처리는 SDR/encoded sRGB 계약 안에서만 주장한다. HDR/Log/RAW 현상은 미구현으로 표기한다.
- 외부 LUT/자산은 출처·hash·license·profile을 manifest에 기록한다(`assets/*/manifest.json`, `scripts/check_*`). 외부 소스 코드는 복사하지 않고 검토 후 독립 구현한다.
- UI 문자열·문서는 한국어. 문서는 `docs/NN-*.ko.md`, 단계별 검증 기록은 `docs/08-STEP-VALIDATION.ko.md`에 커밋·CI 실행 번호와 함께 추가한다. 실기기에서 검증하지 않은 항목을 완료로 표기하지 않는다.

## 현재 상태 (2026-10)

- Phase 1–6(사진·LUT·RAW·모니터·브래킷·장노출·구도·필름 룩 59+3) 개발 범위 구현, 자동 테스트 통과. 실기기 품질 검증은 대기.
- Phase 7 영상 진행 중: SDR 무보정(LUT 비굽기) 녹화, 720p/1080p/4K·24–60fps·H.264/HEVC, 180° 셔터 제안, 선택 오디오, 지원 손떨림 보정, manifest v2(v1 호환), 파일 검증·영상 라이브러리. 노출 분석은 장치가 동시 출력을 허용할 때 연결한다. 영상 LUT 굽기·Log/HDR은 미구현이다.
- 촬영 개선 변경안은 `docs/17-CAMERA-FIELD-FIXES.ko.md`를 따른다. 하단 dock·연속 설정 큐·가로 회전·초록 피킹·터치/길게 누르기·현장 룩 썸네일·장노출 연결·외부 룩 준비·지원 기기의 공식 셔터음 억제·ARKit LiDAR 패키지를 추가했다. 이 변경의 Xcode/실기기 검증은 아직 미수행이다. 기존 CI 성공을 새 코드의 성공으로 인용하지 않는다.
- 사진 중심 UI 2차 개편: 전폭 뷰파인더+오버레이 헤더/레일, 인물 실루엣 가이드(`Composition/PersonGuide.swift`), 최근 촬영 확인(`CaptureReviewView`), 렌즈 배율·디지털 줌·플래시·타이머·프레이밍 가이드(`Camera/PhotoShootingTypes.swift`). 1:1/16:9는 가이드이며 원본은 4:3.
- 구도 프리셋(`Composition/CompositionPreset.swift`, 점선 영역·포인트·메모)과 하단 카드 선택(`CameraCarousel`, 구도·룩 공용)이 있다.
- CI는 `main`, `codex/**`, `claude/**` push와 PR에서 실행된다.
