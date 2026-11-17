# 심도 Phase별 구현·테스트 반복 기록

2026-11-17: 사용자 main 푸시 요청에 따라 기존 개발분과 [29 개선 보고서](29-OPTIMIZATION-AND-ADVANCEMENT-AUDIT.ko.md)를 통합한다. 아래 “main 변경하지 않음/전용 브랜치” 원칙은 2026-11-16 개발 당시 기록이며, 최신 사용자 지시로 변경됐다. 전체 회귀 실패 및 실기기 인수 대기는 계속 추적한다.

후속 조회 결과: `9f23cea` 심도 집중 CI43918075081은 성공(지정 XCTest39개·skip1·실패0)했으나 Optical Flow는 Simulator 실행 불가로 skip했다. 최신 `31daead` 전체 CI43918582758은 단위 테스트 프로세스 재시작/12분 시간 초과와 진단 자료 수집 실패로 종료했다. 이전의 “진행 중” 기록보다 이 결과를 우선하며, 개선 우선순위는 [29 최적화·고도화 보고서](29-OPTIMIZATION-AND-ADVANCEMENT-AUDIT.ko.md)에 정리했다.

2026-11-16 KST. 기준 main `dc75be6`. 후속 사용자 요청에 따라 [24 계획](24-SOFTWARE-DEPTH-DEVELOPMENT-PLAN.ko.md)의 Phase0~7을 진행한다. 앞선1차 작업은 [27 보고서](27-AF-NATURAL-DEPTH-IMPLEMENTATION.ko.md)에 보존한다. 이 문서는 진행 기록이며 인수 전 완료를 선언하지 않는다.

## 원칙

- 단계별 코드 → 관련 자동 검사 → 실패 수정 → 회귀 검사 순서로 반복한다.
- 전용 `codex/depth-phases-20261116` 브랜치에서 실제 macOS CI를 확인한다. main은 변경하지 않는다.
- Linux 정책/픽셀 참조 테스트, iOS SDK/Simulator 검사, 실제 기기/경쟁 앱 품질 인수는 별개다.
- 실기기·동의 받은 평가 사진이 필요한 품질/성능 결과는 만들어내지 않는다.

## 단계 상태

| Phase | 구현 범위 | 상태·검증 |
|---|---|---|
| 0 | 모델/권리·기준 빌드·평가 입력 계약 | 모델 hash/권리 검사. 실제 macOS CI 실패를 단계별 수정 중. 실기기/경쟁 입력 대기 |
| 1 | CoC·광학 참조·가림·레시피 | signed CoC·해상도 비례·CPU PSF 참조·recipe v3 구현. SDK 실행 확인 중 |
| 2 | 매트·알파·경계색·배경 보완 | 선택 인스턴스/포함 매트·RGB 유도 알파·보수적 전경색 복원·로컬 배경 확장 구현. 실제 머리카락/안경 인수 대기 |
| 3 | AI/측정 깊이 융합·신뢰도·일반 사물 | 강건 affine 보정·측정값 보존·검증된 빈 영역 채움. 무보정 AI를 m로 해석하지 않음. 실기기 입력 대기 |
| 4 | 렌즈 프로필·점광원 | Natural/Portrait/Classic 공유 PSF·대칭/광량 보존·CPU 참조 검사. 실제 점광원 비교 대기 |
| 5 | 실시간 심도·시간 안정화·AF 연동 | AI 프리뷰·분석 단일 작업·공유 추론 게이트·시간 필터·Vision Optical Flow 이력 워프·움직임/만료 시 복귀·f값 즉시 반영 구현. SDK 방향 계약/실기기 성능 인수 대기 |
| 6 | 고해상도·사진 재초점·보관함·취소/복구 | 최대64MP 경로·사진 터치 재초점·f/프로필 편집·재시작 보관함·hash 검증·취소/중단 정리 구현. SDK/48MP 실기기 인수 대기 |
| 7 | 품질 평가·지속 사용·출시 게이트 | 증거 hash·실제100장·기기 trace p95·블라인드/법적 검토 게이트 구현. 실제 증거0건으로 **인수 불가** |

## Phase0: 기존 CI 오류

