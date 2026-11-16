# 외부 AI 확정·AF 제어·Natural 정지 사진 심도 1차 구현

2026-11-16 KST. 기준 main `dc75be6`. 사용자 요청: 외부 AI 모델을 찾아 확정하고, 착수 가능하다고 판단한 나머지 작업도 적용. 이전 [24 계획](24-SOFTWARE-DEPTH-DEVELOPMENT-PLAN.ko.md)·[25 조사](25-AF-DSLR-FEATURE-RESEARCH.ko.md)·[26 API 조사](26-IOS17-27-CAPABILITY-RESEARCH.ko.md)를 보존하며, **실제 이번 변경 범위와 미완료 항목은 이 문서를 우선**한다. 작업 트리 상태이며 커밋·푸시·병합은 하지 않았다.

## 1. 확정한 외부 AI 모델

**Depth Anything V2 Small · Apple Core ML FP16**을 초기 기본 깊이 모델로 확정하고 실제 패키지를 저장소에 추가했다. Small 외의 Base/Large/Giant·비상업 가중치는 넣지 않았다. “모든 후보 중 실측 최고”가 아니라, 배포 권리·Apple 변환본·크기·실제 I/O 계약을 확인한 초기 제품 선택이다.

- 공식 배포: https://huggingface.co/apple/coreml-depth-anything-v2-small
- 고정 revision: `cfef6f6f2a70783dedc0bfae40cecbc2052285d3`
- 모델카드 원문: https://huggingface.co/apple/coreml-depth-anything-v2-small/raw/cfef6f6f2a70783dedc0bfae40cecbc2052285d3/README.md
- 원본 Small 권리 명시: https://github.com/DepthAnything/Depth-Anything-V2/tree/a561b849ebae10a6f5ef49e26c83cbbcd36c71bf
- 원본 Small Apache-2.0, Apple 모델카드 apache-2.0, 해당 model.mlmodel 메타데이터 Apache2를 확인했다. 원본 LICENSE와 NOTICE/논문·변환 출처를 `assets/depth-model/legal/`에 보관한다. 새로운 AI 권리는 이전 LUT 권리 확인과 별개이며 독립 법률 감사를 주장하지 않는다.
- 패키지3파일 약49.8MB: model399,433 bytes, weights49,419,072 bytes, manifest617 bytes. 최종 IPA 증분 크기는 미측정이다. FP16을 선택했고 경계 품질을 재측정하지 않은 양자화 모델을 기본으로 쓰지 않았다.
- 파일별 SHA-256·권리·입출력은 [manifest](../assets/depth-model/legal/manifest.json)에 기록했다. 실제 다운로드와 해시 대조를 완료했다.

### 실제 모델 계약 검사

임시 Linux 도구 환경의 coremltools8.3.0 protobuf 파서로 **추론이 아니라 파일 명세**를 확인했다.

| 항목 | 실제 패키지 |
|---|---|
| 모델 형식 | mlProgram / specificationVersion8 |
| 입력 | `image`, RGB image, **518×392 고정** |
| 출력 | `depth`, **518×392 GRAYSCALE_FLOAT16 image** |
| 해석 | 상대 역깊이, 미터 단위 센서 측정이 아님 |
| 전처리 | 모델 안에 정규화 포함. 앱은 RGB 리사이즈만 수행 |

상위 PyTorch README의 동적 종횡비/518 설명을 이 고정 패키지에 그대로 적용하지 않는다. 모델 자체의 입력/출력 shape는 고정이다. PhotoP는 특히 세로 사진을 가로로 찌그러뜨리지 않도록 **종횡비를 유지해 맞추고 edge-pad한 뒤, 출력 깊이에서 같은 ROI를 잘라** 원래 사진 좌표로 되돌린다. 정수 픽셀 반올림 오차만 허용한다. 이 정책은 Apple 모델카드의4:3 landscape stretch 평가와 다르므로 별도 품질 검증이 필요하다. 모델카드의 iPhone12/15 추론 시간은 출처 참고이며 PhotoP 측정값으로 주장하지 않는다.

