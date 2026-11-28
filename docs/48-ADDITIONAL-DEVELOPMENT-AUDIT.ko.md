# 추가 개발 필요 요소 조사

> 2026-11-25 후속 사용자 결정: [49 네이티브 심도·렌즈 계획](49-NATIVE-DEPTH-LENS-PRIORITY.ko.md)이 개발 순서에 우선한다. 발열·아웃포커스/추적 불안정을 먼저 계측하고 네이티브 사진 심도 기반 자체 렌즈 렌더러를 집중 개선한다. 아래 E4/E5 모델 확대 권고는 그 뒤에 검토한다. 본문은11/24 조사 당시 기록으로 보존한다.

2026-11-24 KST. 원격 main `7f0f6c0ebaa80d38451238b8815e12e6d62199ea`, 앱 검증 소스 `19b343a` 기준. fetch 결과 새 main 커밋은 없었다. **이번 작업은 코드·공식 문서·상위 프로젝트 조사이며 새 기능 구현이나 실기기 성능 측정이 아니다.**

우선 개발할 것은 **27.2 SDK 검증, 공유·위치 계약 완성, 실제 사용 모델 표시 정합성, 촬영/후처리 분리, 고해상도 경계 저장/합성**이다. 이어 새 모델의 저장 영상 기억 추적(E4), 라이브(E5) 순으로 진행한다. 이미 있는 영상·라이브 심도를 다시 만드는 과제가 아니다.

[웹·소스 근거 JSON](research/2026-11-24-additional-development-sources.json)에 직접 받은 문서 URL·SHA256·크기·가용 OS·상위 revision·로컬 코드 발췌를 보존했다. 성공한 웹 응답36개(Apple DocC20개 포함), 실패 URL5개도 기록했다. URL 실패를 API 부재로 해석하지 않았으며 Photos/Cinematic의 실제 canonical URL을 다시 확인했다.

## 1. 현재 구현과 실제 남은 범위

| 영역 | 현재 main | 추가 개발/확인 |
|---|---|---|
| 기본 심도 | 센서/LiDAR·Depth Anything/Vision·사진/영상/live·기존 추적/AF·PSF/프로필·64MP·brush/키프레임/재편집 | 실기기 품질/처리 시간·열·중원거리/전경·가림 인수 |
| 신규 사진 실험 | 정밀 선택 EdgeTAM2모델, 인물 alpha MatAnyone2 6모델, 독립 기본Off·저장/복원·적용/복귀 표시 | 인물/비인물 거부·hair/유리/손 등 실제 자료, 역할별 표시·성능·고해상도 경계 |
| 신규 영상 실험 | 새 EdgeTAM video memory/propagator·MatAnyone2 시간 연결·streaming depth는 미연결 | E4 저장 영상부터 독립된 옵션으로 구현 |
| 신규 라이브 실험 | 사진 스위치는 새 영상/live 모델을 켜지 않음 | E5 별도 예산·프레임 시간·AF 우선순위·별도Off 옵션 |
| SDK | 기존26.3/26.6 전체회귀 성공 기록, 최소 iOS18 | 27/27.2 분기의 실제 컴파일·27.2 기기 동작·최소18 호환 확인 |
| 출력/위치 | JPEG 파생물, 원본 별도 보존, 심도 영상은 위치 메타데이터 비복사 | 위치 수집/생성 시 태깅·공유 사본 제거·명시적 원본 내보내기 완성 |

기존 CI44784405939/44784461745와 main 실행44789014833의 source19b343a·success를 이번에 상태 조회로 재확인했다. **이전 실행 결과**이며 이번에 native 테스트를 다시 실행한 것이 아니다. 당시 각 native424중423통과/Flow1skip·UI18·portable158·Python34 범위는 [47](47-EXPERIMENTAL-PHOTO-DEPTH-IMPLEMENTATION.ko.md)·[08의65절](08-STEP-VALIDATION.ko.md)을 따른다.

## 2. 우선순위와 완료 기준

