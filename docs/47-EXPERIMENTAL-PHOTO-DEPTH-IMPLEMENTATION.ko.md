# 실험적 사진 AI 심도 구현 기록

2026-11-21 KST. [기획46](46-EXPERIMENTAL-AI-DEPTH-PLAN.ko.md)에 따른 E0~E3 사진 경로 개발. 기준 main `ec97e59324da6669fdb3d7d74731b271a5e31561`, 작업 브랜치 `codex/experimental-photo-depth-20261120`. **최종 앱19b343a의 두 SDK 전체 CI 성공 후 main 게시를 확인했다.** 아래8절의 실제 검증과7절의 미인수 범위를 구분한다.

## 1. 실제 구현한 범위

기존 센서/LiDAR·Depth Anything/Vision·사진/영상/라이브 심도·추적/AF·PSF/전체 프로필·64MP·brush/키프레임/재편집은 일반 기능을 유지한다. 신규 실험 환경설정은 이 설정을 읽거나 초기화하지 않는다.

신규 사진 옵션은 다음 두 개이며 기본Off다.

| 실험실 옵션 | 실제 처리 |
|---|---|
| 정밀 피사체 선택 · 사진 전용 | EdgeTAM image encoder+initializer → 터치 위치의 선택 mask/예측 IoU/object score → 기존 RGB guided 매트/렌즈 합성. 이는 segmentation prior이며 광학 alpha/실측 깊이/전체 영상 추적이 아니다 |
| 인물 경계 개선 · 사진 전용 | 터치한 Vision person instance를 seed로 선택 → MatAnyone2의 사진별 새 상태/정적 예측10회 → 원래 종횡비로 alpha 복원 → Float alpha 유지·색 unmix → 기존 심도 합성. primary person seed도 사람/얼굴 검출로 확인. runtime/seed 읽기 오류에는 EdgeTAM seed+동일 확인을 보조 사용하며, 인물 없음/여러 인물 판정은 그대로 기존 방식으로 복귀 |

두 옵션이 모두 성공하면 최종 합성은 인물 alpha를 우선한다. 두 모델의 mask를 융합한 구현은 아니며 정밀 선택 기록은 먼저 실행한 선택 분석의 결과다.

같은 실험실을 사진 심도 고급 설정, 영상 심도 패널의 사진 전용 설정, 사진 편집기의 교정·진단에서 열 수 있다. 영상 모드에서 사진 설정을 바꿔도 영상/라이브의 신규 모델 추론은 시작하지 않는다. 촬영 모드 변경 시 설정 창을 자동으로 열지 않는다.

기본 심도 촬영을 켠 사진에서 원본 보관 후 선택한 실험을 처리한다. 기존 사진은 편집기의 **터치한 피사체를 정밀 선택하여 새 사진 만들기**를 명시적으로 실행해야 재분석한다. 편집기 열기/일반 f값 조절/원본 비교/일반 재저장에는 저장 matte·깊이를 사용한다.

## 2. 설정·원본·게시 계약

- `ExperimentalDepthPreferences`의 독립 UserDefaults key, version1·기능별 bool·기본Off. 기존v1의 새 인물 key 누락은false로 해석해 기존 정밀 선택값을 보존한다. 잘못된/미지원 version은 신규 실험만Off로 시작한다.
- `ExperimentalDepthRuntime.request(for:)`는 사진에서만 lease를 발급한다. 영상/라이브는nil이다. lease는 기능 스냅샷·generation을 포함하고 Off→On도 이전 작업을 무효화한다.
- 추론 사이·정적 warmup 사이에 취소/lease를 확인한다. 새 실험이 무효화되면 원본/기본 심도 작업을 없애지 않고 기존 방식으로 새 결과를 만든다. 최종 rename도 동일 lock 안의 generation 검사로 게시를 직렬화한다.
- 원본 hash를 실험 전/후 대조한다. pending UUID 결과에 JPEG·base depth·matte·recipe를 저장한 뒤 atomic rename한다. 실패/취소는 임시 결과만 정리한다.
- 성공한 모델/실패한 옵션을 각각 표시한다. 한 옵션의 fallback을 다른 옵션의 성공으로 표시하지 않는다. 실제 적용한 모델만 JPEG IPTC AI 설명에 추가하며 원본과 위치 정책은 유지한다.
- v3/v4 recipe에 nullable `experimentalDepth`, `experimentalPortrait`를 추가한다. 기존v2/v3/v4를 읽고, 기존 결과의 저장 matte/실험 provenance는 실험실Off에서도 복원한다. 새 AI 재분석만 중지한다.
- 재분석 후 editor가 새 세션/매트를 사용하며 preview revision을 올린다. 이전 preview task가 나중에 도착해 새 결과를 덮지 못하게 한다.