`ExternalDepthEstimator`는 Xcode가 컴파일한 `DepthAnythingV2SmallF16.mlmodelc`를 지연 로드하고 입력/출력 shape·pixel format을 검사한다. FP16 출력 행 stride를 존중하여 읽는다. 추가 ImageNet 정규화·런타임 모델 다운로드·서버 전송·API 키·타사 추론 런타임은 없다. Core ML 예측은 Linux에서 실행할 수 없어 미검증이다.

## 2. 구현한 AF 제어와 UI

- AF-C/AF-S 선택. AF-S 지원 기기에만 선택지를 표시한다.
- 터치 AF+AE / AF만 / AE만 분리.
- 일반 터치는 요청된 MF·명시적 AF/AE 잠금을 유지한다. AF-S가 자동으로 안정화한 잠금과 사용자의 명시적 잠금을 구분한다.
- AF-ON은 중앙 초점을 명시적으로 다시 잡고 MF/AF 잠금을 해제하지만 노출·WB 잠금은 바꾸지 않는다.
- 길게 누르기 대기는 요청한 AF/AE 축만 관찰·고정한다. 다른 축을 같이 잠그지 않는다.
- 지원되는 AF 근/원거리 제한과 smooth AF.
- MF 하단3×/5× 중앙 무보정 확대창. 원본 화각·카메라 zoom·파일을 변경하지 않는 디지털 확인 창이다. 확대창에는 터치 조작을 전달하지 않는다.
- AF 조정 중/안정 추정/잠금/MF/네이티브 추적 상태를 구분한다. 노란 박스는 **요청 위치**이며 선명도 성공 표시가 아니다. lensPosition은 거리로 환산하지 않는다.

`FocusControlPolicy`는 플랫폼 독립 판단, `CameraService`의 직렬 queue는 장치 설정, `CameraModel`은 사용자 의도를 소유한다. 기존 완료 콜백·timeout·pending 설정 보호를 재사용한다. 실제 렌즈 API 적용 전에 실패할 수 있는 지원 검사를 하고, 완료 transaction을 연 뒤 검증 오류로 pending 상태를 남기지 않도록 했다.

### iOS26/27 어댑터

`CameraPlatformFeatures`는 컴파일 SDK 플래그와 런타임 availability를 함께 검사한다. 프로젝트는 SDK26/27의 device/simulator별 조건부 설정으로 플래그를 선택한다. 최소 배포17은 유지한다.

-26: 실제 AF rect·최소 크기 검사. 낮은 SDK/OS에서 가짜 S/M/L hardware 영역을 표시하지 않는다.
-27: 포맷 지원 검사, focusTrackedObject 메타데이터 출력·구독, continuous AF 추적·acquired readout, 렌즈/영상 전환 때 tracking 출력 정리. 별도 객체 신원/눈 추적/이동 박스 UI를 완성한 것은 아니다.
-27: 지원 조합일 때 **S·Auto ISO**. 시간 고정·시스템 ISO 자동 조절을 사용하며, ISO 슬라이더 대신 실제 readout을 보여 준다. EV 보정·물리 조리개 Av는 이번 범위에 넣지 않았다.
- native metadata가 UI를 무제한 갱신하지 않도록 최대4Hz로 제한한다.

해당 SDK 분기와 실제 세션/기기 조합은 미검증이다. 특히 RAW·깊이·고해상도·추적 동시 사용은 실기기 인수 전 보장하지 않는다. Vision 기반 눈 AF·대상 재획득·17~26 범용 피사체 추적은 아직 추가하지 않았다.

## 3. Natural 정지 사진 심도

PRO f값에 입력 선택을 추가했다.

1. 센서 우선·AI 대체: 실제 사진 깊이가 있으면 사용, 없으면 내장 AI.
2. 사진 깊이만: 센서 데이터가 없으면 명시적으로 실패.
3. AI 상대 깊이: 현재 렌즈로 일반 사진을 찍고 AI로 처리.

