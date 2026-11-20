# PhotoP — 작업 가이드

iPhone 전문 카메라 앱(SwiftUI + AVFoundation + Metal). iOS 18+, Swift 5 언어 모드, `SWIFT_STRICT_CONCURRENCY: complete`. Android는 이후 단계.

## 개발 일지 — 매 작업 기록

- 사용자 요청에 따라 개발·조사·문서·실패/수정·검증·커밋/푸시 내용을 **`docs/development-log/YYYY-MM-DD.md`에 날짜별로 누적 기록한다.** 같은 날의 기존 내용을 보존하고 여러 작업을 한 파일에 정리한다.
- 작업 시작 때 당일 파일을 확인하고, 없으면 [템플릿](docs/development-log/TEMPLATE.md)으로 만든다. **완료 답변 전에 당일 일지와 [색인](docs/development-log/README.md)을 갱신한다.**
- 날짜는 사용자 지정 시간대, 없으면 클라이언트 시간대(현재 Asia/Seoul·KST)를 따르며 파일에 명시한다. 과거 UTC 기록은 원래 시각을 유지한다. 직접 실행·기존 CI 확인·Git 기반 회고를 구분하고 미실행/미커밋/미푸시도 실제 상태대로 남긴다.
- 상세 규칙은 [AGENTS.md](AGENTS.md)와 [일지 안내](docs/development-log/README.md)를 따른다. 기존08 검증 이력·주제 문서는 유지하고 일지에서 연결한다.

## 처음 시작할 때

- 2026-11-20 사용자 후속 결정은 [46 실험적 AI 심도 기획](docs/46-EXPERIMENTAL-AI-DEPTH-PLAN.ko.md)이 우선한다. 기능별 기본Off·설정을 통한 활성화, 사진/저장영상/라이브 독립 지원. 사진 전용 정밀 선택/인물 alpha/고해상도 편집은 사진부터 독립 제공하며 영상 전체 추적을 선행 조건으로 두지 않는다. 실험 공개의 기본 기능 검증과 정식 품질 인수를 구별한다. 현재는 기획이며 설정/새 모델 구현 완료가 아니다.

- 2026-11-20 외부 AI 전체 추적 도입의 최신 조사는 [45 보고서](docs/45-EXTERNAL-AI-TRACKER-ADOPTION-RESEARCH.ko.md)를 따른다. EdgeTAM 전체 masked Core ML 경로를 1차 PoC로 권고하고 EfficientTAM은 참조/차선으로 유지한다. 인물 alpha는 MatAnyone 2/Swift 포트를 별도 비교한다. 14개 저장소·7개 모델 spec·전체 EfficientTAM CPU 합성3프레임을 확인했으며 신규 앱 모델 채택·실기기 인수는 하지 않았다. Core AI iOS27 공식 API 조사와 SDK27/기기 실행을 구분한다.

- 2026-11-20 차세대 심도 고도화는 [감사42](docs/42-COMPUTATIONAL-DEPTH-AUDIT.ko.md)·[계획43](docs/43-COMPUTATIONAL-DEPTH-PLAN.ko.md)·[구현44](docs/44-COMPUTATIONAL-DEPTH-IMPLEMENTATION.ko.md)를 따른다. 기존 엔진 재사용, shared Metal PSF·제한 매트 보정·영상 등록·v4 비파괴 brush/v2 영상 보간을 구현했다. 검증 소스77fa25f를 두 전체 CI44687571347(26.3)/44687571198(26.6) success 후 main push했다. native409중408통과/Flow1skip·UI17·portable150·Python34. 정확한 SHA·게시/미인수는08의60절·당일 일지가 우선한다. 실제100장/영상·기기 trace와 EfficientTAM whole tracker/runtime/ANE는 아직 인수되지 않았다.