## 3. 인물 사진 경로의 제한과 처리

MatAnyone2의 작업 크기는288×512다. source 종횡비를 유지해 letterbox하고 seed를 같은 위치로 이동한다. 추론 후 padding을 제거하여 원본 좌표에 맞는 최대512px Float 매트를 저장한다. 기존 최대64MP 출력 합성은 유지하지만 **신경망이64MP alpha를 추론한다는 기능은 아니다.**

선택한 인물을 확인할 수 없거나 여러 얼굴이 함께 선택되는 seed는 primary/보조 모두 거부한다. 다른 가까운 사람에게 자동으로 붙지 않는다. 신경망 alpha는 기존 coarse-mask color-line alpha solver로 다시 바꾸지 않고, foreground/background 색 보정에만 연결한다. 기존 매트는 기본 인수 `preserveAlpha=false`로 종전 연산을 유지한다.

upstream의 정적 warmup은 한 사진의 내부 예측 반복이며 실제 영상10프레임 평가가 아니다. 상태를 다른 사진·영상·라이브로 넘기지 않는다. 모델 로드와 계산은 화면 스레드 밖에서 하고, 기존 inference gate를 공유한다. iteration별 autoreleasepool은 임시 Core ML 출력만 정리하며 다음 pass에 필요한 상태는 강한 참조로 유지한다. 기기 peak memory/열/지연은 별도 인수 대상이다.

## 4. 실제 외부 재사용·가중치

| 포함한 대상 | 범위·고정·조건 |
|---|---|
| Jutsu v1.2 EdgeTAM | ZIP SHA `9c35c1b6…3ae1401`. 이미지 encoder/initializer 원본 두 패키지6파일36,410,378bytes에서 출력 변경 후 **36,410,506bytes**. 패키지 폴더를 ExperimentalPhotoEncoder/Initializer로 변경하고 encoder/weights는 유지. initializer 출력 graph만 아래 방식으로 변경. Meta EdgeTAM7711e01 / inspected conversion3c36c37f / Apache2 LICENSE·NOTICE 유지 |
| MatAnyone2Kit d85a029 | `MatAnyoneCoreML.swift`, `MatAnyoneCoreMLEngine.swift`, `MemoryBank.swift`3파일 실제 복사. GPL-3.0 코드와 S-Lab1.0 가중치 조건을 별도 보존. compiled6모델·권리33파일에 고지2파일을 추가한35파일 **71,531,883bytes** 포함 |
| Swift 이식 변경 | 출처 헤더, Task/lease 취소 확인, 정적 반복별 autoreleasepool. 수치 모델·메모리 알고리즘은 유지. 자체 사진·인물·좌표·설정·저장 adapter는 별도 구현 |
| Native 참고 사진 | NASA Eileen Collins의 public-domain 이미지(scikit-image0.19.0),791,555bytes / SHA88431cd9…ea6cb5. 모델 계약·저장 회귀용이며 alpha/depth GT가 없음 |

[EdgeTAM 고지](../third-party/ExperimentalDepth/NOTICE.md), [MatAnyone2Kit 원 고지](../third-party/MatAnyone2Kit/NOTICE.md), [사진 모델 manifest](../assets/experimental-depth/ExperimentalDepthLegal/manifest.json), [매팅/이식 provenance](../third-party/MatAnyone2Kit/provenance.json)에 실제 URL·SHA·복사 파일·원본/수정본 hash·객체 파일 hash·조건을 남겼다. 실제 모델 사용 조건을 독립적으로 새로 확인/허가받았다고 표시하지 않는다. 코드와 weights의 조건을 혼동하지 않는다.