| 우선 | 과제 | 구체적인 완료 기준 |
|---|---|---|
| P0-1 | **Xcode27.2 CI·기기 매트릭스** | SDK27 심볼을 실제 빌드, Simulator27.2에서 기존/신규 모델과 UI 회귀. iPhone15Pro/27.2 실제 AF·캡처 확인. 최소18 정책 유지 |
| P0-2 | **공유/원본/GPS 분리** | GPS가 있는 원본도 일반 공유본에서는 제거, 명시적 원본 내보내기는 보존. 거부/오래된 위치 처리, 생성 시 태깅·원본 hash 불변 |
| P0-3 | **실제 최종 사용 모델과 표시 정합** | 분석 성공/seed 사용/최종 합성 사용/대체됨을 구분. 최종 기여 없는 모델을 융합 적용으로 오인시키지 않음. 저장 재열기·JPEG credit·앱 안내 일치 |
| P0-4 | **실제 화질·성능 기준선** | 동일 입력 Off/각 옵션/두 옵션 비교·기기 trace 확보. 사진100장/영상10종/3명 blind의 기존 정식 인수 기준은 유지 |
| P1-1 | **촬영과 후처리 분리·영속 작업 큐** | 원본 보관 후 UI 촬영 대기와 처리 대기를 분리. 작업ID·설정 스냅샷·용량 제한·재시작 복구·중복 저장 방지·취소 원본 보존 |
| P1-2 | **모델 캐시·우선순위 스케줄러** | 모델 로드/추론/전송/합성/저장 시간을 분리 계측. bounded cache·취소 가능한 대기·기한 있는 live/사진/영상 작업. 사진 간 recurrent state 공유 금지 |
| P1-3 | **실제 고해상도 경계·품질 출력** | 불확실 ROI의 고해상도 alpha/보정·저장/복원·patch seam 확인. 48MP 샘플 품질/SDR HEIC 비교. 저해상도 alpha 확대를 고해상도 추론으로 표기하지 않음 |
| P1-4 | **E4 저장 영상 기억 추적** | 원본 PTS/음성/방향 보존, ID·가림/재등장·교차/컷/seek·memory reset·fallback·수정 replay 검증 |
| P2-1 | **E5 라이브·AF/가상 초점 정합** | 기존 선택ID·좌표·AF 잠금/수동 우선순위를 확장. 최신 프레임만 대기·유효기간/열 예산·놓친 대상에 오래된 효과 금지 |
| P2-2 | **보관함·간편 조작** | 썸네일/페이지 인덱스·손상 항목/실제 로딩 상태, C1–C3 촬영 프리셋·빠른 메뉴·원터치 재선택/원본 비교. 기존 LUT 프리셋과 구별 |

## 3. 소스에서 확인한 구체적인 공백

### 3.1 27.2를 선택할 CI 경로가 아직 완성되지 않음

현재 workflow는27이라는 입력은 있지만 `macos-26`에서 `/Applications/Xcode_27.app`을 찾는다. 이번에 직접 읽은 공식26 이미지의 Xcode 목록과27 전용 이미지의 목록은 다르다. 공식 `xcode-27` arm64 이미지(버전20261104.0337.1)에는 **`/Applications/Xcode_27.2.app`, iphoneos27.2, iphonesimulator27.2**가 명시돼 있다. hosted-runner 문서에서도 해당 label을 확인했다.

따라서27.2 선택·맞는 label·실제 `xcodebuild -version`/SDK 출력·`PHOTOP_CAMERA_SDK27` 조건을 연결할 수 있다. 사진/영상/live 지원 판정은 기기 activeFormat에서 계속 확인해야 한다. 문서에 도구가 있다는 사실은 실행기 배정/빌드 성공/15Pro 기능 지원의 증명이 아니다. SDK26 회귀를 유지하고 최소 iOS18을 자동으로 올리지 않는다.

소스: [.github/workflows/ios.yml](../.github/workflows/ios.yml), [CameraPlatformFeatures.swift](../ios/PhotoP/Camera/CameraPlatformFeatures.swift), [project.yml](../ios/project.yml).

### 3.2 원본의 일반 공유가 파일 URL에 직접 연결돼 있음

`CaptureReviewView`의 목록에는 원본도 들어가고, 공유는 `ShareLink(item: current)`로 연결된다. 전체 iOS 코드에서 CoreLocation/위치 권한 문구와 위치 수집 경로는 확인되지 않았다. **현재 모든 원본이 GPS를 가진다는 뜻은 아니지만**, 원본에 GPS가 있거나 향후 기본 위치 태깅을 구현하면 이 공유 경로에 제거 보장이 없다. 새 심도 영상의 whitelist 메타데이터 정책과 일반 원본 공유를 구분해야 한다.

개발 순서:

