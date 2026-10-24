# PhotoP — 작업 가이드

iPhone 전문 카메라 앱(SwiftUI + AVFoundation + Metal). iOS 17+, Swift 5 언어 모드, `SWIFT_STRICT_CONCURRENCY: complete`. Android는 이후 단계.

## 빌드·검증

- Xcode 프로젝트는 생성물이다(`ios/PhotoP.xcodeproj/`는 gitignore). 원본은 `ios/project.yml` → `cd ios && xcodegen generate`.
- Linux 기본 환경에는 Swift/Xcode가 없다. iOS SDK 빌드·앱 XCTest·UI 테스트는 GitHub Actions(`.github/workflows/ios.yml`, macos-15)에서 확인한다. 별도 Swift 도구 체인이 있으면 루트 `swift test`로 같은 프로덕션 구도/추적·코치·리뷰·촬영 정책 핵심의 portable XCTest를 실행할 수 있다. iOS 빌드나 Vision/카메라 검증과 혼동하지 않는다.
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

- 최신 사용자 요청은 LUT 적용 상태를 뷰파인더에 보여 주는 것이다. `docs/23-LIVE-VIEWFINDER-LOOK.ko.md`를 우선한다. 룩 선택은 live output 수요에 포함하고, 현재 LUT와 강도/입자/마감을 실제 Metal 프리뷰에 전달한다. LUT 교체는 기존 출력의 frameQueue에서 최신 요청 하나만 설치하며 이전 GPU 작업은 해당 processor를 완료까지 보유한다. AI·노출 측정은 무보정 입력 유지, 원본 비교는 표시만 변경, 저장 RAW/영상은 무보정이다. 아래 과거 촬영 결과 전용/프리뷰 무보정 설명은 이전 요청 당시 기록이다. 카드별 예시 프리뷰는 다시 켜지 않는다. SDK/실기기 검증 대기.

- LUT 적용 점검은 `docs/22-LUT-APPLICATION-AND-NEXT-STEPS.ko.md`를 우선한다. 즐겨찾기 v2는 table hash+정렬된 효과 설정+출처ID로 중복을 구분하며 강도/그레인/마감을 복원한다. 구형 v1은 유지하고 정확히 일치하는 자체 공간 carrier만 설정 복구한다. 촬영 당시 룩과 선택한 사진의 원본 대응을 편집기에 전달해 누락/중복 적용을 막는다. 카메라 미리보기는 계속 무보정이고 원본/결과/실패/강도0/작은 색상 변화/RAW·영상 미적용을 구분한다. 임의로 모든 LUT 색을 증폭하지 않는다.

- 2026-10-23 고해상도·권한 변경안은 `docs/21-HIGH-RESOLUTION-LUT-DEPTH.ko.md`를 우선한다. 촬영 후 LUT/실제 심도 결과와 편집기 내보내기는 64MP·긴 변16384px까지 원본 해상도를 유지하는 halo 타일+디스크 매핑 경로를 사용한다. 12.6MP는 작은 in-memory renderer/preview 안전 상한으로 남으며 고해상도 전체 RGBA를 여기에 넣지 않는다. 외부 LUT25개는 사용자가 앱 사용·상업 사용·재배포 가능을 확인한 상태로 기록한다(`user-confirmed`, 독립 감사/공식 제조사 인증 아님). WDR 출력 프로파일 미확인1개는 여전히 원본 제공만 가능하다. 이번 iOS/Metal·실기기 검증은 대기다.

- 최신 UI·촬영 변경은 `docs/19-FULLSCREEN-CAPTURE-WORKFLOW.ko.md`를 우선한다. 전체 화면 뒤로 네이티브/중립 분석 프리뷰를 확장했다. LUT는 카메라·카드 미리보기 없이 촬영 후 별도 SDR JPEG로 적용한다. Depth는 별도 모드 대신 PRO f값 제어로 지원 렌즈의 실제 사진 깊이 데이터를 사용한다(소프트웨어 흐림 강도, 실제 조리개 아님). LONG 레일 맨 앞에 총 합성 시간과 직접 입력을 제공한다. 원본은 변경하지 않는다. 실제 iOS 빌드/기기 검증은 대기다.
- 최신 AI Composition 전체 Phase 변경안: `docs/20-INTELLIGENT-CAMERA-ALL-PHASES.ko.md`. 후속 사용자의 전체 Phase 구현 요청으로 Phase 2–5 코드 통합까지 진행했다. 7개 촬영 의도, 자동 추천/수동 도식 29항목, 실제 영상 측정·Core Motion 코치, 사용자 탭 줌/노출 패널, 촬영 리뷰·전후 비교·선택적 기기 내 구도 횟수 학습을 추가했다. RAW/브래킷은 셔터 시 분석 출력을 해제, LONG은 합성 중 중지, 영상은 동시 출력 지원 시만 분석한다. 리뷰와 실시간 Vision은 공유 추론 게이트를 사용하며 리뷰 동안 실시간 추론을 잠시 멈춘다. iOS SDK/실영상/성능 인수는 대기이며 아래 기존 앱 로드맵의 Phase 번호와 구분한다. 과거 Phase 1 당시 기록은 `docs/18-AI-COMPOSITION-PHASE1.ko.md`.
- Phase 1–6(사진·LUT·RAW·모니터·브래킷·장노출·구도·필름 룩 59+3) 개발 범위 구현, 자동 테스트 통과. 실기기 품질 검증은 대기.
- Phase 7 영상 진행 중: SDR 무보정(LUT 비굽기) 녹화, 720p/1080p/4K·24–60fps·H.264/HEVC, 180° 셔터 제안, 선택 오디오, 지원 손떨림 보정, manifest v2(v1 호환), 파일 검증·영상 라이브러리. 노출 분석은 장치가 동시 출력을 허용할 때 연결한다. 영상 LUT 굽기·Log/HDR은 미구현이다.
- 촬영 개선 변경안은 `docs/17-CAMERA-FIELD-FIXES.ko.md`를 따른다. 하단 dock·연속 설정 큐·가로 회전·초록 피킹·터치/길게 누르기·현장 룩 썸네일·장노출 연결·외부 룩 준비·지원 기기의 공식 셔터음 억제·ARKit LiDAR 패키지를 추가했다. 이 변경의 Xcode/실기기 검증은 아직 미수행이다. 기존 CI 성공을 새 코드의 성공으로 인용하지 않는다.
- 사진 중심 UI 2차 개편: 전폭 뷰파인더+오버레이 헤더/레일, 인물 실루엣 가이드(`Composition/PersonGuide.swift`), 최근 촬영 확인(`CaptureReviewView`), 렌즈 배율·디지털 줌·플래시·타이머·프레이밍 가이드(`Camera/PhotoShootingTypes.swift`). 1:1/16:9는 가이드이며 원본은 4:3.
- 구도 프리셋(`Composition/CompositionPreset.swift`, 점선 영역·포인트·메모)과 하단 카드 선택(`CameraCarousel`, 구도·룩 공용)이 있다.
- CI는 `main`, `codex/**`, `claude/**` push와 PR에서 실행된다.
