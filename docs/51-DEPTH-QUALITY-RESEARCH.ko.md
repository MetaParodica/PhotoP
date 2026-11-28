# 심도 품질 개선 조사 — 네이티브 깊이와 렌즈 합성

2026-11-25 KST. 기준 HEAD `7f0f6c0`와 **로컬 미커밋 N1 구현**([50](50-NATIVE-DEPTH-FIRST-IMPLEMENTATION.ko.md))을 대조했다. [49](49-NATIVE-DEPTH-LENS-PRIORITY.ko.md)의 방향을 구체화하는 조사이며, 이번 작업에서 앱을 추가 수정하거나 화질/발열을 측정하지 않았다. 상세 실행 계획은 [52](52-DEPTH-QUALITY-DEVELOPMENT-PLAN.ko.md).

## 1. 결론

우선 개선할 것은 **저해상도 네이티브 깊이의 정합·경계 정밀화, 안정된 초점 거리, 가림을 고려한 렌즈 합성**이다. 더 강한 인물/물체 분할 모델을 추가하는 것만으로 세 문제가 해결되지는 않는다. 특히 원통·병·가구·바닥은 인물 매트가 아니라 장면의 연속 깊이와 앞뒤 가림이 중요하다.

권장 조합은 다음과 같다.

1. 공개 `AVDepthData`와 동반 색상을 기준 입력으로 보존하고, Apple의 공개 깊이 흐림 필터를 같은 입력의 비교 기준으로 추가한다.
2. GPU guided filter를 1차 깊이 경계 정밀화 후보로 삼되, 유효 깊이·색상 경계의 불일치와 가림을 검사한다. 신뢰 가중 bilateral solver는 비교용 참조로 둔다.
3. 기존 signed CoC·다층 PSF를 재사용하면서 깊이별 가시성·근경 확산·고해상도 경계 저장을 보완한다. 모델 기반 보정은 품질 개선이 확인되는 경계 ROI에서만 선택적으로 검토한다.

이는 조사에 따른 개발 선택이다. 아직 MPS 필터나 외부 렌더러를 앱/실기기에서 비교 실행한 결과가 아니다.

## 2. 현재 코드에서 확인한 제약

| 영역 | 현재 동작 | 품질 개선 과제 |
|---|---|---|
| 입력 | 방향 적용한 depth/disparity를 Float32로 읽고 절대/상대 단위를 구분. N1은 quality/filtered/intrinsics 요약도 보존 | 방향·미러·crop/zoom·원래 calibration 좌표를 함께 관리하는 geometry 계약 |
| 깊이 확대 | `NaturalDepthEngine.mask`가 저해상도 CoC/validity를 일반 보간으로 확대 | RGB 유도 경계 정밀화, 결측/혼합 픽셀과 관측 표면 분리 |
| 초점 | 터치 주변3×3 유효 값의 중앙값 | 얇은 물체와 배경이 섞일 때 선택 물체 내부의 일관된 깊이 군집 사용 |
| 상대 깊이 | 장면 깊이 분포의 span을 사용하는 가상 CoC | 물체 출입/구도 변화에 따른 효과 크기 변동 점검. 상대값을 미터로 표시하지 않음 |
| 경계 매트 | 사진 최대512px 저장/복원, live160px. 사람 내장 매트와 선택 매트 사용 | 고해상도 경계 ROI·색 번짐 보정·재편집 품질 보존 |
| PSF | 선형 premultiplied 색상/coverage, signed 깊이 층, Metal taps와 큰 반경 피라미드 | 층간 가시성·occlusion·샘플 배분 정밀화. 기존 구조를 없애고 단순 두 영역 블러로 돌아가지 않음 |
| 고해상도 | 12.6MP 초과 시 qualityPairs16→8. 현재 층 수17→9, PSF taps33→17 | 출력 해상도와 합성 정확도는 별개. 품질 우선의 적응 층/샘플·타일 비용 검증 |
| 배경 확장 | 배경 seed의 국소 정규화 원판 필터, 근거 없는 곳은 관측 색 유지 | 가림 경계 주변에서 색 오염/halo를 줄이되 숨은 배경 복원을 주장하지 않음 |
| 시간 일관성 | 기존 flow 등록·상대 scale 보정·광도 변화·세대/만료 거부 | 대상 ID와 대표 깊이의 안정화, 가림/장면 전환 시 잘못된 이력 제거 |