`scripts/check_experimental_depth_models.py`는6개 사진 모델 파일/권리2개,35개 인물 리소스/이식 source3개의 hash·범위·경로를 검사한다. 파생 decoder spec/재현 script hash도 검사한다. raw/compiled 자산 hash 검사와 iOS runtime 추론/품질 검증은 별개다. 앱에서 PyTorch/Python이나 클라우드 업로드를 사용하지 않는다.

## 5. 주요 변경 진입점

- `Processing/ExperimentalDepthPolicy.swift`: 설정/사진 전용 gate·lease/게시·선택 신뢰·provenance·letterbox geometry.
- `Processing/ExperimentalPhotoSubjectSelector.swift`: 실제 CoreML2모델·선택 logits·coarse matte. 예측 IoU≥0.5·object score>0·터치 포함·유한값/영역 검증.
- `Processing/ExperimentalPortraitMatte.swift`, `External/MatAnyone2/`: 선택 인물·사진 전용 정적 matting·padding/Float alpha·모델별 상태/취소.
- `Processing/CaptureResultProcessor.swift`, `DepthPhotoEditor.swift`: 새 실험과 일반 재처리 분리, 원본/sidecar/metadata·fallback·atomic 게시·세션 교체.
- `Camera/CameraModel.swift`, `UI/ExperimentalDepthSettings.swift`, `CameraQuickControls.swift`, `DepthResultLibraryView.swift`, `CaptureReviewView.swift`: 촬영 스냅샷·독립 설정·명시적 재분석·실제 결과 표시.
- `ios/project.yml`, `.github/workflows/ios.yml`, `Package.swift`: 두 모델군 리소스·무결성 검사·동일 production 정책의 portable/native 테스트.

위 iOS 경로의 루트는 `ios/PhotoP/`다. 모델 파일은 이 구현의 신규 실험용이며 기존 depth-model 폴더/AI 코치 중지 정책을 바꾸지 않는다.

## 6. 테스트·실패와 수정

새 검사: 독립 기본Off/설정 유지·v1 key 호환·photo/video/live 분리·old lease 게시 거부·유효 선택/영역·provenance·aspect-fit·신경망 alpha 불변, 실제 사진 CoreML 선택/인물 alpha·저장/재열기/Off 재편집·불확실 대상 fallback, 두 스위치 재실행·실제 editor 재분석·기존 제어값/편집 유지 UI.

첫 b58d859의 전체 CI44766574634(26.3)/44766666910(26.6)는 빌드 후 실제 사진 선택의 noSubject 때문에 실패했다. positive로 정한 손/의상(.45,.6)을 원본 PyTorch로 대조하니 최고 예측IoU0.4106이었다. 얼굴(.43,.2)은0.9019였다. **기준은0.5 유지**하고 명확한 얼굴을 positive 계약 검사로, 이전 손 위치는 정상 fallback 회귀로 분리했다. [실제 reference 결과](research/2026-11-21-photo-reference.json)를 보존했으며 이것을 CoreML 전체 parity나 화질 GT로 쓰지 않는다.

9d7c4ff의26.6 depth CI44771520957에서 실제 인물 alpha·저장·Off 재편집은 통과했다. 정밀 선택은 얼굴의IoU0.9067/score29가 정상인데 reduced mask가0으로 읽혀 두 케이스가 실패했다. 후속4dccbce는 Core ML 배열을 논리 좌표로 읽고 세 후보 중 최고IoU의 첫 후보를 직접 선택한다. 후보 면적/범위 진단을 추가했으며 신뢰도 기준은 유지한다. 이 단계에서 원인이 변환 그래프인지 배열 접근인지 단정하지 않는다.

4dccbce 전체26.3 CI44775025152에서도 candidate 세 개가 전부0이고 IoU는 정상(.08789/.67627/.90674)이었다. native404 중 선택2케이스/관련5assertion이 실패했으며 인물/기존 회귀는 통과했다. 논리 배열 접근만으로 해결되지 않아 이후 모델의 비학습 terminal exact GELU·선형 곱을 native로 분리했다. pristine decoder spec7d128934…81ef9c → 최종a3e0ca63…67f373, encoder/가중치는 그대로다. [파생 script](../scripts/derive_experimental_photo_head.py)를 같은 원본에 다시 실행해 byte 일치도 확인했다.