1. 공유용 별도 파일 생성과 `원본 내보내기` 동작/문구를 먼저 분리한다. 원본 파일은 수정하지 않는다.
2. 사용 중 위치 권한·사용자 끄기·시각/정확도/만료 정책을 구현한다. 거부되면 촬영은 계속한다.
3. `AVCapturePhotoFileDataRepresentationCustomizer.replacementMetadata(for:)`로 파일 생성 시 기존 메타데이터를 보존하면서 위치를 넣는 경로를 검증한다. 현재 `photo.fileDataRepresentation()` 호출과 연결할 수 있다. 이미 저장한 원본을 사후 재작성하지 않는다. 커스터마이저의 flattened-file 메타데이터 처리와 RAW/DNG 지원 범위를 같다고 가정하지 말고 형식별 실제 callback·원시 데이터 보존을 검증한다.
4. Photos의 `PHAssetChangeRequest.location`은 보관함 자산의 위치다. 이것만 설정하고 원본 파일에도 GPS가 있다고 간주하지 않는다.
5. ImageIO의 GPS/XMP 제외와 압축 데이터 복사 경로를 확인해 JPEG/HEIC/DNG별로 검증한다. DNG 등을 무손실로 정제할 수 없으면 조용히 원본을 공유하지 않고 지원되는 파생 공유/명시적 원본 내보내기를 구분한다. EXIF/ICC/방향·AI/룩 credit은 위치 제거와 별도로 유지한다.

소스: [CaptureReviewView.swift](../ios/PhotoP/UI/CaptureReviewView.swift), [PhotoStore.swift](../ios/PhotoP/Storage/PhotoStore.swift), [CameraService.swift](../ios/PhotoP/Camera/CameraService.swift). 이미 확정한 정책의 구현이며 사용자에게 GPS 기본값·공유 정책을 다시 결정받을 항목이 아니다.

### 3.3 두 실험의 분석 성공과 최종 합성 사용 역할이 같지 않음

`CaptureResultProcessor.render`는 정밀 선택 성공 후 `matte`를 저장하고, 인물 단계 성공 시 `matte`를 인물 결과로 교체한다. 이후 두 record가 모두applied면 양쪽 JPEG credit을 추가한다. [47](47-EXPERIMENTAL-PHOTO-DEPTH-IMPLEMENTATION.ko.md)에도 인물 alpha 우선이며 mask 융합 구현이 아니라고 기록돼 있다.

두 모델이 실제 실행돼 분석에 성공한 것과 두 매트가 최종 이미지에 함께 쓰인 것은 다르다. 이를 모델 미실행 오류로 단정할 수는 없지만, 사용자 표시/메타데이터에 **분석 성공·seed·최종 합성·대체됨** 역할을 추가할 필요가 있다. 인물 결과가 충분하면 일반 선택 재추론을 생략하거나, 실제 seed로 공유하는 경로를 비교한다. 실패 시에만 다른 모델을 실행하는 구조도 후보이며 다중 인물/부분 mask를 검증해야 한다.

기존v2/v3/v4·기존 결과의 재편집/과거 provenance 읽기를 보존한다. 양성·비인물 거부 검사 외에 **두 옵션 모두 성공/한쪽 실패/중간Off/재열기** 조합을 추가한다. source-level 데이터 흐름 분석 결과이며 이번에 두 옵션의 새 런타임 재현을 수행한 것은 아니다.

### 3.4 촬영 busy가 긴 후처리와 Photos 저장까지 유지됨

`CameraModel.capture`에서 busy=true 후 `renderCaptureResults`와 `PhotoStore.addToPhotos`를 모두 기다린 다음 false로 돌린다. `canCapture`는 `!busy`를 요구한다. 코드상 다음 촬영이 후처리에 묶여 있다. 실제15Pro에서 몇 초인지는 측정하지 않았다.

단순히 busy만 먼저 풀면 `latestOriginals/latestRendered*`가 다른 촬영과 섞일 수 있다. 먼저 촬영ID·원본/룩/f값/초점/실험 설정 스냅샷을 가진 영속 작업을 설계해야 한다. 원본 보관·Photos 원본 저장·파생 처리/저장의 상태를 구분하고 재시작/중복 저장/저장공간 부족/앱 비활성화를 검사한다. 큐가 가득 찼을 때는 명시적인 대기 상태를 제공한다.

### 3.5 신규 사진 모델 로드·추론 대기·정적 반복의 비용

신규 selector는 호출 때 새 인스턴스를 만들고 모델을 보유하며, portrait 경로는 매 사진 `MatAnyoneCoreML`6모델과 새 engine을 만든다. 정적 warmup10회도 고정이다. 반면 기본 live analyzer는 estimator를 재사용하고 기존 thermal/low-power budget·stale 폐기를 이미 가진다. **앱 전체에 캐시나 열 대응이 전혀 없다고 평가하면 틀린다.**

