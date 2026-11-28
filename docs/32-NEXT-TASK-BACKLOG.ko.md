# 추가 개선·기능 과제 목록

> 2026-11-28 구현·main 반영: [53 기록](53-NATIVE-DEPTH-QUALITY-IMPLEMENTATION.ko.md)에 native reader/geometry·MPS 경계 정밀화·지점 초점 군집·저장/재편집·공개 Apple reference adapter를 연결했다. 앱139c5d1/CI66bf20d, Xcode26.3·27.2 전체 success(각 unit433통과/Flow1skip·LUT18·UI18), 직접 공통178·Python41. 기능/CI66bf20d를 main에 FF push했다. N2 시간/identity 안정화·N3 가시성/고해상도 alpha ROI·실사/열 인수·native 영상은 남아 있다.

> 2026-11-25 품질 개발 기획: [51 조사](51-DEPTH-QUALITY-RESEARCH.ko.md)·[52 실행 계획](52-DEPTH-QUALITY-DEVELOPMENT-PLAN.ko.md). 다음 구현은 동일 입력 native/공개 Apple filter 기준선과 NativePhotoDepthReader/DepthGeometry다. 이후 MPS 경계/신뢰·초점 안정화, 가시성 PSF, 고해상도 ROI 저장/복원, 실제 사진 인수 뒤 영상으로 진행한다. 이번 조사에서는35웹응답/Apple18·상위5repo·로컬16소스를 대조했으며 앱 추가 수정·성능/화질 측정·새 빌드/푸시는 없다.

> 2026-11-25 개발 시작: [50 1차 구현](50-NATIVE-DEPTH-FIRST-IMPLEMENTATION.ko.md)에 N1 자동 AI/사진 native 분리·preview 열 예산·메타데이터 저장을 반영했다. 공통164통과/190Swift 구문 검사, 새 iOS·실기기 검증/커밋·푸시 없음. N0의 기기 trace·SDK27.2와N2~N5는 후속이다.

> 2026-11-25 최신 우선순위: [49 네이티브 심도·렌즈 계획](49-NATIVE-DEPTH-LENS-PRIORITY.ko.md)의 N0 계측→N1 네이티브 촬영 계약/열 예산→N2 정합/초점 안정→N3 고해상도 경계·가림/PSF 합성을 먼저 진행한다. 사용자 확인한 기본 카메라 HEIC에 깊이 보조 이미지가 존재함을 직접 확인했다. 기존 기능·신규 AI 기본Off는 유지하며, 외부 추적 모델 추가보다 네이티브 심도 품질을 우선한다. 실제 발열/PhotoP A/B는 미검증이고 앱 수정 완료 상태가 아니다.

작성: 2026-11-17. 기준: `main` `004d869`. [29 개선 보고서](29-OPTIMIZATION-AND-ADVANCEMENT-AUDIT.ko.md), [30 최적화 구현](30-OPTIMIZATION-IMPLEMENTATION.ko.md), [31 기능·오픈소스 조사](31-FEATURE-AND-OSS-RESEARCH.ko.md)와 이전 단계 문서에 흩어진 남은 과제를 한곳에 모았다. 과제 정리 문서이며 이번에 앱 코드를 바꾸거나 새로 검증하지 않았다. 2026-11-18 사용자 결정(7절)을 반영했다.

> 2026-11-21 사진 전용 신규 AI 실험 개발: [47 구현 기록](47-EXPERIMENTAL-PHOTO-DEPTH-IMPLEMENTATION.ko.md). 두 옵션만 기본Off로 추가하며 기존 심도/AI/영상/live는 기본 기능을 유지한다. 새 영상 기억 추적·live 모델·실사 품질/기기 trace gate는 후속 과제다. 검증 앱19b343a를 두 SDK 전체회귀(native423통과/Flow1skip·UI18/각SDK) 후 main push했다. 자세한 결과·후속은47/08/당일 일지를 따른다.

> 최신 추가 개발 조사(2026-11-24): [48 소스·공식 문서 대조](48-ADDITIONAL-DEVELOPMENT-AUDIT.ko.md). P0는27.2 SDK 검증·공유/GPS 계약·실제 최종 모델 역할 표시·실기기 기준선, P1은촬영/후처리 큐·캐시/스케줄러·고해상도 ROI/매트 저장·E4 기억 추적이다. 아래 과거 표의 상태/금지 권고는 작성 당시 기록이며 최신 사용자 지시/현재 소스·48 판정이 우선한다. 이번에는 조사·문서만 갱신했다.