이 표는 소스의 구조와 개선 후보를 구분한다. PhotoP 불량 결과의 원본/레시피·동일 입력 비교가 아직 없어 각 후보의 실제 기여도를 확정하지 않았다. N1의 자동 AI 분리/preview 예산 변경도 실기기 품질·열 인수를 마친 상태는 아니다.

사용자가 기본 카메라 비교본으로 확인한 HEIC에는576×768 깊이 보조 이미지가 있었다. 대응 주 이미지4284×5712와의 축 비율은7.4375배다. **깊이 좌표1픽셀의 오차가 색상 좌표에서 여러 픽셀이 될 수 있는 크기**이며, 이는 좌표 비율 계산이지 실제 경계 오차 측정값이 아니다. HEIC의8bit depth coded sample을 미터 값이나 내부 AVDepthData 정밀도로 오해하지 않는다.

## 3. Apple 공식 문서에서 확인한 범위

### 3.1 깊이와 신뢰도

[AVDepthData](https://developer.apple.com/documentation/avfoundation/avdepthdata)는 동반 영상의 렌즈 왜곡에 맞춰진 비직선 좌표의 깊이/시차를 전달한다. 같은 영상에 효과를 적용할 때 깊이만 무조건 보정하면 오히려 어긋날 수 있다. 다른 센서/3D 좌표로 재투영할 때는 색상·깊이 양쪽의 보정/변환을 함께 적용해야 한다.

[depthDataQuality](https://developer.apple.com/documentation/avfoundation/avdepthdata/depthdataquality)는 지도 **전체의** 품질이다. 개별 픽셀의 확률/confidence map으로 사용할 수 없다. [depthDataAccuracy](https://developer.apple.com/documentation/avfoundation/avdepthdata/depthdataaccuracy)의 절대/상대 단위 정확도도 품질과 별개다.

[사진 필터링](https://developer.apple.com/documentation/avfoundation/avcapturephotosettings/isdepthdatafiltered)은 기본 활성화이며 시간적 보간으로 잡음/빈 영역을 보완한다. 유효 값이라고 모두 해당 순간의 직접 관측치인 것은 아니다. 이미 필터링된 지도에서 보완 픽셀의 원래 위치를 완벽히 되찾을 수 있다고 가정하지 않는다. 일반 촬영은 효과에 적합한 필터링 경로를 우선하고, unfiltered는 지원 범위 내 진단 실험으로 비교한다. 둘을 같은 순간의 독립 정답처럼 취급하지 않는다.

[ARKit confidenceMap](https://developer.apple.com/documentation/arkit/ardepthdata/confidencemap)은 LiDAR sceneDepth의 픽셀별 신뢰도 정보다. AVDepthData 전체에 똑같은 map이 제공된다는 뜻이 아니다. 반사/흡광 표면에서 신뢰도가 떨어질 수 있다. 일반 사진에는 유효성·국소 깊이 일관성·RGB 경계·포화/암부 등을 사용한 **자체 신뢰 가중치**가 필요하며, 이를 하드웨어 확률로 표시하면 안 된다.

### 3.2 인물 매트의 역할

[AVPortraitEffectsMatte](https://developer.apple.com/documentation/avfoundation/avportraiteffectsmatte)는 세밀한 인물 경계를 위한 사람 중심 매트이며 장면의 모든 깊이 변화를 보존하는 지도가 아니다. 공식 문서의 해상도 예시는 문서 작성 당시 카메라의 사례로, iPhone15Pro의 모든 렌즈/포맷에서 같은 크기를 보장하지 않는다.

내장 매트가 있는 인물은 이를 우선 활용한다. 원통·병·잎·유리 등에 사람 매트를 강제로 적용하지 않는다. 불투명 물체의 기하 경계, 머리카락의 부분 alpha, 유리의 투과/반사는 서로 다른 문제다. 하나의 부드러운 선택 마스크로 모두 동일하게 처리하지 않는다.

### 3.3 공개 깊이 흐림 필터 — 비교 기준

[CIContext.depthBlurEffectFilter](https://developer.apple.com/documentation/coreimage/cicontext/depthblureffectfilter(for:disparityimage:portraiteffectsmatte:orientation:options:))는 색상·disparity·선택적인 portrait matte와 방향에서 깊이 흐림 필터를 만드는 공개 API다. iOS12부터 제공되므로 앱의 최소 iOS18 범위에서 검토할 수 있다. [파일 URL 입력](https://developer.apple.com/documentation/coreimage/cicontext/depthblureffectfilter(forimageurl:options:))도 있다.

이 API를 **PhotoP 자체 렌더러의 독립 비교 기준**으로 추가할 가치가 있다. 문서는 얼굴 landmark 활용도 설명하므로 비인물·초점 위치·조리개 제어 범위를 실제 반환 필터의 지원 키/출력으로 확인해야 한다. 지원하지 않는 조건을 지원한다고 간주하지 않는다.

Apple Camera 앱 전체의 촬영·ISP·다중 프레임·독자 보정과 같은 파이프라인은 아니다. 이미 흐림이 보이는 Apple 비교본에 다시 효과를 적용해 자체 렌더러와 공정한 비교를 했다고 주장하지 않는다. PhotoP에서 얻은 같은 색상/깊이로 비교하고, Apple Camera 완성본은 별도의 제품 참고 자료로 둔다.

### 3.4 GPU 경계 정밀화

[MPSImageGuidedFilter](https://developer.apple.com/documentation/metalperformanceshaders/mpsimageguidedfilter)는 iOS11.3부터 제공되는 edge-aware 필터다. 공식 API에는 guidance·source·weights를 받는 regression과 coefficients를 이용한 reconstruction이 있다. 낮은 해상도에서 계수를 구하고 높은 해상도에서 복원하는 후보로 적합하다.

단독 guided filter는 물체 경계의 정답을 알지 못한다. 표면 무늬/그림자 경계를 가짜 깊이로 복사하거나 비슷한 색의 앞뒤 물체를 합칠 수 있다. 입력 깊이의 불연속·유효성·신뢰 가중치·매트 경계를 함께 쓰고, 관측 깊이의 안정된 영역은 강하게 고정하는 방식으로 검증한다. 실제 지원 texture 형식·epsilon·비정상 값·타일 halo는 SDK/기기 PoC에서 확인한다.

## 4. 논문·오픈소스 대조

| 자료 | 이번 직접 확인 | 적용 판단 |
|---|---|---|
| [Google, Synthetic Depth-of-Field with a Single-Camera Mobile Phone](https://research.google/pubs/synthetic-depth-of-field-with-a-single-camera-mobile-phone/) | SIGGRAPH2018 공식 초록. 사람 분할과 가능한 경우 dual-pixel 깊이를 결합하는 모듈 구조 | 분할과 기하의 역할 분리에 참고. 해당 기기의 과거 처리 시간을 iPhone 성능으로 환산하지 않음 |
| [Fast Bilateral Solver](https://arxiv.org/abs/1511.03296), [저자 코드](https://github.com/poolio/bilateral_solver) | 신뢰 가중 target와 bilateral 공간의 정규화를 푸는 실제 notebook. README는 비최적화 구현임을 명시 | native 깊이 anchor/불확실 경계 보정의 오프라인 참조. 기존 Python/SciPy 코드를 live iOS에 그대로 넣지 않음 |
| [Guided filter OpenCV 구현](https://github.com/atilimcetin/guided-filter) | 공개 C++ 코드·회색/RGB guidance, 같은 guidance의 초기 계산 재사용. README MIT 표기 | 알고리즘 참조. iOS 첫 후보는 MPS로 정해 OpenCV 전체 의존성 추가를 피함. 원 논문 URL 일부는404라 원문을 읽었다고 기록하지 않음 |
| [Dr.Bokeh](https://shengcn.github.io/DrBokeh/), [소스](https://github.com/ShengCN/DrBokeh-Src) | RGBAD 다층 입력, 가림 포함 scatter와 CUDA 커널의 색/가중치/가시성 결합 | 자체 Metal 렌더러의 가림·부분 coverage 참조로 우선 활용. CUDA 확장을 직접 모바일에서 실행할 수 있다고 가정하지 않음 |
| [BokehMe](https://juewenpeng.github.io/BokehMe/), [소스](https://github.com/JuewenPeng/BokehMe) | CVPR2022. classical scatter 오류 영역을 neural renderer로 보정하는 구조. 코드의 CUDA/CuPy scatter·누적 가중치 확인 | 오류 영역을 한정해 처리하는 설계 참고. neural 모델 전체를 기본 촬영에 추가하지 않음 |
| [Bokehlicious](https://timseizinger.github.io/BokehliciousProjectPage/), [소스](https://github.com/TimSeizinger/Bokehlicious) | ICCV2025 프로젝트·컨볼루션/attention 기반 모델 코드, RealBokeh 자료 링크 | 시각적 목표/평가 자료 후보. native 기하 보존·글자/얼굴 재현·기기 비용이 확인되기 전 기본 엔진 대체로 채택하지 않음 |

고정한 저장소 revision은 DrBokeh `24d96e4`, BokehMe `8b3ed55`, Bokehlicious `0d2c458`, bilateral_solver `4b6ef7e`, guided-filter `57749d8`이다. 전체 SHA·파일 URL·hash는 [근거 JSON](research/2026-11-25-depth-quality-sources.json)에 있다.

이번에는 소스/문서를 읽기 위해 `/tmp`에 다운로드했으며 **새 외부 코드·가중치를 앱에 복사하지 않았다.** 향후 이식은 출처·revision·복사/수정 파일·알고리즘 차이·조건을 당일 일지와 기존 provenance에 기록한다. 가중치/자료의 조건은 코드와 별도로 기록한다. 예를 들어 guided-filter README의 MIT 표기와 Bokehlicious README의 상업 이용 시 license 확인/contact 문구를 한 종류의 권리로 합치지 않는다. 사용자 지시에 따라 라이선스를 이유로 조사 대상을 배제하지 않았다.

## 5. 무엇을 먼저 채택할지

| 방법 | 장점 | 주요 위험 | 결정 |
|---|---|---|---|
| 단순 bilateral/전체 blur 강화 | 구현이 작음 | 물체 경계 누출·바닥 깊이 평탄화·잘린 전경 | 품질 개선의 주 방법으로 사용하지 않음 |
| MPS guided refinement + native anchor | 공개 GPU API, 새 학습 모델 없이 정밀화 가능 | texture copying·동일색 경계 실패 | **첫 PoC**. 동일 입력 기준선과 경계 사례를 통과해야 기본 경로로 승격 |
| 신뢰 가중 bilateral solver | 결측/신뢰도와 구조를 함께 다룸 | 계산/메모리·튜닝 비용, 과평활 | 오프라인 비교 참조. MPS 실패 사례에서 추가 가치 검증 |
| visibility-aware 다층 PSF | 색 번짐·근경 가림의 렌더링 원인을 직접 다룸 | 샘플 수·타일 halo·정규화 오류 | **핵심 자체 엔진 고도화** |
| neural 전체 사진 보정 | 어려운 경계의 보완 가능 | 열·재현성·글자/피부 변형·원래 기하 변경 | 기본 경로에 추가하지 않음. 후속 실험실 ROI 보정 후보 |

## 6. 평가에서 구분할 것

- 깊이 정확도, 경계 alpha, 렌즈 합성, 실제 광학 AF와 대상 추적을 별도 지표로 본다. 하나의 매트 점수로 전체 화질을 평가하지 않는다.
- 기본 카메라 비교본과 PhotoP 결과가 같은 입력이라는 보장은 없다. 동일 입력 렌더러 비교와 실제 앱 간 비교를 별도로 보고한다.
- 고해상도 파일 생성은 고해상도 경계 품질 확보와 다르다. 원본 크기 확대·가림·재편집 복원까지 검사한다.
- 원래 광학적으로 흐린 부분·가려진 배경·센서에서 이미 잘린 하이라이트를 이 처리만으로 복원할 수 있다고 주장하지 않는다. SDR 계약은 유지한다.
- 열 상태 enum은 실제 온도(°C)가 아니다. Instruments/프레임 지연/메모리/system pressure와 조건을 기록하고, 표면 온도는 외부 계측이 있을 때만 별도로 보고한다.

## 7. 조사 검증 상태

직접 성공한 웹 응답35개(Apple DocC18개 포함), 저장소 HEAD5개, 실패 URL10개와 로컬 소스16파일 hash를 기록했다. 실패 URL은 canonical 경로/실제 notebook 경로를 찾아 일부 대체했고 실패도 남겼다. URL404를 기능 부재로 해석하지 않았다. 특히 깊이 흐림 API는 `CIDepthBlurEffect` 추정 경로 대신 `CIContext`의 실제 reference를 따라 확인했다.

문서·코드 읽기와 기기 실행을 구분한다. 이번에 MPS/외부 구현·native/Metal 테스트·새 모델 변환·실사 A/B·열 측정을 실행하지 않았다. 이전164개 공통 테스트는 N1 작업의 기록이며 이번 조사의 품질 검증 점수로 재사용하지 않는다.