AI 모드 때문에 LiDAR를 가짜로 활성화하거나 카메라 세션을 바꾸지 않는다. 센서 모드에서는 지원 시 인물 효과 매트 전달/포함을 요청한다. 사진 깊이는 EXIF 방향·사진 비율·유효 값·상대/절대 정확도를 확인한다.

### 새 엔진의 실제 처리

- `SoftwareDepthField`: top-left 역깊이, 무효 값0, 상대/미터 역수 단위 분리, 최대 약2M 깊이 샘플.
- 초점 주변 유효 값 중앙값과 정지 사진용2~98% 깊이 범위. 전체 깊이가 거의 일정하거나 초점이 무효이면 합성을 꾸며내지 않고 원본을 남긴다.
- signed CoC: 전경/배경 부호·반경을 구분. 절대 깊이는 가상50mm·긴 변36mm 기준 렌즈 근사, 상대 깊이는 별도 창작 강도 계약이다. 실제 휴대폰 조리개·측정된 상용 렌즈 PSF가 아니다.
- 약17개 기본 깊이 중심과 초점면을 사용한 삼각 가중 레이어, 원판 `CIDiscBlur`, premultiplied 원근 합성.
- 배경 레이어의 유효 색을 경계 아래로 로컬 확장하고, 기록되지 않은 배경 복원은 근사라고 명시한다. 멀리 떨어진 빈 영역에서는 보수적 fallback이 남는다.
- 초점면 원본을 보존한 뒤 흐린 전경을 마지막에 얹어, 선명한 배경 위로 전경 보케가 확장되게 한다. 초점면 복원이 전경 보케를 지우지 않도록 순서를 분리했다.
- 포함된 인물 매트는 초점면 경계의 선택적 보조다. 모든 머리카락의 전경색 분리/오염 제거·일반 투명체 매팅을 완성했다고 주장하지 않는다.
- 깊이/매트는 색이 아닌 데이터로 처리하여 감마 변환을 끈다. 색 처리는 명시적 extended-linear-sRGB 작업 공간 → 출력 sRGB → 기존 LUT/입자/마감 순서다. 원본 JPEG/HEIF의 ISP 톤매핑까지 되돌리지는 않는다.

이것은 초기 Natural 보케 엔진이며 Leica LUX/DSLR 동등 품질을 입증한 결과가 아니다. 깊이 레이어 근사·재구성·극단적 경계 실패를 경쟁 촬영으로 평가해야 한다.

### 해상도·촬영 제한

Natural/AI는 최대12.6MP. 자동 축소하지 않는다. 지원되는 실제12MP급 해상도를 사용자가 선택할 수 있는 버튼을 제공하며, 초과하면 원본을 보존하고 안내한다. ‘사진 깊이만’의 기존 고해상도 심도는64MP 기본 variable-blur 경로를 유지하며 새 Natural과 구분한다. 기존64MP LUT 경로도 유지한다.

RAW·브래킷·LONG·영상에 새 Natural 효과를 제공하지 않는다. 네이티브 피사체 추적과 심도도 현재 상호 배제한다. 이동한 추적 대상의 메타데이터를 사진 깊이 좌표에 연결하기 전에 과거 터치 지점을 새 초점면으로 잘못 사용하지 않기 위해서다. 일반 AF-S/C 터치와 심도는 사용할 수 있다. f값은 촬영 후 가상 흐림이며 **실시간 심도 프리뷰는 아직 아니다**. 기존 실시간 LUT 프리뷰를 대체하거나 제거하지 않는다. 원래 허용되지 않았던 모드 조합을 가짜로 활성화하지 않는다.

## 4. 저장·재처리

원본 bytes는 계속 보존한다. 성공 결과는 기존 원자적 pending→final 번들에 새 JPEG·LUT와 다음을 저장한다.

- recipe v2: 실제 깊이 출처, 상대/절대 단위, 초점·f값, 해상도, 매트 사용 여부, 처리 경로.
- `depth.f32`: little-endian Float32 역깊이, width/height/units·SHA-256. AI 값을 미터로 표시하지 않는다.