- [main 실행40045643158](https://github.com/MetaParodica/PhotoP/actions/runs/40045643158), job120726611625의 실제 SDK 로그를 조회했다.
- `IntelligentCompositionViews.swift`의 `[CGFloat]` 삼분할 배열에서 `[1 / 3, 2 / 3]`이 Int로 추론되어 exit65가 발생했다. 명시적 CGFloat 나눗셈으로 수정했다.
- 이 실패는 앞선 Linux97개 통과가 앱 SDK 빌드 성공을 뜻하지 않는 사례다. 이번 새 CI 결과를 확인한 후 다음 상태를 기록한다.

## Phase1~4: 첫 반복

- `2587c02`를 검증 브랜치에 게시했다. 새 실행43903880619는 macOS26 대기열 상태로, 성공/실패 로그가 아직 없다. 공식 macOS15 설치표의 Xcode26.3을 확인하여 기본 CI를 해당 조합으로 변경한다.26.6/27은 수동 선택을 유지한다.
- 공통 코어에 정규화·대칭 PSF/CPU 참조, 강건 affine 깊이 보정과 측정값 보존·빈 영역 융합, RGB 유도 알파·전경색 복원, 세대/움직임/만료 기반 시간 상태를 추가했다. 관련 테스트8개를 추가하여 portable105개 통과.
- 사진 파이프라인에 선택 인스턴스/포함된 인물 매트, 보수적 경계색 복원, 보정된 AI hole fill, Natural/Portrait/Classic의 공유 PSF 커널을 연결했다. recipe v3는 렌즈·원본 깊이 출처·매트와 hash를 보관하여 재처리 때 다시 추론하지 않도록 했다. SDK/실제 사진 인수는 아직 대기다.

## Phase5~6: 실시간·재편집 반복

- `07d1958`: AI 선택 시 실시간 심도 프리뷰를 하단에서 켤 수 있다. 원본→선형 심도→sRGB LUT/입자/마감 순서이며 AI/노출 분석은 원래 입력을 쓴다. f값/프로필은 모델을 다시 실행하지 않고 다음 렌더링에 반영한다. 실시간은8 depth 구간·최대160px 분석 지도와 축소 매트로 비용을 제한한다. 고해상도와 동일한 좌표·반경식을 쓰지만 샘플 수가 달라 픽셀 동일성을 주장하지 않는다.
- 하나의 추론만 진행하며 분석 결과는 소스 시각 기준0.75초 후 만료된다. 상대 깊이는 이전 결과를 affine 정렬한 후 안정된 RGB 영역만 필터링한다. 보정 실패는 이력을 폐기한다. 움직임/무효 초점·낮은 깊이 대비에는 심도를 표시하지 않고 원본/룩 프리뷰를 유지한다. 방향·렌즈·실행 세대 변경 시 초기화한다. 이는 optical-flow 추적을 대신하는 보수적 대체 경로다.
- 프리뷰는 현재 AI 깊이 소스에서만 켠다. 센서 사진 깊이와 AI 프리뷰가 같은 측정이라고 오인시키지 않는다. 네이티브27 추적은 metadata 좌표와 촬영 깊이 정렬을 인수하기 전까지 소프트웨어 심도와 동시 사용하지 않는다. MF/사용자 잠금을 심도 슬라이더가 변경하지 않는다.
- `5048940`: 앱 재시작 후 보관함을 열어 저장된 실제 사진을 터치하고 f/렌즈/원본 비교를 변경한다. 원본·depth/matte/LUT hash를 확인하며 저장은 새 UUID 번들이다. 처리 중 취소/비활성화는 타일 사이에서 감지하고 pending 파일을 정리한다. 하루 이상 지난 앱 소유 UUID pending 폴더만 복구 정리하며 정상 결과·원본·활성 작업·알 수 없는 폴더는 보존한다.
- 최대64MP·긴 변16384px를 유지한다.12.6MP 초과는8 구간/8 PSF 쌍, 이하16 구간/16쌍으로 비용을 제한한다. 모델/매트의 세부 해상도가64MP라는 의미는 아니다. 이미지 디코더/인코더 peak memory 및48MP 처리 시간은 실측 전이다.
- `6d22293`: 구도/사진 리뷰/AI 깊이/매트 추론을 공통 lock으로 직렬화하여 병렬 Vision/Core ML 경쟁을 제한했다. 캡처 원본을 보존한 후 앱이 비활성화되면 효과 처리를 취소한다.
- `4c3513e`: 큰 CoC를 미리 대역 제한하고 축소 피라미드에서 PSF를 평가한 뒤 복원한다. 고해상도의 고립된 샘플 모양 점광원을 줄이기 위한 경로다. 상수 보존·점광원 면적/광량·전체/타일 ROI 비교 XCTest로 검사한다. 실제 점광원 사진 인수는 별개다.
- `37fcbcb`: Apple 공식 [VNGenerateOpticalFlowRequest](https://developer.apple.com/documentation/vision/vngenerateopticalflowrequest)·[VNTargetedImageRequest](https://developer.apple.com/documentation/vision/vntargetedimagerequest)·[출력 포맷](https://developer.apple.com/documentation/vision/vngenerateopticalflowrequest/outputpixelformat) 본문을 직접 확인했다. 작은 동일 RGB 캔버스에 단일 flow 요청을 실행하여 이전 깊이 이력을 현재 좌표로 옮긴다. 영상 경계/새 가림·색상 불일치는 이력을 버리고 깊이 불일치도 혼합하지 않는다. 워프가 성공해도 원래 프레임 시각의 만료 기한을 늘리지 않는다. 실패/지원 불가는 기존 motion gate로 대체한다. 매트는 현재 분석에서 새로 추출하며 오래된 매트를 워프해 재사용하지 않는다.
- 이동/가림/잘못된 flow/같은 색의 깊이 급변 회귀를 추가하여 portable109개 통과했다. Vision의 실제 벡터 방향은 비대칭 RGB를 가로3·세로2px 이동한 SDK XCTest로 검증한다. Vision 자체가 실행 불가하면 해당 검사를 명시적 skip으로 남긴다. 그 경우 실제 동작 성공으로 주장하지 않는다. CPU-only Simulator 모델 계약과 실제 iPhone의 all compute units 성능을 구분한다.

## SDK 실패를 실제 로그로 수정한 기록

- 실행43906209605/job133435626156: macOS의 portable 대상에서 Foundation만 가져온 `CGRect` initializer가 해석되지 않았다. `FocusControlPolicy`에 조건부 CoreGraphics import를 추가했다.
- 실행43909758982/job133448140758: Swift6.2 계열에서 테스트의 긴 숫자 식 타입 추론이 시간 초과했다. 렌즈 계수/예상 반경을 명시적 Double로 분리했다. `0452e2d`에 반영했다.
- 실행43910963114(Xcode26.3)/43911330157(Xcode26.6)는 macOS portable 검사를 통과한 뒤 실제 iPhone SDK 빌드에서 CameraView 전체 modifier 식/실시간 luminance map 식의 타입 검사 시간 초과를 드러냈다. `13567b2`에서 화면 layout/presentation/reactions를 분리하고 luminance를 명시적 Float 단계로 변경했다. 수정본의 SDK 검사도 이어간다.
- 최신 SDK 빌드/Simulator 결과는 아래 후속 기록을 확인한다. 위 실패를 숨기거나 Linux 통과를 SDK 성공으로 대체하지 않는다.
- `13567b2`의 [실행43912801297](https://github.com/MetaParodica/PhotoP/actions/runs/43912801297)은 Xcode26.3/실제 iPhone SDK26.2 빌드에 성공했다. 현재 Simulator XCTest를 진행 중이다.26.6/SDK26.5는 별도 실행43912927523에서 검증한다.27 SDK의 성공으로 확대 해석하지 않는다.

## Phase7: 출시 인수 도구

- [평가 입력 계약](depth-acceptance/README.ko.md), [빈 manifest](depth-acceptance/manifest.json), `scripts/check_depth_acceptance.py`를 추가했다. Python28개, portable109개가 현재 통과한다.
- 실제100장·범주/동의·원본/PhotoP/경쟁 결과/평가 보고서의 hash, 세 종류 기기10분 trace·원시 지연 샘플 p95, 취소/원본/열 동작, 독립3인 블라인드 및 최종 권리/화질 승인을 요구한다. 샘플 없는 현재 게이트는 eligible=false/exit2이며 출시 인수는 대기다. CI의 validate-only는 입력 무결성 검사일 뿐 화질 통과가 아니다.
- 업계 최고/Leica 동급, 투명체 복원·정밀 머리카락 정답, 이동 정합/광학 흐름·실제 렌즈 PSF 실측·iOS27 SDK/실기기 성공을 주장하지 않는다. 센서 metric 보정과 AI 상대 깊이·추정 배경은 UI/recipe에서 구분한다. 기기별 성능 예산·영상/HDR/RAW 심도·눈 AF·포커스 스태킹/전체 DSLR 조사 목록은 별도 후속 과제다.
