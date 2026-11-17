# PhotoP 최적화·고도화 개선 보고서

2026-11-17 통합 메모: 사용자 요청으로 이 보고서와 기존 심도·AF 개발분을 main 반영 범위에 포함한다. 아래 `dc75be6`/미병합 표기는 조사 당시 기준이다. 보고서의 최적화 제안은 개발 완료 항목이 아니며 전체 회귀 실패·실기기 인수 대기 상태를 유지한다.

조사 기준: 2026-11-16 세션, `codex/depth-phases-20261116`의 `31daead`. 원격 main은 `dc75be6`으로 최신 심도 변경이 아직 병합되지 않았다. 코드·실제 Actions 로그를 대조한 조사이며 앱 소스 수정이나 새 성능 실험을 수행한 보고서는 아니다. 기존 미커밋 문서 변경은 보존했다.

## 1. 판단

우선순위는 **전체 회귀 복구 → 실기기 계측 → 프리뷰/추론 최적화 → 고해상도 처리·촬영 반응성 → 경계 화질·AF 고도화**다. 기능 수를 늘리기 전에 실패 재현과 기기별 처리 예산을 확보하는 편이 현재 사용자 체감 개선에 유리하다.

아래의 코드상 반복 작업은 최적화 후보다. 각 항목이 실제 iPhone에서 차지하는 시간·전력은 아직 계측하지 않았으므로 예상 배속이나 발열 감소율을 확정하지 않는다. Simulator 시간은 iPhone/Neural Engine 성능으로 사용하지 않는다.

## 2. 새로 확인한 검증 결과