‘최근 심도 사진을 현재 f값으로 재처리’는 저장 깊이·촬영 당시 초점/룩을 사용하여 별도 결과를 만든다. 현재 카메라 화면으로 재추론하지 않는다. 경로·크기·버전·원본·깊이·LUT hash를 검사하고 손상되면 거부한다. 원본/이전 결과는 바꾸지 않는다.

첫 UI는 **f값 재처리만** 지원한다. 사진을 다시 열어 새 위치를 탭하는 재초점 편집 UI·앱 재시작 후 심도 결과 보관함은 후속이다. v1 결과는 기존 디코딩이 가능하지만 깊이 asset이 없으므로 이 재처리를 허용하지 않는다.

## 5. 빌드·검사·CI

- Swift6.0.3/Linux portable 테스트 **97개 통과**(기존82+AF/심도/모델 좌표 정책15).
- Python **23개 통과**(기존19+모델 manifest 정책4).
- 기존 LUT5+25, 새 모델3파일·LICENSE/NOTICE 무결성 검사 통과.
- Swift142개 `-frontend -parse`, YAML parse, `git diff --check` 통과. iOS 타입 검사·Metal/CI kernel 실행과 다르다.
- 새 iOS 테스트7개: Core ML 실제 입력/출력 추론, Natural 색/초점·원본/깊이 저장·재처리, 변조 거부, 무효 깊이, 오프라인 AF-ON 보호, Auto ISO 및 tracking 충돌 검증. **작성만 했으며 미실행**이다.

환경 점검 절차에 따라 모델 명세 검사·Linux 테스트 도구는 `/tmp`의 임시 환경에 설치했다. 앱 Python/패키지 의존성을 추가하지 않았다. 모델 명세 파싱 성공을 Core ML 추론 성공으로 보고하지 않는다.

CI는 공식 runner 문서의 macOS26.6.1/Xcode26.6 경로를 확인하여 `macos-26`·Xcode26.6을 기본으로 선택하도록 변경했다. 모델 원본 무결성·컴파일된 `.mlmodelc`·법적 고지 포함 여부를 검사한다. 수동 실행에서27을 선택할 수 있지만, runner에 실제 Xcode27이 없으면 명시적으로 실패한다. default26 검사 통과를27 검사 성공으로 대체하지 않는다.

공식 추가 근거:

- https://developer.apple.com/support/xcode/ — 조회 시 Xcode27/27.2 및 iOS27 SDK 등재, 요구 macOS26.6 이상 확인. 로컬 설치·호환 기기 확인은 별개다.
- https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md — 조회 시 기본 Xcode26.6, `/Applications/Xcode_26.6.app`;27 안내가 있어도 기본 설치표에27은 없었다.

CI 변경은 미푸시라 **새 CI 실행·SDK 빌드·Simulator 테스트·실제 FPS/발열·실기기 품질 결과는 없다.**

## 6. 남은 작업과 인수 순서

1. Mac에서 모델 컴파일/번들 포함, 전체 앱·새 iOS 테스트. SDK26 기본 회귀 및 실제 SDK27 어댑터 각각 빌드.
2. 비LiDAR/지원 Pro 기기에서 입력·모드·포맷 capability 덤프, 터치/MF/잠금·AF-S·native metadata·Auto ISO 확인.
3. 실제 사진 센서/AI 깊이·매트·정렬, 머리카락·전경·유리·야간 점광원·다중 인물 블라인드 평가.
4. PhotoP 처리 시간·메모리·발열을 측정한 뒤 모델 크기/quantization·레이어 수·최대 반경을 결정.
5. 눈 AF·대상 재획득, 정밀 알파/전경색 복원, 실시간 심도·시간 안정화, 사진 재초점 UI,48MP Natural을 다음 기능으로 진행.

DSLR 조사 목록 전체(HDR 합성·focus stack·interval·C1/C2/C3·RAW 현상·Log/HDR·Cinematic Video)를 이번1차 구현에 포함했다고 주장하지 않는다. 경쟁 앱 직접 촬영 인수 전 “업계 최고 구현 완료”라고 표시하지 않는다.