## 1. 현재 상태

| 항목 | 상태 | 근거 |
|---|---|---|
| 세션 시작 main | `d977858`(사용자 결정 문서 포함). 앱 소스 기준은 `241c1be` | 2026-11-18 checkout/fetch |
| 이전 자동 회귀 | `241c1be` 전체 CI 44056942568 성공: 공통 118, iPhone·Simulator 빌드, 네이티브 355개 중 354 통과·Flow 1 skip, UI 11, Python 31, 자산·번들 검사 | [30 보고서 4절](30-OPTIMIZATION-IMPLEMENTATION.ko.md) |
| 이전 문서 main CI | `004d869` 실행 44060529564 `success`(상태만 확인, 세부 집계는 열지 않음) | GitHub Actions |
| 이전 T00/F1/F2 자동 회귀 | `cf94605` 전체 CI44235743796 성공: iOS 단위370통과/1skip·UI14통과·portable129·Python31. T00/V07 CI 기준 충족, F1/F2 기기 인수 대기 | [33 기록](33-IOS18-FUSION-SCOPES.ko.md) |
| 후속 촬영 UI/심도 main 회귀 | `6b9b148` 전체 CI44505418877 성공: Xcode26.3·SDK/Simulator26.2, 네이티브377통과/기존 Flow1skip·UI14·portable134·Python31. 실제 기기 인수 대기 | [08의57절](08-STEP-VALIDATION.ko.md#57-main-촬영-ui심도-전체-ci-통과), [37 기록](37-CAMERA-DEPTH-QUICK-CONTROLS.ko.md) |
| 실기기 인수 | 없음. 심도 인수 데이터(100장·기기 trace·블라인드·권리)가 비어 `check_depth_acceptance.py`가 exit 2 | `docs/depth-acceptance/` |
| 구조 | `CameraService.swift` 1209줄, `CameraModel.swift` 1081줄. `CIKernel(source:)` 계열 2곳 | `git grep` |
| 구형 원격 브랜치 정리 | 후속 사용자 지시로 `claude/maintenance-guide`, `codex/ios-camera-foundation`, `claude/oss-feature-research-20261117`를 원래 tip의 원격 archive 태그 보존 후 삭제 | [36 백업/정리 기록](36-USER-DECISIONS-AND-BRANCH-CLEANUP.ko.md), 원격 heads/태그 역참조 확인 |

## 2. 우선순위 원칙

1. **실기기 인수가 먼저다.** 기능은 많지만 실제 iPhone 성능·화질 근거가 하나도 없다. 측정 없이 최적화 목표나 화질 우위를 정하지 않는다.
2. 이미 있는 자산을 활용하는 작은 기능(노출 융합, 스코프, 네이티브 API)을 큰 신규 기능보다 앞에 둔다.
3. SDR 계약·원본 불변·외부 코드 비복사 원칙을 바꾸는 과제는 사용자 결정(7절)을 받은 뒤 시작한다.

## 3. P0 — 실기기 인수와 검증 공백

2026-11-19 사용자가 검증 기기를 **iPhone 15 Pro / iOS 27.2**로 알려줬다. 사용자 제공 환경이며 원격 연결/실제 촬영 인수 완료는 아니다. 이 기기로 V02~V06·V08과 현재37 변경을 우선 검증한다. LiDAR·메인 카메라 고해상도 경로는 실제 렌즈/포맷 지원을 확인하고, 물리 Camera Control 버튼 시험은 이 기기에 적용하지 않는다. V01의 여러 기기 성능 비교는 별도로 미완료 상태를 유지한다.

| ID | 과제 | 완료 기준 | 필요한 것 | 출처 |
|---|---|---|---|---|
| T00 | **최소 iOS 18 상향**(전체 CI 성공, 기기 동작 별도) | `ios/project.yml` `deploymentTarget` 17.0→18.0, `CameraService.swift`의 `#available(iOS 18.0, *)` 분기 2곳(셔터음 억제) 정리, `CLAUDE.md`·README 표기 갱신. 전체 CI 성공 | CI(macos-15 Simulator 런타임이 iOS 18 이상인지 확인) | 7절 |
| V01 | 기기별 성능 기준선 | 최소 지원급·중간급·LiDAR Pro에서 프리뷰 p50/p95, 프레임 드롭, peak memory, 10분 열·전력을 `OSSignposter` 구간으로 기록 | 실기기 3종 이상, Instruments | 29 §6, 30 §5 |
| V02 | Optical Flow 방향·가림 | 가로/세로 이동, 전면 미러, 가로 화면에서 skip 없이 방향 fixture 통과 | 지원 실기기 | 29 A02, 30 §5 |
| V03 | 심도 화질 인수 | 동의 받은 100장, 블라인드 평가, 기기 trace, 권리 기록으로 `check_depth_acceptance.py` 통과 | 촬영 세트·평가자 | 28, `depth-acceptance` |
| V04 | 고해상도·저장 안정성 | 24/48MP 처리 시간·메모리, 저장 중 취소, 원본 hash 불변, 저장공간 부족 | 48MP 지원 기기 | 21, 30 §5 |
| V05 | 다중 피사체 매트 선택 | 터치한 instance 하나만 선택되는지 실제 장면 확인 | 실기기 | 30 §5 |
| V06 | iOS 26/27 분기 | 해당 SDK 빌드와 지원 기기에서 네이티브 추적·노출 우선·rect 분기 동작 확인 | iOS 26/27 SDK·기기 | 26, 27 |
| V07 | 저장 중 편집 잠금 UI 자동화(CI2개 통과) | 저장 진행 중 f값·프로필 변경 차단을 UI 테스트로 고정 | CI만으로 가능 | 30 §5 |
| V08 | 영상 실기기 | 오디오 동기, 손떨림 보정 화각·지연, 장시간 녹화 | 실기기 | 08 §31 |

## 4. P1 — 성능·구조 개선

| ID | 과제 | 방향 | 완료 기준 | 출처 |
|---|---|---|---|---|
| B02 | 추론 스케줄러 | 우선순위·기한이 있는 단일 스케줄러, 최신 프레임 하나만 대기 | 큐 대기·만료 작업 비율 감소(V01 기준선 대비) | 29 |
| B03 | 열·빈도 제어 | 모델·Flow·매트·구도 빈도를 각각 제어, 복귀에 hysteresis | 오래된 심도 표시를 늘리지 않고 fallback·깜박임 감소 | 29 |
| B06 | 고해상도 GPU 파이프라인 | CI→CGImage→Data→Metal 복사 제거, 2-slot 제한 파이프라인 | 타일 경계·색 일치 유지, 48MP p95·peak 감소 | 29 |
| B07 | 촬영·후처리 분리 | 촬영 busy와 후처리 busy 분리, 용량 제한 영속 큐 | 셔터 재입력 가능 시점 단축, 재시작 시 작업 복구 | 29 |
| B01 잔여 | 프리뷰 luma 생성 | 남은 CPU 경로(CGImage 생성·재래스터화)를 GPU나 저빈도로 | frameQueue CPU·할당 감소 | 29, 30 |
| S01 | `CameraService`·`CameraModel` 분리 | 촬영·프리뷰·심도 조정 단위로 점진 분리. 직렬 queue·revision·GPU 소유권 계약 유지 | 기존 테스트 전부 통과, 파일당 책임 축소 | 29 C08 |
| S02 | `CIKernel(source:)` 2곳 교체 | 사전 컴파일 Metal 커널로 | 동일 입력 출력 일치 테스트 | 29 C08 |
| S03 | 현장 지표 | MetricKit 수집(이미지·사용자 데이터 제외)으로 실사용 hang·메모리 경고 확인 | 개인정보 없는 집계만 저장 | 31 §3 |

## 5. P2 — 화질·AF·사용성

| ID | 과제 | 방향 | 출처 |
|---|---|---|---|
| C01 | 머리카락·안경 경계 | 불확실 영역만 고해상도 재추론. ViTMatte·MODNet 비교 PoC(가중치 출처 확정 후) | 29, 31 §5.5 |
| C02 | 보케 샘플 배분 | 픽셀 수가 아닌 CoC·경계·GPU 예산 기준 | 29 |
| C03 | 노출 변화 안정성 | AE·조명 변화 정규화, 장면 컷은 즉시 폐기 | 29 |
| C04 | 눈 AF·추적 유지 | 눈 우선/눈 고정 구분, 추적 실패 시 정지·재선택 | 25, 29 |
| C05 | 광학 AF와 가상 초점면 일치 | 하나의 대상 ID·좌표 계약 | 29 |
| C06 | 보관함 확장 | 파생 index·썸네일·페이지 조회·손상 항목 안내 | 29 |
| C07 | 취소·중단 복구 통합 | LUT export·장노출·재편집 pending 정책 통일 | 29 |
| C09 | 실측 PSF | 실제 점광원 촬영으로 보케 형태·광량 보정 | 28 |

## 6. P2~P3 — 신규 기능

상세 근거와 오픈소스 판정은 [31 조사](31-FEATURE-AND-OSS-RESEARCH.ko.md)를 따른다.

| 순위 | ID | 기능 | 구현 방식 | 핵심 위험 |
|---|---|---|---|---|
| 1 | F1 | 브래킷 **노출 융합**(코드·CI 확인, 기기 인수 대기) | 기존 3장 브래킷에 Metal 융합 추가. 외부 의존 없음 | 고스트. 정렬 실패 시 거부 |
| 2 | F2 | **스코프**(코드·CI 확인, 기기 인수 대기): 파형·RGB 퍼레이드·벡터스코프·False color | `Monitoring.metal` 확장. OpenPocketCine(Apache-2.0)은 구조 참고 | SDR 프리뷰 분석임을 표기 |
| 3 | F12 | **위치 태깅, 기본 활성화**(결정) | 위치 권한(사용 중) 문구 추가, 첫 촬영 전 권한 요청. 허용/유효 위치가 있으면 생성 시점에 태깅, 거부 시 위치 없이 촬영. 설정 끄기 제공. **공유 사본은 위치 제거, 원본 사진 내보내기는 기록된 위치 보존**. 원본 사후 수정 금지. 사진·영상·Photos 경로별 API 확인 필요 | 공유/원본 경로 분리·정확도·오래된 위치 처리. 현재 권한 요청·위치 수집·제거 공유 사본 코드 없음 |
| 4 | F3 | **Camera Control** | `AVCaptureControl`(iOS 18.0+). T00 이후 분기 불필요 | 하드웨어 버튼은 iPhone 16 이상만 |
| 5 | F4 | 편집본 **EXIF·ICC 처리·품질 우선 SDR 출력** | ImageIO. JPEG·SDR HEIC 등 지원/품질 비교 후 적합한 형식 선택. 원본은 재압축하지 않음. **HDR 게인맵은 생성·보존하지 않음**(결정) | 파생물 실제 색/방향/크기에 맞는 메타데이터, 위치 제거 공유본/원본 내보내기 구분. 최고 압축 품질과 무손실을 혼동하지 않음 |
| 6 | F8 | 미적 점수로 **추천 컷** | `CalculateImageAestheticsScoresRequest`(iOS 18.0+) | 점수는 제안일 뿐임을 표기. 시뮬레이터 실행 여부 미확인 |
| 7 | F5 | **포커스 스태킹** | 수동 초점 브래킷 + 정렬 + 피라미드 병합 자체 구현 | 렌즈 호흡에 따른 배율 변화, 메모리 |
| 8 | F13 | **사용자 촬영 프리셋**(C1~C3식) | 노출·포맷·룩·가이드 조합 저장 | 장치별 지원 차이 처리 |
| 9 | F9 | 인터벌·별궤적 | 장노출 스태킹과 결합. starlapse(MIT) 참고 | 백그라운드 촬영 불가 |
| 10 | F10 | 자동 수평·원근 보정 | 소실점 자체 구현(논문 참고). `librectify`는 권리 불명이라 사용 금지 | 오검출 |
| 11 | F11 | 초해상·디지털 줌 화질 | iOS 26.0+ `VTSuperResolutionScalerConfiguration` 또는 Real-ESRGAN PoC | AI 생성 디테일은 원본 아님. 파생물로만. 1차 표기는 메타데이터·앱 내 공지로 결정. API/기기·모델 권리 검증은 별도 |
| 12 | F14 | 영상 LUT 굽기(SDR) | 녹화 후 파생 영상으로. 원본 영상 불변 | 처리 시간·발열 |

**제외(2026-11-18 결정)**: HDR 출력 전반(ISO 게인맵 생성·보존, `libultrahdr`, Log/HDR 영상), 서명·출처 증명(C2PA, `c2pa-ios`).

**사용 금지**: `hdrplus-python`(AGPL-3.0), `librectify`(빈 LICENSE), RMBG-2.0·MatAnyone·Depth Anything V2 Base/Large/Giant(비상업), `lensfun` 링크(LGPL-3.0·CC BY-SA 3.0). 근거는 [31 §7](31-FEATURE-AND-OSS-RESEARCH.ko.md).

## 7. 사용자 결정

2026-11-18 사용자 결정을 기록한다.

| 결정 | 결과 | 영향 |
|---|---|---|
| HDR 출력 | **도입하지 않음**. 파생물·영상 모두 SDR 유지 | F4는 EXIF·ICC·SDR HEIC로 축소, Log/HDR 영상 제외 |
| 서명(C2PA) | **제거** | F6 삭제 |
| 최소 iOS | **18로 상향** | T00 추가. F3·F8은 분기 불필요. F11(iOS 26+)만 분기 |
| 위치 정보 | **기본 활성화** | F12 순위 상향. 권한 거부 시 태깅 없이 촬영 |
| AI 처리 결과 표기 | **1차로 메타데이터에 표시 + 앱 내 공지**(후속 결정) | 실제 적용한 처리 종류를 파생물에 기록. 사진 픽셀 워터마크/C2PA는 1차 범위에 없음 |
| 공유본 위치 | **제거**(후속 결정) | 원본을 수정하지 않는 별도 공유 사본 경로 필요 |
| 원본 사진 내보내기 위치 | **원본에 기록된 위치 포함/보존**(후속 결정) | 허용/유효 위치가 있을 때 생성 시점 태깅. 위치가 없으면 만들거나 원본을 사후 재작성하지 않음 |
| 출력 형식 우선순위 | **가능하면 품질 우선**(후속 결정) | JPEG 기본 유지라는 이전 제안은 확정안이 아님. 해상도·색·압축 품질/지원 포맷 검증 |
| 미병합 원격 브랜치 3개 | **archive 태그 백업 후 원격 삭제 완료** | [36 기록](36-USER-DECISIONS-AND-BRANCH-CLEANUP.ko.md)에 원래 tip/태그·복구 방법 보존 |

## 8. 권장 진행 순서

1. **T00**(최소 iOS 18), **V07**의 기반 회귀 확인. 두 항목의 CI 기준은 충족했고 구형3개 저장소 정리도 완료했다. 실제 기기 인수와 구분한다.
2. **V01** 기기 성능 기준선.
3. **F1·F2**. 외부 의존이 없고 기존 기능의 빈칸을 채운다. V01과 같은 계측으로 비용을 확인한다.
4. **F12**(위치 기본 활성화), **F3·F4·F8**.
5. **B07·B02·S01**. 촬영 반응성과 구조 부채를 줄인다.
6. **F5** 포커스 스태킹, 이후 V02~V06 결과에 따라 C 묶음과 B03·B06 범위 확정.

각 단계는 이전 관례대로 `docs/08-STEP-VALIDATION.ko.md`에 커밋·CI 실행 번호를 기록하고, 실기기 검증 전에는 완료로 표기하지 않는다.

## 9. 2026-11-18 진행 기록

아래는 초기 구현 세션 당시 기록이다. 후속 사용자 정책/브랜치 정리 결과는7·11절과36 문서를 따른다.

- 기준 main `d977858`, 작업 `codex/ios18-bracket-scopes-20261118`.
- 검증 소스 `cf9460505bd9211ba9afbfad974c6419fcc569db`, 전체 [CI44235743796](https://github.com/MetaParodica/PhotoP/actions/runs/44235743796) **success**. macos-15 / Simulator26.2 확인.
- T00 최소18.0과 V07 실제 저장/취소 잠금 자동화2개의 CI 완료 기준을 충족했다. 실제 카메라/저장 안정성 인수와 별개다.
- F1: 원본 픽셀 정렬 보정·모호성/고스트 거부·Metal SDR JPEG·원본 hash 불변/별도 레시피. 최대12.6MP, 서브픽셀/회전 미지원. 코드/CI는 확인했고 실제30세트·메모리·지연·화질은 대기다.
- F2: 파형·RGB 퍼레이드·벡터스코프·False color와 SDR 프리뷰 분석 계약. 코드/CI는 확인했고 실제 프리뷰 p95·메모리·색/가독성·영상 동시 출력은 대기다.
- F12는 공식 Apple API 본문이 현재 환경 proxy403으로 차단되어 구현 전 확인을 수행하지 못했다. 구현 보류이며 기본 켜기/거부 시 위치 없이 촬영/원본 생성 때 태깅 결정은 유지한다.33 문서의 후보 API 점검표를 먼저 확인한다.
- 새 외부 소스 복사·이미지·폰트·오디오·통신·모델·의존성 없음. 원격 정리 대상3개 브랜치는 삭제하지 않았다.
- 단계별 소스/실행/실패와 수정은08 문서46~53절, 현행 구현·인수 범위는33 문서를 따른다.

## 10. 추가 결정 사항 검토 보고

2026-11-18 [35 추가 결정 필요 사항](35-PENDING-DECISIONS.ko.md)에 작성 당시 미결정2건과 추가 제안3건을 구분했다. 이후 사용자가 AI 표기·위치 공유/원본·품질 우선 정책과 구형 브랜치 정리를 결정했다. 당시 권장안을 현행 미결정으로 오인하지 않도록35 상단에서36 기록으로 연결한다. 실기기/자료 확보는 인수 준비 과제로 남는다. F12 API 확인과 성능/구조 상세 설계는 불필요한 별도 승인 항목으로 늘리지 않는다.

## 11. 후속 사용자 결정·브랜치 정리

- [36 결정·정리 기록](36-USER-DECISIONS-AND-BRANCH-CLEANUP.ko.md)에 확정 정책과 원래 tip/원격 archive 태그3개를 기록했다. 열린 PR 없음, 대상별 독자 커밋1개를 보존했고 atomic push와 SHA lease로 브랜치3개만 삭제했다. 원격 재조회에서 삭제/백업 일치와 main `2c1a7b3` 보존을 확인했다.
- AI 처리 표기·공유 위치 제거·원본 내보내기 위치 보존·품질 우선은 **구현 기준**이다. 이번 작업에서 새 앱 동작이나 iOS 테스트를 추가한 것은 아니다. F12/F4 등에서 경로별 API·원본 불변·색/품질/메타데이터 회귀를 검증해야 한다.

## 12. 후속 촬영 UI·심도 조작 변경

- [37 구현 기록](37-CAMERA-DEPTH-QUICK-CONTROLS.ko.md): 박스형 뷰파인더·설정 패널1.5배·PRO 첫 f값/간편 심도·작은 전경 CoC 합성 변경. AI 구도 추천/코치/자동 리뷰는 사용자 요청으로 임시 중지하고 수동 가이드·심도 AI는 유지한다.
- portable134·Python31·Swift 구문165파일은 확인했다. Xcode 빌드·새 네이티브/UI 회귀·실제 기기 중/원거리 전경 품질·열/지연·셔터음 인수는 대기다. 기존 V01~V07 인수 완료를 대신하지 않는다.
- 2026-11-19 후속 main `6b9b148`의 전체 CI44505418877 성공으로 Xcode26.3·SDK/Simulator26.2 빌드·네이티브/UI 회귀를 확인했다. 첫 인물 위치 보조 스크롤 오판/수정은08의56절에 남겼다. iPhone 15 Pro/iOS27.2 실제 기기 품질·열/지연·셔터음과 V01~V08의 실기기 범위는 여전히 대기다.
- 셔터음은 기존 공식 지원 검사/매 촬영 요청 자동 무음을 유지한다. Apple 공식 문서의 기기·지역 제한을 확인했고 지원하지 않는 환경의 강제 무음을 완료로 표시하지 않는다.

## 13. 2026-11-19 카메라 앱·카메라 비교 제안

- [38 비교 보고서](38-CAMERA-APP-AND-CAMERA-FEATURE-COMPARISON.ko.md): Leica LUX·Halide·ProCamera·ProShot·Blackmagic·Focos·ReLens7개 앱과 Sony/Canon/Nikon/Fujifilm/Leica5개 카메라의 공식 기능을 현재 소스와 대조했다. 마케팅 소개·코드 확인·독립 화질 검증을 구분하며 새 제품 결정/앱 구현 완료가 아니다.
- 우선 현재37 변경의 Xcode/기기 인수(Q0)와 확정 출력/위치/AI 표기 계약(Q1=F4/F12)을 완료한다. 이어 **U1 촬영 C1–C3(F13), U2 간편 메뉴, U3 독립 수평계, U4 선택 초점 위치 확대**로 조작을 줄이는 안을 권장한다.
- 심도는 **D1 AF/가상 초점 대상 통합(C04/C05), D2 깊이/불확실 영역 보기(C01/C02), Q2 고품질 출력·촬영/후처리 분리(B06/B07)**를 우선한다. 고해상도 해상도 유지와 동일 합성 샘플 품질은 다르다는 현재 한계를 확인했다.
- 이후 가림 시 대상 유지(D3), 깊이 브러시/Undo(D4), 가상 렌즈 정합(D5), WB 보정(U5), Camera Control(U6=F3), 보관함(U7=C06/C07)을 검토한다. RAW 현상(Q3), 스태킹/인터벌(Q4=F5/F9)은 장면별 PoC 후 판단한다. 상세 효과·난이도·인수 기준은38의6~8절을 따른다.
- **AI 구도 추천/코치/자동 리뷰는 임시 중지**다. 기존6절 F8 등 AI 추천 확장 후보도 현재 권장 진행 묶음에 포함하지 않는다. 독립 수평계·AF/심도 개선을 이유로 추천 기능을 다시 켜지 않는다. HDR/Log/게인맵/C2PA 제외·카드별 룩 예시 중지는 유지한다.


## 14. 사진·영상 공통 심도 후속 인수와 고도화

[39 조사](39-VIDEO-DEPTH-AND-TRACKING-RESEARCH.ko.md) → [40 사전 계획](40-VIDEO-DEPTH-IMPLEMENTATION-PLAN.ko.md) → [41 구현](41-VIDEO-DEPTH-IMPLEMENTATION.ko.md)을 따른다. 선택 물체/인물/얼굴 추적·AF-C 추종/잠금 보존·영상 프리뷰·별도 심도 MOV/recipe·보관함 편집/취소/원본 비교는1차 구현했다. 검증 소스 f140234를11월20일 main에 반영했고 Xcode26.3 전체·26.6 UI CI가 성공했다. 검증/게시 상태는08의59절과11월20일 일지를 따른다.

| 순서 | 후속 과제 | 확인할 내용 |
|---|---|---|
| 1 | iPhone15Pro/iOS27.2 인수 | 실제 미리보기/촬영, 근·중·원거리 전경/머리카락/가림/빠른 팬,4K·HEVC·AAC 음성 동기·지속 메모리/열/속도와 취소/용량 부족 |
| 2 | EfficientTAM Core ML PoC | 고정된 모델 변환, bounded memory, 교정 탭·가림 뒤 대상 기억을 현재 Vision 추적과 비교. 저자 iPhone15 성능 소개를 자체 실측으로 사용하지 않음 |
| 3 | 시계열 깊이/경계 | Video Depth Anything Small streaming·scale/shift 정합, MatAnyone/RVM/SAM 비교, 깜빡임과 경계 spill 정량 평가. 상대 깊이를 단순 평균하지 않음 |
| 4 | native Cinematic | 실제 input/format 지원·AF mode 예외·녹화 중 f값 변경 금지·다중 depth track 보존/편집 어댑터부터 확인 |
| 5 | 편집/출력 운영 | 시간별 편집 정확도·결과 구분 UX, 중단 후 재개·저장 공간 예측/파생물 관리,10비트 SDR 파생 출력 검토 |

현재 파생 영상은8비트 SDR이며 원본은 변경하지 않는다. native Cinematic/새 시계열 모델 통합·실기기 경쟁 화질 우위는 완료로 표시하지 않는다. AI 구도 추천/코치/자동 리뷰 중지와 HDR/Log/C2PA 제외 정책은 유지한다.


## 2026-11-20 차세대 심도 후속 — 최신

[감사42](42-COMPUTATIONAL-DEPTH-AUDIT.ko.md)·[계획43](43-COMPUTATIONAL-DEPTH-PLAN.ko.md)·[13항목 구현 보고44](44-COMPUTATIONAL-DEPTH-IMPLEMENTATION.ko.md)를 따른다. 기존29/30/41의 기능을 새로 만들었다고 집계하지 않는다. source **77fa25f**를 Xcode26.3/26.6 두 전체 CI로 검증하고 main에 push했다(각 native409중408통과/Flow1skip·UI17·portable150·Python34). 정확한 URL/범위는08·44·당일 일지를 따른다. 실제 품질 인수는 미완료다.

외부 AI의 최신 제품 결정은 [46 실험적 기능 기획](46-EXPERIMENTAL-AI-DEPTH-PLAN.ko.md)을 따른다. 기존 심도/AI/추적/64MP/편집은 기본 기능과 기존 설정을 유지하고 **신규 외부 AI 기능만 실험실 기본Off·설정 활성화**로 추가한다. 신규 기능은 사진/저장영상/라이브 독립 지원하며 사진용부터 제공한다. 전체 실사 품질 인수와 실험 공개의 기능 검증을 구별한다. 이 결정은 현재 기획이며 모델/설정 구현 완료를 뜻하지 않는다.

| 우선 | 실제 남은 작업 | 확보한 근거/범위 |
|---|---|---|
| P0 | 실제100장·10종 영상/기기 trace/3명 blind 인수 | 새 Metal PSF·far-only fill·color-line 매트·영상 등록·editor 자동 회귀와 별개. 두 evidence gate 실제자료0/exit2 |
| P0 | neural matte ROI/경계 품질 비교 | 기존 Vision+제한 RGB 보정만 앱에 있음. alpha 합성 MAE 실제 구버전0.0983785→0.0147567, 실제 모발/유리 개선 미입증. 최신45의 MatAnyone 2/Swift 저수준 Float alpha·선택 인물 seed를 독립 비교 |
| P0 | streaming temporal 모델 고정 상태 CoreML PoC | VDA Small 실제116MB/SHA·29M tensor값 확인,32-frame cache 구조. 앱은 기존 모델+등록 검증 flow/affine |
| P1 | 신규 외부 AI만 실험실·사진부터, EdgeTAM 전체 masked 추적 후속 | 최신46: 기존 심도·AI·추적·64MP/편집은 기본 유지, 신규 실험 항목만Off·사진/영상/라이브 독립. 새 photo mask/매팅부터 제공하고 memory 추적은 별도 옵션. 45의빈 슬롯/FP16 parity·기기 검증 유지. EfficientTAM은 기존 변환/CPU 참조 차선 후보 |
| P1 | 실측 광학 PSF·선택 색수차/구면수차·난해한 occlusion | shared Metal/CPU gather 근사·독자6스타일은 구현. 경쟁 렌즈 실측 복제 아님 |
| P1 | priority inference scheduler·thermal fairness/p95 | single-job/reuse/취소·live0.75초 stale 조기 폐기 구현, 전역 lock 우선순위는 미구현 |
| P1 | 10bitSDR reader/pool/HEVC Main10/색 검증 | 현8bitSDR 유지, HDR/Log/gainmap/C2PA 금지 유지 |
| P2 | C1~3/빠른 설정/독립 수평계/확대 UX | 기존38 비교표와 현재 미구현을 먼저 대조. 심도 P0보다 우선하지 않음 |

사진 brush는 base 지도·scale을 유지하는 v4 recipe이며 기존v2/v3 읽기/교정 해제를 지원한다. 영상 intent v2는 focus/reciprocal-f 보간을 명시하고 v1 hold를 유지한다. 원본 bytes·hash·공유 위치 정책을 바꾸지 않는다. metadata/위치 F12 등의 기존 미완료 정책도 이 심도 구현으로 완료했다고 간주하지 않는다.


## 2026-11-24 추가 개발 조사 — 현행 우선순위

[48 보고서](48-ADDITIONAL-DEVELOPMENT-AUDIT.ko.md)와 [근거 JSON](research/2026-11-24-additional-development-sources.json)을 따른다. 원격main7f0f6c0/앱19b343a 기준이며 새 원격 커밋은 없었다.

- **A:** 공식27 전용 runner의 Xcode27.2/SDK27.2를 실제 CI에 연결, 기기 계측과 분석/최종 합성 모델 역할 표시 정합을 확인한다. 기존26 회귀와 최소18을 유지한다.
- **B:** 원본 공유의 GPS 제거 보장·명시적 원본 내보내기·생성 시 위치 태깅을 완성한다. 후처리가 촬영 busy를 잡는 구조는 촬영ID/설정 스냅샷·영속 큐·제한 모델 캐시와 함께 개선한다.
- **C:** NN288×512/저장512 상한과48MP의 샘플 쌍16→8을 구별한다. ROI 고해상도 분석은 매트 patch/피라미드 저장·복원·기존 recipe 호환과 동시에 개발한다. JPEG/SDR HEIC는 실제 품질/메타데이터/처리 비용으로 선택한다.
- **D:** 기존 선택ID/좌표/AF bridge를 재사용해 새 EdgeTAM memory/MatAnyone2 영상 alpha(E4), 별도 라이브(E5), 정식 실사/trace 인수(E6)로 진행한다. VDA streaming은 별도 깊이 PoC이며 mask/alpha를 깊이로 취급하지 않는다.
- 기존 심도/AI·사진/영상/live/편집은 기본 제공, 신규 모델만 실험실Off, 사진 독립·SDR·원본 불변·품질/AI/위치 정책을 유지한다. AI 구도 추천·HDR/Log/게인맵/C2PA를 다시 도입하지 않는다. 라이선스 종류로 조사 대상을 제외하지 않는 사용자 후속 지시를 유지하고 실제 복사/배포 조건·고지는 별도 기록한다.
- 이번에는 앱 수정/새 모델 복사·추론/새 native CI 없이 조사했다. 현재 빈 인수 gate는 사진0장·영상0종으로 직접 실행exit2이며 기존19b CI success는 상태 조회로만 재확인했다. 이번 문서는 미커밋·미푸시다.