[원본 중간 출력 대조](research/2026-11-21-linear-mask-head-reference.json)에서 terminal exact GELU 차이8.94e-8, 세 mask의 clamped logits 최대차이3.81e-6, 양성 영역/선택은 같았다. 이는 원본Torch/NumPy 수치 대조이며 CoreML runtime parity를 대신하지 않는다. native vector GELU 상수/NaN·채널/픽셀 배치·single token 제외 검사도 추가했다.

c65d6f8의 두 빌드에서는 Accelerate에 없는 vverff 함수 사용으로 컴파일이 실패했다. 직접 도입한 API 오류는 Darwin.erff의 동일 수식으로 바로잡았다. 4dccbce의UI18 중 기존17은 통과했고 신규1이 상위 DisclosureGroup AX ID의 하위 switch/button ID 덮어쓰기로 실패했다. wrapper ID를 제거하고 자식 control ID·엄격한 기존 제어 assertion은 유지했다.

b294452의26.3 native405개는404통과/기존Flow1skip으로 완료됐다. 새 실제사진6개도 모두 통과했다. 실제 head 범위가 정상이고 candidate2의IoU0.9067383/양성1841px로 선택→512 매트→저장·Off 재편집이 성공했다. 영역 수가 같다는 것만으로 pixel parity를 선언하지 않는다. 해당 LUT/UI와 두 번째 SDK 검사는 이어서 확인한다.

26.6 실행44779078806은 steps0/runner_id0으로15분 대기 후 hosted runner 미확보·arm64 capacity annotation으로 종료됐다. 코드 실패와 분리하며 재시도했다. GitHub 공식 [표준 runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)·[Intel26 이미지](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md)의26.6/SDK26.5 설치를 확인하고 a4b2aac에26.6 전용 선택적 Intel host를 추가했다. iOS/모델 트리는 b294452와 동일하며 실행 시 기존SDK 확인을 유지한다. 실제 전체 결과는 아래에 확정한다. 최종 각 검사 수·source SHA·run URL·실패/skip은 결과를 확인한 뒤 확정한다. 이전/취소한 실행은 통과로 세지 않는다. Python34개와 모델 source hash 검사는 Linux 직접 실행에서 통과했으며 iOS 추론을 대체하지 않는다.

b294452의26.3 전체CI44778982243은 unit405=404통과/Flow1skip, LUT18, UI18로 success였다. 실제 artifact의 실험실 screenshot을 열어 확인하니 비인물 그라데이션에도 인물 적용 문구가 나오는 의미 오류가 있었다. 초기 UI 검사가 두 옵션의 적용/fallback 표시만 확인해 놓친 사례다.

19b343a는 primary Vision proposal에도 사람/얼굴 확인을 적용하고 notPerson/ambiguousPerson은 외부 seed로 우회 승인하지 않는다. 새 native 비인물512px 처리·원본/기본 깊이 보존·MatAnyone2 IPTC credit 미표기와 UI64px 비인물의 portrait-fallback assertion을 추가했다. 명확한 인물 양성 검사는 그대로 유지하며 406개 unit 대상(추가1)을 다시 실행한다. 이전 성공을 새 수정본의 성공으로 세지 않는다.

## 7. 미검증·후속

- iPhone15Pro/iOS27.2 실제 카메라/AF·처리 시간·peak memory·열·ANE/GPU 배치·원본 촬영의 근/중/원거리/모발·4K 동시 작업. SDK27/CoreAI 빌드·실행 미수행.
- 실제 사진100장/영상10종·3명 blind·기기 trace gate는 별도 미인수다. NASA 참고사진1장을 해당 acceptance dataset이나 경쟁 앱 비교로 계수하지 않는다.
- 이번 정밀 선택은 단일 양성 터치다. 외부 모델의 다중 양성/음성 prompt·후속 replay는 아직 제공하지 않으며 기존 brush 교정은 기본 기능으로 유지한다.
- EdgeTAM video memory/propagator·외부 streaming 깊이·새 모델의 라이브/영상 통합은 이번 사진 경로와 독립된 후속 E4/E5다. 기존 영상/라이브 심도와 Vision/flow 추적은 기본 제공을 유지한다.
- MatAnyone2의288×512 경계 해상도·다중 인물/부분 가림·유리/털/비인물·색/회전·64MP seam은 실제 자료로 비교해야 한다. 이 통합만으로 DSLR/Leica/업계 최고 품질이라고 선언하지 않는다.