- 2026-11-20 사진·영상 심도/추적 검증 소스 `f140234`를 main에 push했다. 전체 CI44665022130(Xcode26.3)·UI CI44665022029(Xcode26.6) success, native392통과/Flow1skip·UI15·공통140·Python31. 최종 검증/게시 기록은08의59절과11월20일 일지를 따른다. 실기기27.2 인수는 대기다.
- 사진·영상 공통 심도/선택 대상 추적의 새 구현은 [41 구현 기록](docs/41-VIDEO-DEPTH-IMPLEMENTATION.ko.md)을 따른다. 조사39·사전 계획40을 먼저 작성했다. 최신 테스트/게시 상태는08과 당일 일지에 기록하며 실제 기기 품질·시간적 일관성 모델/네이티브 Cinematic은 후속 검증이다.

- 2026-11-19 [38 카메라 앱·카메라 비교](docs/38-CAMERA-APP-AND-CAMERA-FEATURE-COMPARISON.ko.md)는 공식 기능/현재 소스 대조와 후속 제안이다. 새 제품 정책 확정·앱 구현·실기기 화질 검증이 아니며 AI 구도 추천 임시 중지 등 기존 결정을 유지한다.
- [34 개발 온보딩](docs/34-DEVELOPER-ONBOARDING.ko.md)을 먼저 읽는다. 2026-11-18 main `2c1a7b3`, 이전 `004d869` 이후17개 커밋의 요약·실행 방법·소스 진입점을 정리했다.
- 이전 main 촬영 UI·심도 소스 `6b9b148` 전체 [CI44505418877](https://github.com/MetaParodica/PhotoP/actions/runs/44505418877)는 SHA·success·원시 job/단위/LUT/UI 로그를 확인했다. Xcode26.3·SDK/Simulator26.2, 공통134·Python31, 네이티브378개 중377통과/기존 Flow1skip, UI14통과. 첫 UI 보조 스크롤 실패와 수정, 실제 기기 인수 미완료는 [08의56~57절](docs/08-STEP-VALIDATION.ko.md)을 따른다. 이전 온보딩 기준 `2c1a7b3`의 CI44240812815는 당시 기록이다.
- 현재 제품 결정은 아래 최우선 절, 기존 F1/F2 구현은33 문서, 영상 심도/추적은41 문서, 남은 과제는32 문서를 따른다. 아래 오래된 “최우선”·iOS17·테스트 수·진행 상태는 당시 기록이다. 위치 태깅은 결정만 있고 아직 코드/권한 요청이 없으며 F1/F2 실기기 인수도 대기다.

## 2026-11-18 사용자 결정 — 최우선

- 후속 영상 심도 요청은 [39 조사](docs/39-VIDEO-DEPTH-AND-TRACKING-RESEARCH.ko.md)·[40 계획](docs/40-VIDEO-DEPTH-IMPLEMENTATION-PLAN.ko.md)을 따른다. 사진/영상 공통 대상 추적·실제 심도 영상 출력을 개발하며 AI 구도 추천은 계속 중지한다. 사용자가 라이선스 종류와 무관한 오픈소스 조사·필요시 복사를 명시했으므로 이전의 라이선스별 조사/복사 제외 권고보다 우선한다. 실제 복사·이식은 원문 조건/출처·고정 SHA·범위·용도를 일지/NOTICE에 기록하고 고지문을 유지한다.
- 최신 촬영 UI 요청은 [37 구현 기록](docs/37-CAMERA-DEPTH-QUICK-CONTROLS.ko.md)을 따른다. 뷰파인더를 설정과 겹치지 않는 박스로 배치하고 패널 높이1.5배·간편 f값/터치 초점·전경 CoC 합성을 반영했다. **AI 구도 추천/코치/자동 리뷰는 임시 중지**하며 수동 가이드와 심도 AI는 유지한다. Xcode26.3 전체 회귀는 통과했고 iPhone 15 Pro/iOS27.2 실제 기기 인수는 대기다.
- HDR 출력·게인맵 생성/보존·Log/HDR 영상·C2PA는 도입하지 않는다. 파생물과 영상은 SDR이다.
- 최소 iOS는 18이다. 위치 태깅은 기본 활성화하며 거부 시 위치 없이 촬영한다.
- 후속 결정: **AI 처리 결과는 1차로 메타데이터에 표시하고 앱 내에서 공지한다.** 원본 파일에 표기를 덧붙이지 않으며 픽셀 워터마크/C2PA는 1차 범위에 포함하지 않는다.
- **공유본은 위치 정보를 제거하고 원본 사진 내보내기는 기록된 위치를 포함한다.** 생성 시점 권한/유효 위치가 없으면 위치 없이 촬영한다. 공유 사본을 별도로 만들며 보관 원본 bytes/hash는 바꾸지 않는다.
- **출력 형식은 가능하면 품질 우선**이다. JPEG 기본 유지라는 이전 제안은 확정안이 아니다. 원본 재압축/자동 축소를 피하고 지원 형식별 품질·색·메타데이터를 검증해 정한다.
- 구형 원격3개는 archive 태그 보존 후 삭제했다. 정확한 태그/원래 SHA와 최신 정책은 [36 결정·정리 기록](docs/36-USER-DECISIONS-AND-BRANCH-CLEANUP.ko.md)을 따른다. 새 영상 심도 파생물의 AI 메타데이터/recipe·위치 미복사는41에서 구현했다. 사진의 위치 권한/공유 원본 분리 등 나머지 정책 전체를 완료한 것은 아니다.
- 기존 수행 순서는 T00 → V07 → F1 → F2이며 현재 코드/CI 상태는33 문서를 따른다. 후속 F12 등 과제는32 백로그 순서로 진행하고 검증/미검증 기기는08·32·당일 일지에 남긴다.

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
- 외부 LUT/자산은 출처·hash·license·profile을 manifest에 기록한다(`assets/*/manifest.json`, `scripts/check_*`). 후속 사용자의 명시 지시에 따라 외부 소스 검토/필요시 복사를 허용하며 원문 고지·출처/SHA·범위·수정·실제 앱 포함 여부를 보존한다. 코드와 가중치의 조건/기술 적합성을 구분하고 라이선스만을 이유로 조사 대상을 제외하지 않는다.
- UI 문자열·문서는 한국어. 설계/보고서는 `docs/NN-*.ko.md`, 날짜별 작업은 `docs/development-log/YYYY-MM-DD.md`, 상세 단계별 검증은 `docs/08-STEP-VALIDATION.ko.md`에 기록하고 커밋·CI 번호를 연결한다. 실기기에서 검증하지 않은 항목을 완료로 표기하지 않는다.

## 현재 상태 (2026-11)

- 2026-11-18 사용자 결정(`docs/32-NEXT-TASK-BACKLOG.ko.md` 7절): 위 최우선 절을 따른다. T00에서 배포 설정과 셔터음 지원 분기를 iOS 18 기준으로 정리했고 `4bc0a24` 전체 CI44228552924가 성공했다. T00·V07·F1·F2 소스 `cf94605` 전체 CI44235743796은 iOS 단위370통과/1skip·UI14통과·portable129·Python31로 성공했다. F1/F2 실제 기기 화질·성능은 미검증이며 F12는 공식 API 확인 전 보류다. 구현/한계는33 문서, 단계별 상태는08·32 문서를 따른다.

- 2026-11-17 최적화 구현은 `docs/30-OPTIMIZATION-IMPLEMENTATION.ko.md`를 최우선한다. 기준 main `f6862b2`, 작업 `codex/optimization-20261117`. 비지역화 LUT 포맷·기술/sRGB Float64 캐시·캐시 쓰기 실패 시 유효 룩 유지·정규화/매트/입력 재사용·단일 선택 매트·Flow backoff/Code9 Simulator 오류만 skip·저장 중 편집 잠금·signpost·회귀 분리/프로세스 종료/자료 보존을 추가했다. 소스 `241c1be` 전체 CI44056942568에서 공통118/Python31, iPhone/Simulator 빌드, 네이티브355개 중354통과/Flow1skip, UI11개 통과를 확인했다. 앞선 `72df01b` 전체 CI44054275255와 UI 집중44054370318도 성공했다. 이번 후속 문서 정리는 앱 코드 변경이 아니다. 실기기 성능/화질·iOS27 인수와29 보고서의 나머지 과제는 미완료다.

- 2026-11-16 후속 심도 Phase 구현/테스트는 `docs/28-DEPTH-PHASE-IMPLEMENTATION.ko.md`를 최우선한다. 측정/AI affine 융합, 선택 인스턴스 매트·보수적 알파/색 복원, Natural/Portrait/Classic, 선택적 AI 실시간 심도·세대/움직임/만료 안전 복귀, 최대64MP·저장 사진 터치 재초점/프로필/f값 보관함, 취소/중단 복구를 구현했다. `OnDeviceInferenceGate`는 구도/리뷰/AI/매트 추론 실행을 직렬화한다. 공통 로직110/Python28 통과와 iOS SDK/Simulator/실기기 결과는 구분한다. 2026-11-17 사용자 요청으로 기존 개발분과 `docs/29-OPTIMIZATION-AND-ADVANCEMENT-AUDIT.ko.md`를 main에 통합한다. 기준 main은 `dc75be6`이었다. 심도 집중 CI43918075081은 성공(38개 통과/Optical Flow1개 skip), 전체 CI43918582758은 테스트 재시작·시간 초과로 실패했으므로 전체 회귀 성공으로 표시하지 않는다. `scripts/check_depth_acceptance.py`는 실제100장/기기 trace/블라인드/권리 인수가 없으면 exit2이다. `--validate-only`를 화질 통과로 인용하지 않는다. Optical Flow 실기기 방향 검증·실측 PSF·눈 AF/전체 DSLR 목록·iOS27 실기기 인수는 미완료다. 다음 문단의1차 제약은 당시 기록이다.

- 2026-11-16 외부 모델·AF/심도1차 구현은 `docs/27-AF-NATURAL-DEPTH-IMPLEMENTATION.ko.md`를 우선한다. `assets/depth-model`에 Apple Core ML Depth Anything V2 Small FP16을 고정 revision/Apache2 LICENSE·NOTICE·hash로 포함한다. `scripts/check_depth_model.py`를 실행한다. 센서 우선/AI 상대 깊이·최대12.6MP Natural disk layers·깊이 f32/recipe v2 저장과 f값 재처리, AF-S/C·독립 터치·AF-ON·MF 하단 확대를 추가했다. SDK26/27 조건부 어댑터는 availability+포맷 지원 검사도 요구한다. iOS27 native metadata/Auto ISO·iOS26 rect 분기는 SDK/실기기 미검증이다. 기존64MP LUT/고해상도 센서 기본 심도는 유지하며 새 Natural의 실시간 프리뷰·눈 AF·전체 DSLR 로드맵 완료를 주장하지 않는다. portable97/Python23·Swift142 구문 검사와 iOS SDK/CI/기기 품질 결과를 혼동하지 않는다.

- 2026-11-16 추가 조사·계획은 `docs/24-SOFTWARE-DEPTH-DEVELOPMENT-PLAN.ko.md`, `docs/25-AF-DSLR-FEATURE-RESEARCH.ko.md`, `docs/26-IOS17-27-CAPABILITY-RESEARCH.ko.md`를 참조한다. 원격 main `dc75be6` 기준으로 Leica·Apple·Sony·Nikon 공식 문서 및 일부 공개 소스를 직접 검토하고 조회 hash를 `docs/research/2026-11-16-official-camera-sources.json`에 기록했다. iOS27 native tracking·auto exposure sentinel,26 rect/cinematic 제약을 구분한다. 이는 문서 변경일 뿐 새 AF/심도 기능이나27 SDK·실기기 검증이 완료된 것이 아니다. 앱 최소 배포17은 유지한다.

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