| 대상 | 실제 결과 | 해석 |
|---|---|---|
| [심도 집중 CI43918075081](https://github.com/MetaParodica/PhotoP/actions/runs/43918075081), `9f23cea`, Xcode26.6 | iPhone SDK·Simulator 빌드, 자산/번들 검사 성공. 지정 XCTest39개 중38개 통과·1개 skip, 실패0 | 타일 halo/core 비교·큰 CoC 점광원·모델 추론/저장 심도 재편집 등의 지정 범위 성공. 전체 앱/UI 인수 성공은 아님 |
| Optical Flow 방향 검사 | `Failed to create motion flow estimator`로 skip | 벡터 방향의 실제 Vision 실행 검증이 남아 있다. 수학적 이력 워프 테스트 통과와 구분 |
| [최신 전체 CI43918582758](https://github.com/MetaParodica/PhotoP/actions/runs/43918582758), `31daead`, Xcode26.3 | Swift DEBUG/SDK 조건, iPhone·Simulator 빌드 성공. 테스트 프로세스 재시작 뒤 단위 테스트 단계12분 제한 초과 | 전체 회귀 실패. UI·후속 자산 검사는 실행되지 않았고 화면 수집 및 결과 업로드도 실패 |
| 전체 CI의 재시작 직전 | `FilmStyleLibraryTests.testUniqueOriginalProfilesWithReproducibleRightsAndHashes` 실행 중 이후 XCTest가 비정상 종료/크래시/시간 초과 후 재시작이라고 기록 | 종료 원인은 아직 특정하지 못했다. 이 테스트가 마지막으로 시작됐다는 사실만으로 메모리 부족이나 제품 코드 결함을 단정하지 않음 |
| 재시작 후 집계 | 301개·skip1·실패0이 로그에 있으나 전체 단계는 시간 초과 | 일부 재시작 구간의 집계를 전체 성공으로 합산하지 않음. 소스상 단위 테스트 함수344개와 전체 실행 완료를 대조해야 함 |
| 공통/자산 검사 | portable110·Python28 성공 기록 | AVFoundation 실카메라·Optical Flow·발열·전체 UI 성공을 뜻하지 않음 |
| 실기기 화질 인수 | 평가 manifest의 scenes/deviceRuns/blindReviews는 비어 있음 | 업계 최고·경쟁 앱 동급·출시 품질을 주장할 근거가 아직 없음 |

## 3. P0 — 먼저 해결할 검증·안정성 과제

### A01. 전체 회귀와 진단 자료 수집 복구

- **확인:** 최신 전체 실행에서 테스트 재시작·단위 테스트 시간 초과·Simulator Shutdown 상태의 화면 수집 실패·artifact zip 생성 실패가 함께 발생했다.
- **작업:** 해당 필름 룩 테스트를 독립 재현하고 `.ips`/XCTest 결과·메모리/CPU 기록을 보존한다. 값싼 계약 테스트와 대량 LUT 생성/고해상도 테스트를 분리하고 cold/warm 캐시를 명시한다. UI는 독립 job 또는 독립 결과 수집으로 앞 단계 실패가 모든 증거를 없애지 않게 한다.
- **진단 보강:** stdout/stderr를 별도 파일로 보관하고 결과 번들이 닫힌 후 업로드한다. 실패 시에도 확보 가능한 로그/이미지와 깨진 xcresult를 분리 수집한다. 단순 제한 시간 증가는 원인 분석을 대신하지 않는다.
- **완료 기준:** 최신 동일 소스의 전체 단위/UI suite가 끝까지 실행되고 재시작·누락·skip 사유가 보존되며, 반복 실행에서도 결과/실패 자료를 열 수 있어야 한다.
- **근거:** [workflow](../.github/workflows/ios.yml), [전체 로그](https://github.com/MetaParodica/PhotoP/actions/runs/43918582758).

### A02. 실기기 지원·품질 인수와 Optical Flow 검증

- **확인:** Simulator의 Vision Flow 생성 자체가 실패했고 테스트는 모든 `VNErrorDomain` 오류를 skip한다. 이는 실제 비지원과 요청/모델 구성 오류를 충분히 구분하지 못한다.
- **작업:** 알려진 비지원만 skip하도록 오류 분류를 좁히고, 다른 Vision 오류는 실패로 남긴다. 실기기에서 가로/세로 이동·좌표 방향·새 가림·장면 전환·전면 미러링을 검증한다. 실패 종류에 따라 세션 내 비활성화 또는 재시도 간격 증가를 적용한다.
- **지원 매트릭스:** 최소 지원급·중간급·LiDAR Pro에서 실제 센서 깊이/AI 대체/RAW·영상 상호 배제를 확인한다. iOS27 분기는27 SDK 빌드와 실제 지원 포맷/기기 시험을 별도로 수행한다.
- **완료 기준:** 지원 기기에서 flow 방향 fixture가 skip 없이 통과하고, 미지원 기기에서는 기존 프리뷰 유지가 확인돼야 한다. 기기별 장시간 촬영·원본 보존·취소·재개 증거를 확보한다.
- **근거:** [Flow 어댑터](../ios/PhotoP/Processing/DepthMotionEstimator.swift), [SDK 테스트](../ios/PhotoPTests/NaturalDepthTests.swift), [인수 계약](depth-acceptance/README.ko.md).

## 4. P1 — 반응 속도·발열·메모리 최적화

| ID | 현재 코드에서 확인한 지점 | 개선안 | 검증 기준 |
|---|---|---|---|
| B01 | `LiveDepthAnalyzer.current`가 프리뷰마다 CGImage 생성·RGBA 재래스터화·CPU luma 배열을 만든다. `field.bounds`는 valid 값 전체 정렬이며 analyzer와 renderer에서 반복 호출된다 | luma/움직임 검사를 GPU 또는 저빈도 분석 단계로 옮기는 대안을 비교. 모델 프레임별 정규화 범위·매트 CI 이미지·깊이 통계를 캐시하고 현재 유효성 마스크를 분리 | AI/LUT 색 계약과 움직임 안전 복귀를 유지하면서 frameQueue CPU·할당량·p95 지연 감소 |
| B02 | Core ML·매트·Flow·구도/리뷰가 단일 `NSLock`을 공유한다. 대기 순서·기한 정책은 없고 오래된 작업도 끝에서야 폐기될 수 있다 | 우선순위/기한이 있는 단일 추론 스케줄러, 최신 프레임 하나만 대기, 단계 사이 세대·만료 확인. 진행 중 동기 모델 실행의 강제 중단은 보장하지 않음 | 큐 대기시간/만료 작업 비율 감소, 촬영 시 이전 분석이 불필요하게 후속 매트/Flow까지 실행되지 않음 |
| B03 | 깊이 갱신 간격은 최소0.35초로 이론상 약2.9Hz 이하이며, `.serious`와 저전력의 composition 간격은 모두0.4초다. 소스 시각0.75초 후 결과는 만료 | 모델·Flow·매트·구도 빈도를 각각 제어하고 기기/열/지연 실측에 맞춰 해상도·PSF 샘플 수 조절. 복귀에는 hysteresis 적용 | 오래된 심도 표시를 늘리지 않고 fallback 시간 비율·깜박임·소비 전력을 함께 줄임 |
| B04 | 모델 입력 CVPixelBuffer를 매 추론 생성하고 CI 캐시도 매번 비운다. 매트는 최대8개 인스턴스의 전체 scaled mask를 순서대로 생성할 수 있다 | 입력 buffer pool, CIContext/중간 이미지 재사용을 계측. instance label에서 터치 대상ID를 찾은 뒤 해당 마스크 하나를 생성. Flow 비지원/일시 오류 구분 및 backoff | 다중 사물에서 선택 정확도를 유지하면서 추론당 할당·마스크 생성 횟수 감소. 캐시 추가 후 peak memory도 확인 |
| B05 | 외부 기술 LUT는 최초 SDR bake 후 ASCII `.cube`로 저장하고 재사용 시 원본·캐시 모두 다시 텍스트 파싱한다.65³ bake는 행별 `String(format:)`을 사용 | 허용된 프리셋의 사전 변환 또는 버전/hash가 있는 바이너리 런타임 캐시. CPU 기준값과 원본 `.cube`는 보존하고 GPU용 Float 데이터는 별도 경로 검토 | cold/warm 룩 선택 지연·메모리·파싱 시간 개선, 채널/도메인·색 오차/출처 검사가 동일하게 통과 |
| B06 | 고해상도 타일마다 CI→CGImage→RGBA Data→Metal buffer 복사 및 `waitUntilCompleted`가 발생한다 | CI/Metal 간 texture 전달 및 제한된2-slot 파이프라인을 비교. 완료 fence와 버퍼 소유권을 유지하고 타일 크기·동시 작업 수를 기기별 제한 | 타일 seam·원본 hash·색 일치·취소/저장공간 부족 테스트 유지,48MP p95·peak footprint·임시 디스크 계측 |
| B07 | `CameraModel.capture`는 원본 보존 뒤 효과 결과·Photos 저장까지 기다리는 동안 전체 busy 상태를 유지한다 | 촬영 busy와 후처리 busy를 분리. 원본 URL 기반의 용량 제한 처리 큐와 단계별 영속 job 상태로 연속 촬영 반응성 개선. Photos 재시도는 중복 저장 가능성을 별도 설계 | 셔터 재입력 가능 시점 개선, 처리 큐가 무한 증가하지 않음, 재시작·취소 시 원본/작업 대응 유지 |
| B08 | 편집기 `save()`는 f/초점/렌즈를 snapshot하지만 `.disabled(saving && saveTask == nil)`은 저장 task가 있는 동안 슬라이더/Picker를 잠그지 않는다 | 저장 중 편집 제어만 잠그거나 저장 snapshot과 다음 편집 draft를 명확히 구분. 취소 버튼은 계속 사용 가능하게 유지 | 저장 도중 f값/프로필 변경 시 파일 recipe와 사용자에게 표시한 저장 값이 일치하는 UI 회귀 |

주요 근거: [LiveDepthAnalyzer](../ios/PhotoP/Processing/LiveDepthAnalyzer.swift), [DepthField 통계](../ios/PhotoP/Processing/SoftwareDepthPolicy.swift), [추론 gate](../ios/PhotoP/Processing/OnDeviceInferenceGate.swift), [PreviewBudget](../ios/PhotoP/Processing/PreviewBudget.swift), [매트](../ios/PhotoP/Processing/DepthMatteRefiner.swift), [LUT compiler](../ios/PhotoP/Film/CompanyFilmLibrary.swift), [SDR bake](../ios/PhotoP/Film/SDRVendorAdapter.swift), [타일 처리](../ios/PhotoP/Processing/HighResolutionPhotoProcessor.swift), [GPU 대기](../ios/PhotoP/Processing/MetalLUTRenderer.swift), [촬영 흐름](../ios/PhotoP/Camera/CameraModel.swift), [편집 UI](../ios/PhotoP/UI/DepthResultLibraryView.swift).

메모리·크기 참고: 런타임 `CubeLUT.values`는 `SIMD3<Double>` 배열이다.65³ 배열은 요소 stride32 기준 약8.38MiB이며 파싱 중 문자열·Data·GPU 표는 별도다. Float 기반 표는 오차 검증 후 도입해야 한다. 현재 디스크의 모델 자산은 약48MiB, 외부 LUT22MiB, 기본 LUT4.7MiB다. 이는 소스 디렉터리 크기이며 IPA/App Store 다운로드 크기가 아니다. 모델 양자화는 별도 후보로 두고 경계 화질·실제 지연 비교 없이 바로 교체하지 않는다.

## 5. P2 — 화질·AF·사용성 고도화

| ID | 개선 과제 | 구체적인 방향·인수 |
|---|---|---|
| C01 | 머리카락·안경·유리·손가락 경계 | 최대384px 정지 매트/160px 라이브 지도는 미세 경계 정보에 한계가 있다. 불확실 영역만 고해상도 ROI 재추론/알파 보정하고 색 오염·배경 누출을 비교. 투명체·가려진 배경을 정확히 복원한다고 주장하지 않음 |
| C02 | 고해상도 보케의 품질 일관성 | 현재12.6MP 초과 시 레이어/PSF 쌍을16→8로 줄인다. 픽셀 수만이 아니라 CoC·깊이 경계·실제 GPU 예산에 따라 샘플을 배분. 큰 CoC 피라미드·Classic 캣아이의 광량/형태는 실제 점광원과 중심/주변부에서 평가 |
| C03 | 움직임·노출 변화의 안정성 | 현재 프리뷰 프레임은 이전 분석 결과와 luma 차이를 비교해 무효화한다. 카메라 이동뿐 아니라 AE/조명 변화도 영향을 줄 수 있다. 노출 변화 정규화·신뢰도·다음 프레임 전파를 비교하되 새 가림·장면 컷에서는 즉시 폐기 |
| C04 | 눈 AF·대상 유지·재획득 | 눈/얼굴 선택, 추적 실패 시 정지·사용자 재선택, AF-S/AF-C 및 AF-ON 동작을 통합. MF/사용자 AF·AE 잠금을 우선하고, 실제 선명도 확인 없이 녹색 성공 표시를 만들지 않음 |
| C05 | 광학 AF와 가상 초점면의 일치 | 하나의 대상ID/좌표 변환 계약으로 네이티브 미리보기·센서 AF·AI 지도·저장 사진을 연결. 전면 미러·가로/세로·aspect-fill crop·줌·렌즈 전환을 시험. 현재 네이티브27 추적과 소프트웨어 심도의 동시 사용 제한은 인수 후 해제 검토 |
| C06 | 보관함 확장과 신뢰도 안내 | 현재 보관함은 전체 폴더/recipe를 스캔한다. 파생 index·썸네일·페이지 조회·필터·손상 항목 복구 안내를 추가. 원본/센서 깊이/AI 추정/원본 비교/처리 중 상태를 짧게 구분하고 상시 로그를 다시 만들지 않음 |
| C07 | 취소·중단 복구 범위 통합 | 캡처 결과뿐 아니라 LUT export·장노출·재편집의 pending 정책을 통일. 현재 원본 보존/UUID 원자 저장 원칙을 유지하고 최근 작업·활성 작업·정상 결과를 삭제하지 않는 회귀 시험 |
| C08 | 렌더러·소유권 구조 정리 | deprecated `CIKernel(source:)` 경로를 사전 컴파일 Metal 기반으로 옮기는 방안을 검증. 카메라 모델1081줄·서비스1209줄을 촬영/프리뷰/심도 조정 단위로 점진 분리. 직렬 장치 queue·revision·GPU 완료 전 frame 소유권은 유지 |

추가 기능 후보는 **C1~C3 사용자 촬영 프리셋 → 초점 브래킷/스태킹 → 고스트 보정 노출 합성 → 전경 동작 기반 인터벌 촬영** 순으로 검토할 만하다. RAW 현상·HDR/Log·영상 LUT 굽기는 현재 SDR 계약과 별도 색/출력 파이프라인 과제다. 후처리 배경 실행과 백그라운드 카메라 촬영은 다른 제약이므로 항상 가능하다고 안내하지 않는다.

## 6. 실측 계획과 완료 기준

1. `OSSignposter`/Instruments 중심으로 캡처·대기·추론·Flow·매트·렌더·디코딩·JPEG·Photos 각 구간을 분리한다. 프레임 소스 시각→표시 지연과 심도 지도의 age도 별도 측정한다. 현재 소스에는 관련 signpost/MetricKit 수집이 확인되지 않았다.
2. 기기별 LUT만/심도만/심도+LUT+구도, 전·후면, 세로·가로, 저전력·열 상태,12/24/48MP를 측정한다. cold 모델/캐시와 warm 상태를 구분한다.
3. 지연 p50/p95, 프레임 간격/드롭, 추론 대기/실행 시간, 심도 fallback 비율, peak memory, 임시 디스크,10분 이상 사용 시 열/전력을 기록한다.30fps의33.3ms·60fps의16.7ms는 프레임 예산이지 현재 실측 결과가 아니다. 기존 계획의 전체 프리뷰 p95 150ms 목표도 실측 후 기기별로 확정한다.
4. 동의 받은 약100장부터 머리카락/안경·역광·야간·동물·유리·식물·전경·다중 인물·움직임을 평가한다. 동일 입력과 앱별 촬영 비교를 분리하고 실제 DSLR의 화각/거리를 맞춘 참조 및 블라인드 평가를 사용한다.
5. 최적화 전후 원본 hash·렌즈/f값 recipe·색 관리·타일 경계·가림·점광원 에너지·취소/저장공간 부족·재시작 복구를 회귀 검사한다. 평균 FPS만 개선하고 피부/경계/원본 보존이 나빠지는 변경은 채택하지 않는다.

## 7. 권장 실행 순서

- **1차:** A01/A02와 B08. 전체 회귀/실기기 실행 근거·저장 UI 일관성 확보.
- **2차:** 계측을 붙인 뒤 B01/B02/B04/B05. 프리뷰의 반복 계산·추론 대기·LUT 변환을 개선.
- **3차:** B03/B06/B07. 열 예산·고해상도 처리·촬영 후처리 큐 최적화.
- **4차:** C01~C05의 화질·AF, C06~C08의 사용성/구조 개선. 새 DSLR 기능은 안정된 기준 위에서 확장.

이 보고서의 우선순위는 현재 코드·검증 결손·사용자 체감 범위를 기준으로 정했다. 기기 계측 후 작업 순서와 목표를 조정하며, 미측정 개선율이나 출시 완료 일정을 제시하지 않는다.