### 실기기 수동 점검 준비(미실행)

- PRO 일반 단일 사진·심도f/2.8에서 두 옵션Off 기준 사진을 찍고, 옵션을 하나씩 켜 같은 인물/물체를 촬영한다. 기존 f값·프로필·사진/영상/live 설정이 유지되는지 확인한다.
- 인물 없는 벽/그라데이션/물체에는 인물 적용 표시·MatAnyone2 AI credit가 없어야 한다. 명확한 인물은 모발/손/의상·근/중/원거리·가림·다중 인물에서 실제 원본/결과를 비교한다.
- 저장 결과를 두 옵션Off로 다시 열어 f값·프로필·brush 교정과 원본 비교/새 결과 저장을 확인한다. 취소 후 원본·이전 결과와 기본 심도가 남는지도 확인한다.
- 가로/세로·전면/후면·24/48MP에서 선택 좌표·가장자리 seam·원래 해상도를 확인한다. Instruments로 결과 대기 시간·peak memory·10분 열/전력 trace를 기록한다. Simulator CPU 시간은 기기 속도로 환산하지 않는다.

## 8. 최종 검증·게시

검증 앱 소스 `19b343ac42f95555790ca75f60bcd53270d83d6c`. 이번에 직접 요청한 두 전체 CI의 원시 unit/LUT/UI 로그·xcresult summary·workflow 상태와 source SHA를 확인했다.

| 전체 CI | 환경 | 실제 결과 |
|---|---|---|
| [44784405939](https://github.com/MetaParodica/PhotoP/actions/runs/44784405939) | Xcode26.3·SDK/Simulator26.2·arm64 | **success** · portable158·unit405통과/Flow1skip(406)·LUT18·UI18·Python34 |
| [44784461745](https://github.com/MetaParodica/PhotoP/actions/runs/44784461745) | Xcode26.6·SDK/Simulator26.5·arm64 | **success** · portable158·unit405통과/Flow1skip(406)·LUT18·UI18·Python34 |

각 native합계424=423통과/기존Flow1skip이다. Optical Flow의 기존 Simulator runtime code9만 제외됐고 새 모델/인물·비인물 검사는 skip하지 않았다. UI18에는 두 스위치 재실행·실제 재분석·비인물 portrait 거부·기존 f값/프로필/brush 유지가 포함된다. 새 실제사진 native7개는 모두 통과했다. 26.6의 최종 화면 캡처도 직접 열어 비인물에 두 옵션 모두 기존 방식으로 처리한다고 표시됨을 확인했다. 이는 실제 사용자 사진/물리 iPhone 평가를 대신하지 않는다.

Linux 직접 Python34·신규 모델/권리/이식 source/파생 graph·재현 script hash·문서 로컬 링크·diff 형식 검사도 통과했다. 같은 test를 portable/native에서 중복 실행한 수를 서로 다른 품질 사례로 합산하지 않는다. 기존/중간/취소한 실행은 위 최종 성공에 포함하지 않는다.

앱19b343a를 main에 정상FF push하고 `git ls-remote origin refs/heads/main`의 동일 SHA를 확인했다. 이후 검증/온보딩/개발 일지의 문서 후속은 앱·모델·테스트·CI 코드를 바꾸지 않는다. 문서 후속은 `[skip ci]`로 불필요한 native 재실행을 생략하고 링크/형식 검사를 수행한다. 최신 문서 HEAD와 검증 앱 SHA를 구별한다.

E0/E1과 E2의 사진 alpha·합성/재편집, E3의 설정/표시·회귀를 구현·검증했다. E3의 실기기 수동 점검과 E4/E5·정식 품질 인수는 미완료다. 선택적26.6 Intel host는 실제 SDK/iPhone 빌드까지만 확인했으며 native/UI 전체는 미검증이다. 이번 최종 두 환경은 arm64다.
