# PhotoP 개발 온보딩

작성일: **2026-11-18**. 확인한 원격 `main`: **`2c1a7b3dbd381a56d6e5d34236cc3af62f9da0f6`**.
이전 인계 기준 `004d869` 이후 **17개 커밋·30개 파일 변경**을 문서·실제 소스·CI 로그와 대조했다. 이 문서는 개발 인계이며 새 앱 기능을 구현한 기록이 아니다.

## 1. 먼저 알아야 할 현재 상태

PhotoP는 iPhone용 SwiftUI·AVFoundation·Metal 카메라 앱이다. **최소 iOS 18**, **Swift 5 언어 모드**, `SWIFT_STRICT_CONCURRENCY=complete`를 사용한다. Xcode의 Swift 컴파일러 버전과 프로젝트의 언어 모드는 구분한다. Android와 엄격한 Swift 6 언어 모드 전환은 별도 과제다.

기존 기반은 수동 노출·AF/AE/WB 제어, RAW/ProRAW 원본 보존,3장 브래킷, 샘플링 장노출, 무보정 SDR 영상, 실시간 LUT와 고해상도 파생물, 센서/AI 소프트웨어 심도·저장 사진 재초점, 구도 코치다. 실제 사용 가능 조합은 기기·렌즈·포맷 지원에 따라 제한한다.

이번 main에는 다음이 추가됐다.

| 영역 | 구현·확인한 내용 | 아직 완료로 보면 안 되는 범위 |
|---|---|---|
| T00 — iOS 18 | 배포 타깃18.0, CI의 Simulator18 이상 검사, 셔터음 억제의 불필요한 OS18 분기 제거 | 셔터음 억제는 여전히 실제 장치 지원 검사 필요. 모든 iOS18 기기 기능을 보증하지 않음 |
| V07 — 저장 중 편집 잠금 | 실제 심도 편집기의 f값·프로필·원본 비교 잠금, 물리 터치 후 값 불변, 저장 완료/취소 후 복구 UI2개 통과 | 실제 iPhone의 저장 중단·용량 부족 인수 |
| F1 — SDR 노출 융합 | 기존 브래킷 원본3장 보존, 정렬/고스트 거부, Metal 합산, 별도 JPEG·레시피, 원본 hash 불변 | 최대12.6MP, 정수 평행이동·유한 표본·단일 스케일 가중 합성. 전체 Mertens 피라미드/HDR 합성 아님 |
| F2 — SDR 스코프 | 휘도 파형·RGB 퍼레이드·벡터스코프·False color, LUT 적용 전 입력 분석 | 센서 RAW/HDR/Log·정확한 IRE 계측 아님. 실제 기기 지연·발열·영상 동시 출력 미검증 |
| F12 — 위치 태깅 | 기본 활성화라는 사용자 결정과 API 후보 점검표 | **미구현**. 위치 권한 문구·요청·수집 코드 없음. 켜져 있다고 표시하지 않음 |