신규 사진 경로에 대해 다음을 계측/개선한다.

- 불변 MLModel 그래프와 작업별 state를 분리해 제한된 owner/cache로 재사용. 새 사진마다 memory bank는 초기화한다.
- 모델 로드·seed·각 추론·8MiB급 FP32 head 전송/CPU 계산·합성·JPEG·저장을 구분 계측한다. `.all`은 ANE 실행 증거가 아니므로 MLComputePlan/기기 trace로 확인한다.
- 현재 공통 gate는 NSLock이다. live 쪽 try-lock/drop과 오래된 결과 폐기는 있지만 작업 우선순위·취소 가능한 대기·기한 스케줄러는 없다. 실행 중인 CoreML 호출을 임의 선점할 수 있다고 가정하지 말고 모듈/반복/프레임 경계에서 양보한다.
- warmup0/1/3/10을 실제 alpha 품질·성능으로 비교한다. 반복을 줄였다는 이유만으로 고품질 사진 개선이라고 선언하지 않는다.
- 검증된 CPU mask-head는 기준/fallback으로 유지한다. GPU/다른 graph 최적화는 점수·후보 선택·finite/영역·이미지 비교를 통과한 경우만 채택한다.

### 3.6 고해상도 출력과 고해상도 경계는 별도 문제

MatAnyone2Kit의 bundled NN은288×512 고정이다. PhotoP는 최대512px 매트를 저장하고 **`DepthMatteSurface.decode`와 `loadSession`도512 상한**이다. 더 큰 분석만 추가하고 저장 때512로 줄이면 재편집에서 고해상도 개선이 사라진다.

기존64MP 타일 출력은 유지한다. 새 실험용으로 불확실 경계의 halo ROI 재분석·겹침 합성·alpha patch/피라미드 저장과 복원을 함께 설계한다. 전체48MP에 현재7채널Float 포맷(28bytes/px)을 단순 확장하면 sidecar만 약1.34GB다. 이것은 디스크 데이터 계산이며 앱 peak memory 실측값이 아니다. 경계 alpha와 필요한 보정만 제한 저장하고 원본/좌표/hash/이전 recipe 호환을 유지하는 쪽이 적절하다.

또한 현재12.6MP 초과 사진은 합성 sample pairs를16→8로 줄인다. **해상도는 유지되지만 샘플 품질은 동일하지 않다.** 품질 우선 preset·CoC/경계 기반 샘플 배분·시간/열 예산을 실제48MP로 비교한다. 고해상도 기능이 없다는 평가도, 고해상도 모발 품질을 확보했다는 평가도 현재 근거로는 맞지 않는다.

### 3.7 보관함과 작업 관측

현재 심도 목록은 UUID 폴더의 recipe를 전부 읽고 정렬하며 페이지/썸네일 인덱스가 없다. 원본 hash 전체를 목록에서 모두 계산하는 구조는 아니며 선택 후 loadSession에서 검증한다. 목록 로딩·손상 항목 표시와 메타데이터 인덱스, pending 원인/재시도/취소를 보강한다. MetricKit은 로컬 진단 후보이며 이미지나 위치를 전송하는 서비스 도입을 뜻하지 않는다.

## 4. 외부 프로젝트 재확인과 도입 판단

7개 upstream의 현재 default-branch HEAD를 API로 확인하고 해당 revision의 README를 직접 다시 읽었다. 기존45와 일치하는 revision도 최신 API 조회 결과로 확인했으며, 새 버전/새 성능이 나왔다고 꾸미지 않는다. 이번에는 가중치 다운로드·앱 복사·새 변환/추론을 하지 않았다.