사용자가 확정한 제품 범위는 [32 문서 7절](32-NEXT-TASK-BACKLOG.ko.md#7-사용자-결정)과 [36 후속 결정](36-USER-DECISIONS-AND-BRANCH-CLEANUP.ko.md)을 따른다. 파생 사진·영상은 **SDR**이며 **HDR/게인맵 생성·보존, Log/HDR 영상, C2PA는 도입하지 않는다**. AI 결과는 메타데이터·앱 내 공지, 공유본은 위치 제거·원본 내보내기는 위치 보존, 출력은 품질 우선으로 결정됐다. 권한 거부/유효 위치 없음이면 위치 없이 촬영한다. 이 후속 정책은 위 main 스냅샷에서 이미 구현된 기능이라는 뜻이 아니다.

## 2. 문서 읽는 순서

1. [CLAUDE.md](../CLAUDE.md)의 최신 사용자 결정·작업 규칙.
2. 이 문서와 [33 구현 보고서](33-IOS18-FUSION-SCOPES.ko.md): 현행 F1/F2의 동작과 한계.
3. [32 백로그](32-NEXT-TASK-BACKLOG.ko.md): 과제ID·우선순위·결정 대기 항목.
4. [08 단계별 검증](08-STEP-VALIDATION.ko.md): 46~53절의 실패·수정·최종 통과 기록.
5. [30 최적화](30-OPTIMIZATION-IMPLEMENTATION.ko.md), [28 심도 구현](28-DEPTH-PHASE-IMPLEMENTATION.ko.md): 이번 변경의 기반.
6. [31 기능·오픈소스 조사](31-FEATURE-AND-OSS-RESEARCH.ko.md): 후보와 출처를 찾을 때 읽는다. **조사 당시의 공백 목록·HDR/C2PA 후보·iOS17 표기는 현재 구현/결정을 뜻하지 않는다.**

오래된 문서의 “진행 중”, “최우선”, 테스트 수는 당시 기록이다. 현행 동작은 최신 사용자 결정, 현재 소스, 해당 SHA의 완료된 CI로 판단한다.

**매 작업의 기록:** [AGENTS.md](../AGENTS.md)와 [개발 일지 안내/색인](development-log/README.md)을 따른다. 작업 시작 시 해당 날짜의 `docs/development-log/YYYY-MM-DD.md`를 확인하고, 완료 답변 전에 수행·검증·실패/수정·남은 일·커밋/푸시 상태를 누적 갱신한다. 같은 날 여러 요청을 한 파일에 정리한다. 현재 클라이언트 기준은 Asia/Seoul(KST)이며 이전 UTC 기록은 원래 시각을 보존한다.

후속 촬영 UI·심도 합성/조작과 AI 구도 추천 임시 중지는 [37 기록](37-CAMERA-DEPTH-QUICK-CONTROLS.ko.md)을 따른다. 아래 main 스냅샷 CI와 새 미커밋 코드의 검증 범위를 구분한다.

## 3. 새 커밋 17개 요약

범위: `004d869..2c1a7b3`, 오래된 순서다. 중간 진단/컴파일 수정은 별도 제품 기능으로 세지 않는다.

| 커밋 | 핵심 내용 |
|---|---|
| `92bbd4c` | 기능·오픈소스 조사를31번으로 정리하고32 백로그 신설 |
| `d977858` | 최소OS·SDR·위치·AI 표기 등 사용자 결정 기록 |
| `4bc0a24` | iOS18 배포·Simulator 게이트, 셔터음 OS 분기 정리 |
| `f29653a` | 실제 심도 편집기와 저장 barrier를 사용하는 잠금 UI 회귀 추가 |
| `805ee0b` | 네이티브 컴파일 오류와 선택 런타임을 CI annotation에 노출 |
| `c150e81` | 브래킷3장 보존 뒤 SDR Metal 융합·JPEG/레시피 연결 |
| `7f2e7f5` | 파형·퍼레이드·벡터스코프·False color 추가 |
| `f0ce456` | 이미지 fixture와 융합 휘도식을 분리해 Swift 타입 검사 부담 해소 |
| `067173e` | XCTest 요약 보존, LONG 촬영/재합성 때 이전 융합 상태 초기화 |
| `8b3cb40` | 모호한 정렬 거부와 정책·가중치의 레시피 기록 보강 |
| `e7fdda0` | 모니터 GPU 테스트 픽셀의 UInt8 타입 명시 |
| `eb5ea75` | 축소 정렬 뒤 원본 픽셀 좌표에서 정밀 이동 보정 |
| `d19e220` | 편집기 잠금 실패의 정확한 단언 위치 노출 |
| `b2f423f` | 보존된 UI 실패 로그의 실제 위치 확인용 임시 진단 |
| `cf94605` | 개별 세그먼트 대신 전체 프로필 컨트롤 잠금 검사. 물리 터치·값 불변 검사는 유지 |
| `d06fd3d` | 전체 CI 성공과 구현/실기기 인수 경계 기록 |
| `2c1a7b3` | 최종 검증 보고서 공백 정리 |

`cf94605..2c1a7b3`의 앱·테스트·프로젝트·Package·CI·scripts·assets 차이는 없다. 최종 두 커밋은 문서 변경이다. 정확한 diff는 `git log --oneline 004d869..2c1a7b3`와 `git diff 004d869..2c1a7b3`로 확인할 수 있다.

## 4. 코드에서 시작할 위치

| 위치 | 책임·이번 변경의 진입점 |
|---|---|
| [ios/project.yml](../ios/project.yml) | XcodeGen 원본, 배포18.0·Swift5·SDK26/27 조건. 생성된 xcodeproj를 직접 관리하지 않음 |
| [CameraModel.swift](../ios/PhotoP/Camera/CameraModel.swift) | MainActor UI 상태. `capture()`, `bracketFusionEnabled`, `latestFusion`/실패 사유, LONG 상태 초기화 |
| [CameraService.swift](../ios/PhotoP/Camera/CameraService.swift) | AVFoundation 장치·세션을 소유한 직렬 queue, 실제 지원 검사·캡처 콜백 |
| [ExposureFusionPolicy.swift](../ios/PhotoP/Processing/ExposureFusionPolicy.swift) | 초기/정밀 정렬, 노출 정규화, 모호성·잔차·고스트 거부, Codable 정책·가중치 |
| [ExposureFusionProcessor.swift](../ios/PhotoP/Processing/ExposureFusionProcessor.swift) / [ExposureFusion.metal](../ios/PhotoP/Processing/ExposureFusion.metal) | 원본 hash 확인, GPU 합산, 결과 원자 게시 |
| [LiveLUTPreview.swift](../ios/PhotoP/Processing/LiveLUTPreview.swift) / [PreviewMonitoring.swift](../ios/PhotoP/Processing/PreviewMonitoring.swift) | 프리뷰 수요·통계 예산·단일 in-flight/GPU 완료 뒤 집계 전달 |
| [ScopeAnalysisPolicy.swift](../ios/PhotoP/Processing/ScopeAnalysisPolicy.swift) / [Monitoring.metal](../ios/PhotoP/Processing/Monitoring.metal) | bin 배치·크로마·False color 구간과 GPU 구현 |
| [MonitoringControls.swift](../ios/PhotoP/UI/MonitoringControls.swift) / [CameraQuickControls.swift](../ios/PhotoP/UI/CameraQuickControls.swift) | 스코프 토글·범례, 포맷 패널의 브래킷/융합 설정 |
| [DepthResultLibraryView.swift](../ios/PhotoP/UI/DepthResultLibraryView.swift) | 실제 저장 사진 재초점 편집기·저장/취소·편집 잠금 |
| [DepthEditorReviewFixture.swift](../ios/PhotoP/UI/DepthEditorReviewFixture.swift) / [DepthEditorInteractionTests.swift](../ios/PhotoPUITests/DepthEditorInteractionTests.swift) | DEBUG Simulator 전용 저장 barrier와 실제 UI 회귀 |

F1의 흐름은 **원본3장 보존 → 최대192px 휘도에서 초기 정렬 → 원본 좌표의 최대32×32 표본 격자에서 정수 이동 보정 → 거부 정책 검사 → Metal 가중 합산 → 별도 결과 게시**다. 유효한 결과는 `Documents/FusionResults/<UUID>/photo.jpg`와 `recipe.json`에 저장한다. `.pending-<UUID>`를 원자 이동하며 전후 원본 SHA-256을 비교한다. 레시피에는 요청 EV·초기/정밀 이동·가중치·정책·SDR 계약을 남긴다.

융합 토글은 기본 `true`지만 브래킷을 켜고 지원되는 처리 사진3장을 얻어야 동작한다. 같은 방향·크기의 JPEG/HEIC 최대12.6MP만 지원하며 초과 사진을 자동 축소하지 않는다. 실패 시 원본과 기존 개별 결과를 유지한다. 융합 JPEG에는 LUT를 굽지 않고 리뷰에 **“SDR 노출 융합 · LUT 미적용”**으로 구분한다. 기존 LUT/심도 내보내기의64MP 경로와 융합의12.6MP 상한을 혼동하지 않는다.

F2는 **LUT 적용 전 SDR 입력**을 분석한다. 파형/퍼레이드는64열×64밝기, 벡터스코프는64×64이며 최대256px 격자·4Hz 통계 예산을 사용한다. GPU 완료 뒤 최대81KiB 집계만 복사한다. False color는 통계 주기와 별도로 매 프레임 원본 encoded 휘도에7구간을 적용하며 Zebra/피킹보다 우선한다. 원본 사진·영상에는 스코프를 굽지 않는다.

## 5. 환경과 빠른 시작

### Mac에서 앱 개발

확인된 CI는 **Xcode26.3 / iOS SDK26.2 / Simulator26.2 / macos-15**다. 최소 배포18.0과 실제 시험한 런타임26.2는 서로 다르다. SDK26/27 조건부 코드가 있다는 이유로 해당 기기 인수를 완료했다고 표시하지 않는다.

Xcode와 XcodeGen이 설치된 Mac에서 저장소 루트 기준으로 실행한다.

```sh
swift test
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 scripts/check_depth_model.py
python3 scripts/check_lut_bundle.py
python3 scripts/check_company_luts.py
cd ios
xcodegen generate
xcodebuild -project PhotoP.xcodeproj -scheme PhotoP -sdk iphoneos \
  -configuration Debug -derivedDataPath .build CODE_SIGNING_ALLOWED=NO build
open PhotoP.xcodeproj
```

서명 없는 SDK 빌드는 실기기 설치가 아니다. 실제 촬영은 Xcode에서 개발 팀·번들ID를 설정하고 iOS18 이상 iPhone으로 별도 확인한다. 계정 비밀값은 저장소에 넣지 않는다.

### Cloud/Linux에서 가능한 범위

이번 환경에서 Python3.12.14와 `gh`를 확인했고 Python31개·모델/LUT 무결성 검사를 실행해 통과했다. **현재 PATH에 Swift/Xcode가 없으며 이전 `/tmp` Swift 도구 체인도 확인되지 않았다.** 세션이 바뀌어도 임시 도구 체인이 남아 있다고 가정하지 않는다. 이번 작업에서 Swift/iOS 테스트를 로컬 재실행했다고 주장하지 않는다.

Swift 도구 체인이 별도로 설치돼 있으면 루트 `swift test`로 같은 프로덕션 정책/계산 로직을 검사할 수 있다. 홈 캐시 쓰기가 제한된 Cloud에서는 다음처럼 캐시를 `/tmp`로 지정한다. 이는 iOS SDK·Vision·AVFoundation·Metal·UI 시험을 대신하지 않는다.

```sh
CLANG_MODULE_CACHE_PATH=/tmp/photop-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/photop-module-cache \
XDG_CACHE_HOME=/tmp/photop-cache \
swift test --scratch-path /tmp/photop-onboarding-build \
  --cache-path /tmp/photop-swiftpm-cache --disable-sandbox
```

### CI와 Simulator UI 검토

원격에 존재하는 작업 ref를 사용한다. 아래 `main`은 필요하면 이미 push한 작업 브랜치로 바꾼다.

```sh
gh workflow run ios.yml --ref main -f xcode=26.3 -f test_scope=all
gh run list --workflow ios.yml --branch main --limit 5
```

| 입력 | 실제 검사 범위 |
|---|---|
| `test_scope=all` | 단위·LUT·UI 전체 회귀 게이트 |
| `test_scope=depth` | 지정 심도3개 클래스. 전체 단위/LUT/UI 통과로 인용하지 않음 |
| `test_scope=ui` | UI 집중 실행. 일반 단위/LUT suite는 생략 |
| `diagnostic_run=<실행ID>` | 이전 결과 번들 열람. 새 소스의 테스트 실행이 아님 |

기본은26.3이며26.6/27 선택 시 CI가 설치된 Xcode를 검사한다. 없는 SDK는 실패하므로 옵션 존재만으로 지원을 주장하지 않는다. `main`, `codex/**`, `claude/**` push와 PR은 자동 검증 대상이다.

`.github/workflows/ios.yml`이 명령·런타임 선택의 기준이다. `scripts/run_test_process.py`는 시간 초과/취소 때 테스트 프로세스 그룹을 정리한다. 기본 개별 테스트120초/최대180초와 실패 반환값을 유지한다. `photop-unit-log`·`photop-lut-log`·`photop-ui-log`, `photop-native-ui`의 summary/닫힌 xcresult/화면을 먼저 읽고 실패를 재현한다. 단순 timeout 증가나 넓은 skip으로 실제 오류를 숨기지 않는다.

Python 실행기 회귀는 의도적으로 자식 프로세스를 시간 초과시킨다. `Test process exceeded 0.5s` 메시지만으로 실패라 판단하지 말고 unittest의 최종 `OK`/실패 집계를 확인한다. Swift의 복잡한 이미지/배열 식은 작은 typed 루프로 나누며 UInt8/Int 혼합 추론 오류와 실제 컴파일 오류 annotation을 먼저 확인한다.

Xcode Scheme의 DEBUG Simulator 실행 인자 `--ui-review`에 `--review-guide`, `--review-looks`, `--review-video`, `--review-depth`, `--review-person`을 조합해 화면을 검토한다. 카메라는 작동한다고 꾸미지 않는다. 저장 잠금 검토는 **`--ui-review --review-depth-editor`**다. 유효한 작은 사진/깊이 fixture와 실제 편집기의 저장 경로를 사용하며 `editor.review.releaseSave` 버튼으로 barrier를 해제한다. 호스트는 DEBUG+Simulator 전용이므로 기기/Release 기능으로 옮기지 않는다.

잠금 회귀는 `editor.depth.aperture`·전체 `editor.depth.profile`·`editor.depth.compare`의 상태와 물리 터치 후 값 불변을 확인한다. UIKit의 개별 세그먼트 enabled 플래그는 전체 컨트롤과 다를 수 있다. 저장/취소 뒤 조작 복구까지 검증하며 실패를 없애려고 이 최종 상태 검사를 삭제하지 않는다.

## 6. 실제 확인한 검증 기준선

최신 main **`2c1a7b3`**의 [전체 CI44240812815](https://github.com/MetaParodica/PhotoP/actions/runs/44240812815)는 **success**다. 실행의 SHA 일치·완료 상태와 단위/LUT/UI 원시 로그를 직접 확인했다. 공통129·Python31·SDK/런타임은 같은 실행의 job 로그와도 대조했다.

| 검사 | 결과 |
|---|---|
| 공통 Swift 정책/계산 | 129개 통과 |
| 일반 iOS 단위 | 353개 중352통과·Flow1skip |
| LUT 별도 회귀 | 18개 통과, 독일어 지역 설정 |
| 네이티브 단위 합계 | **371개 중370통과·1skip** |
| UI | **14개 모두 통과** |
| Python·자산·실제 앱 번들 | 31개 및 모델/LUT 검사 통과 |

공통 테스트는 네이티브와 겹치는 로직이므로 독립 기능 수처럼 합산하지 않는다. Flow skip은 Simulator의 알려진 Vision 백엔드 생성 실패다. 실제 기기 방향 검증을 뜻하지 않는다. 앞선 구현 소스 `cf94605`의 [CI44235743796](https://github.com/MetaParodica/PhotoP/actions/runs/44235743796)도 성공했고, 중간 실패를 최종 성공과 섞어 합산하지 않는다.

문서 작성 시 로컬에서는 Python31·자산 검사와 문서 링크/변경 검사를 수행한다. 앱·테스트·CI 소스를 바꾸지 않는 온보딩 작업이므로 새 iOS 전체 회귀는 실행하지 않는다.

## 7. 이어서 할 일과 변경 시 지킬 계약

- **V01/V02/V03/V04/V05/V08:** 실제 기기 p50/p95·메모리·10분 열/전력, Flow 방향, 다중 피사체 매트,24/48MP 저장/취소, 영상 동시 출력과 화질을 인수한다. 심도 평가100장·기기 trace·블라인드 자료는 아직 비어 있다. `check_depth_acceptance.py --validate-only`는 스키마 검사이고 화질 인수 성공이 아니다.
- **F1/F2:** 코드·CI 확인과 실제 촬영 인수는 구분한다. F1은 역광/손떨림/움직임 약30세트와12MP 비용·선명도, F2는1024px 프리뷰 p95·색/가독성·온도·영상 동시 출력 확인이 남았다.
- **F12:** 다음 구현 후보지만 공식 API 본문/사진·DNG·영상·Photos 경로의 계약부터 재확인한다. 이전 작업에서는 문서 본문403으로 보류했으며 이번 온보딩에서 재조회·구현하지 않았다. 위치는 원본 생성 시점에 전달하고 저장 후 원본을 재인코딩해 넣지 않는다.
- **그 다음:** F3 Camera Control, F4 EXIF/ICC·SDR HEIC, F8 추천 컷과 B07/B02/S01은32 백로그 순서로 검토한다. 추론 스케줄러·열 제어·GPU 타일·눈 AF·실측 PSF는 완료된 것으로 취급하지 않는다.
- 원본 bytes·hash 불변, 파생물 UUID 번들의 원자 게시, 장치 직렬 queue·snapshot revision, GPU 완료까지 프레임 소유권을 유지한다. 취소/세대 변경이 늦은 결과를 새 촬영에 적용하지 않게 한다.
- 외부 코드·모델·자산은 조사와 도입을 구분한다. 이번17개 커밋은 새 외부 의존성/모델/통신을 추가하지 않았다. 기존 Small FP16 모델과 LUT는 manifest·LICENSE/NOTICE·hash 검사를 유지하고 도입 금지/보류 후보는31·32를 따른다.
- 후속 사용자 지시로 `claude/maintenance-guide`, `codex/ios-camera-foundation`, `claude/oss-feature-research-20261117`를 원격 archive 태그로 보존한 뒤 삭제했다. 백업 태그/원래 SHA·복구 방법은36 문서에 있다. 다른 브랜치를 임의로 정리하지 않는다.

개발은 현재 원격 main과 작업 트리부터 확인하고 시작한다. 변경을 작게 나눠 관련 정책/SDK/UI 회귀를 실행하고, 코드 SHA·CI 범위·실패/skip 사유·실기기 미검증 항목을08·32에 남긴다. 그날의 전체 작업 요약과 실제 수행/저장소 상태는 날짜별 개발 일지에 누적하고 마무리 전에 갱신한다.