| 대상·직접 확인한 revision | 확인한 사실 | 다음 작업에서의 역할 |
|---|---|---|
| [Meta EdgeTAM](https://github.com/facebookresearch/EdgeTAM/tree/7711e012a30a2402c4eaab637bdb00a521302c91) / [Jutsu](https://github.com/jutsuhq/edgetam-coreml/tree/3c36c37f93a3106375aa33c14fd7ec426b9e1fa9) | 전체 영상 변환4패키지와 photo2패키지는 구별. Jutsu FP32 CPU parity파일은pass=true지만 stock 비교/FP32 masked·FP16 ANE/GPU masked 원시파일은pass=false | **E4 단일 대상 기억 추적 PoC 1순위 유지.** 사진 CPU head 성공을 video memory parity 성공으로 확대하지 않음 |
| [MatAnyone2](https://github.com/pq-yang/MatAnyone2/tree/0079197acd6d16a741f71558809c06c586c579e0) / [Swift Kit](https://github.com/flowtyone/MatAnyone2Kit/tree/d85a029870b5149af6aa122cbc13c90db11e5b35) | first-frame seed 기반 recurrent alpha, Kit 고정288×512·저자 A18/iPhone16 성능. 현재 앱은 사진별 재초기화 | **선택 인물의 저장 영상 alpha**로 시간 state를 연결·비교. 저자30fps를15Pro/27.2 실측으로 쓰지 않음 |
| [ViTMatte](https://github.com/hustvl/ViTMatte/tree/8cd7ef068380) | image+trimap 입력, SAD/MSE/gradient/connectivity 평가 | **사진 ROI 경계의 비교 후보.** 모바일/CoreML 변환과 trimap 품질부터 PoC. 범용 추적/깊이 모델로 분류하지 않음 |
| [RVM](https://github.com/PeterL1n/RobustVideoMatting/tree/53d74c6826735f01f4406b5ca9075eee27bec094) | 인물 recurrent alpha·CoreML 고정 해상도 모델/내보내기 문서. GPU FPS는 다른 하드웨어 조건 | 가벼운 영상 인물 기준선. 특정 사람 ID를 선택하는 전체 객체 추적으로 대체하지 않음 |
| [Video Depth Anything](https://github.com/DepthAnything/Video-Depth-Anything/tree/4f5ae23172ba) | 공식 experimental streaming·학습 없는 cache 재사용, 실제 CLI vits/vitb/vitl 선택·기본vitl/max_res1280. PyTorch CPU/CUDA 코드 | **시간 깊이 안정화의 후속 별도 PoC.** 공개 iOS/CoreML 배포/실기기 성능을 이번 조사에서 확보한 것은 아님 |

ViTMatte/VDA의 표시는 읽기 쉬운 SHA 앞부분이며 전체 고정 SHA와 README/실제 streaming 코드 URL은 근거 JSON에 있다. segmentation(대상 mask), matting(alpha), depth(깊이/상대값), camera AF(렌즈 제어)를 같은 기능으로 취급하지 않는다. 작은 개발 평가 세트는 빠른 비교용이며 정식100장/10종 gate를 대체하지 않는다. 라이선스로 조사 대상을 배제하지 않는 기존 지시는 유지하고, 실제 이식 시 코드/weights 조건·원문 고지·SHA·수정·포함 범위를 계속 기록한다.

## 5. 영상과 라이브 개발 순서

1. **E4 저장 영상 단일 대상**: 기존 `SubjectTrackingSelection.id`·generation·top-left 좌표·기존 AF bridge를 재사용한다. EdgeTAM memory/pointer bank에 PTS·선택 교체·가로/미러·scene cut/seek/reset 계약을 추가한다. 처음 실험의 개발 검증은1080p/30급 짧은 영상부터 하고 기존 기본4K/60 영상 심도를 낮추지 않는다.
2. **parity 후 인물 alpha**: current CPU/GPU/ANE 별 mask/IoU/score/메모리를 원본과 비교한다. MatAnyone2는 사진의 반복이 아니라 증가하는 실제 프레임/PTS로 상태를 전달한다. 다중 인물·교차·가림 후 다른 사람에 붙지 않음을 확인한다.
3. **깊이 시간 안정화**: mask 기억만으로 depth scale 흔들림이 해결되지 않는다. 기존 flow/affine을 기준으로 streaming depth를 별도 평가한다. actor/메모리/seek/replay 정책을 통일한다.
4. **E5 라이브**: 사진 옵션과 별도Off·기한/열·프레임 최신성·수동/AF/AE lock 우선순위, 늦은 결과 폐기. 카메라 AF 제어와 가상 초점은 같은 선택의 다른 좌표 공간임을 유지한다.

네이티브 Cinematic은 iOS26의 `isCinematicVideoCaptureSupported`와 iOS17부터 Cinematic 자산 재생/편집 API가 있음을 공식 문서에서 재확인했다. **모든15Pro 포맷 지원·현재 일반 MOV에 자동 깊이 추가**를 뜻하지 않는다. 실제 capability와 SDR/포맷/음성·편집 조건을 검증한 뒤 독립 후보로 비교하며 현재 custom SDR 경로를 강제로 교체하지 않는다.

Core AI는 공식 DocC iOS27.0이다. `.aimodel`·specialization/function-loading 등 새 통합이 필요하므로 현재 CoreML 모델을 켜기만 하면 고해상도/실시간이 된다고 가정하지 않는다. **27.2 CI/기기 기준선 이후** 프로파일링/변환 PoC로 다룬다.

## 6. 사용자에게 새로 결정받을 것과 바로 진행 가능한 것

현재 확정된 **기존 심도 기본 유지·신규만 실험실Off·사진 독립·품질 우선·SDR·원본 불변·AI 메타데이터/앱 공지·공유 위치 제거/원본 위치 보존**으로 P0·계측/캐시·큐·ROI PoC는 설계/개발을 시작할 수 있다. GPS 기본값/라이선스별 조사 제외 여부를 다시 묻지 않는다.

실측 비교 뒤 정할 항목은 photo cache/열 예산·작업 큐 한도·ROI/모델 해상도·warmup 최적점·JPEG/SDR HEIC 기본 형식·새 영상 처리 해상도/빈도다. 이는 자료에 근거한 구현 선택이며, 새 실험을 기본On/정식 기능으로 승격하거나 HDR/Log/C2PA·AI 구도 추천을 재도입하는 정책 변경과 구분한다. 현재 사용 기기는15Pro라 물리 Camera Control 버튼은 우선 대상이 아니다.

권장 다음 개발 묶음:

- **A: 27.2 CI + 계측/재현 자료 + 실제 모델 역할 표시 정합.** 현재 기능을 평가할 기준과 신뢰 가능한 결과 표시를 만든다.
- **B: 공유/원본/GPS 계약 + 촬영/후처리 영속 큐 + 제한 모델 캐시.** 원본 보존·촬영 응답성·누적 작업을 함께 검사한다.
- **C: 사진 고해상도 ROI/sidecar + 품질 우선 SDR 출력.** 모발/안경/전경·근중원거리와48MP seam을 확인한다.
- **D: E4 저장 영상 → E5 라이브 → E6 정식 인수.** 기존 표준 기능과 독립된 추가 옵션으로 공개한다.

## 7. 검증 범위와 출처

이번 직접 실행은 main/source 대조, 공식 DocC20개 등 웹 응답36개 확인·hash, upstream7개 README/streaming 코드/원시 parity 결과 읽기, 기존 CI 상태 조회, 현재 빈 인수 manifest gate 실행이다. 사진 gate는sceneCount0/exit2, 영상 gate는realEvidenceRecords0/exit2였다. 새 iOS 빌드·CoreML/외부 모델 추론·실기기 촬영·경쟁 앱 비교·성능 수치는 만들지 않았다. 빈 gate의 exit2는 앱 자동 테스트 실패와 구별한다.

대표 공식 출처(상세 hash/가용OS/수집 실패·정정 URL은 JSON):

- [GitHub 표준 hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [27 전용 이미지](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md), [26 이미지](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md).
- Apple [MLComputePlan](https://developer.apple.com/documentation/coreml/mlcomputeplan-1w21n), [VNGeneratePersonInstanceMaskRequest](https://developer.apple.com/documentation/vision/vngeneratepersoninstancemaskrequest), [VNTrackObjectRequest](https://developer.apple.com/documentation/vision/vntrackobjectrequest).
- Apple [photo metadata customizer](https://developer.apple.com/documentation/avfoundation/avcapturephotofiledatarepresentationcustomizer), [replacementMetadata](https://developer.apple.com/documentation/avfoundation/avcapturephotofiledatarepresentationcustomizer/replacementmetadata(for:)), [Photos asset location](https://developer.apple.com/documentation/photos/phassetchangerequest/location), [GPS/XMP 제외](https://developer.apple.com/documentation/imageio/kcgimagemetadatashouldexcludegps).
- Apple [Cinematic capture 지원](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/iscinematicvideocapturesupported), [Cinematic framework](https://developer.apple.com/documentation/cinematic), [native AF tracking 지원](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/iscontinuousautofocustrackingsupported), [Core AI](https://developer.apple.com/documentation/coreai), [통합 가이드](https://developer.apple.com/documentation/coreai/integrating-on-device-ai-models-in-your-app-with-core-ai).

이번 보고서·근거·일지는 로컬 저장이며 아직 커밋/푸시하지 않았다. 앱 소스/모델·프로젝트/CI 설정을 변경하지 않았다.
