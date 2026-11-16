# AF·DSLR 촬영 기능 추가 개발 조사 보고서

작성·공식 웹 문서 직접 조회: 2026-11-16 KST. 기준: 원격 `main dc75be6f6a8cc656976b030d64fd9f595c3991f4`. 범위: **추가 기능 조사·실행 계획 저장**. 앱 기능 구현·커밋·푸시·병합은 이번 요청에 포함하지 않았다.

## 1. 결론

우선 개발 가치는 AF-S/AF-C/AF-ON, 독립 AF/AE 지점, 눈·피사체 추적, MF 확대, 촬영 반응성이다. 이 기능들은 최고 수준의 소프트웨어 심도와 같은 초점 대상·좌표 계약을 공유해야 한다.

iOS27 공식 문서를 확인한 결과, 지원 포맷에서 일반 연속 피사체 추적 AF와 시스템 Auto ISO/시간/조리개 우선 모드를 사용할 수 있는 설계 경로가 확인됐다. 모든 기능을 자체 AI와 AE 제어 루프로 다시 만들기보다 네이티브 우선·미지원 fallback을 권장한다. 상세 API·가용성·상호 배제는 [26 보고서](26-IOS17-27-CAPABILITY-RESEARCH.ko.md), 보케 구현은 [24 계획](24-SOFTWARE-DEPTH-DEVELOPMENT-PLAN.ko.md)을 따른다.

## 2. 원격·자료 접근 및 근거 구분

- 원격: `https://github.com/MetaParodica/PhotoP.git`. `git ls-remote origin refs/heads/main` 성공, 원격/로컬 main SHA 일치. 작업 시작 시 작업 트리는 깨끗했다. 토큰·SSH 키를 새로 만들거나 원격을 변경하지 않았다.
- 초기 네트워크 제한에서 Apple/Leica는 proxy CONNECT403이었다. 사용자가 네트워크를 활성화한 뒤 현재 정책 unrestricted/enforced 및 공식 URL HTTP200을 확인했다.
- Leica·Apple·Sony·Nikon의 공식 페이지 본문, Apple 공식 DocC JSON을 직접 읽었다. [출처 장부](research/2026-11-16-official-camera-sources.json)는 수신 본문 hash와 플랫폼 정보를 보관한다.
- 공식 문서의 기능 설명과 PhotoP 소스 관찰, 앞으로의 제품 제안을 구분한다. 제조사의 성능·마케팅 문구를 자체 실측으로 바꾸지 않는다.
- iOS27 문서의 존재는 현재 사용할 SDK·지원 iPhone·OS 출시 상태의 증거가 아니다. 이번 환경에는 iOS SDK/실기기가 없다.

## 3. 현재 코드에서 확인한 기능과 공백

| 항목 | 현재 코드 근거 | 판정 |
|---|---|---|
| 연속 AF | `CameraService.applyOnQueue`의 `.continuousAutoFocus` | 있음. 독립 AF-C 제품 정책은 없음 |
| 터치 AF/AE | `CameraPreview.Coordinator.meter`, `CameraService.focusAndMeter` | 있음. 같은 탭에서 두 지점을 함께 지정 |
| 길게 눌러 잠금 | `scheduleMeteringLock`/`pollMeteringLock` | 있음. 약50ms 간격·최대 약2초 안정화 대기, 실제 초점 정확도 판정은 아님 |
| MF·AF/AE/WB 잠금 | `FocusSettings`, `CameraSettingsValidator`, service 제어 콜백 | 있음. lensPosition은0~1 정규 위치 |
| 초점 표시 | `CameraView`의 metering target, 장치 readout | 요청 표적/잠금 표시. 광학 선명도 확정 표시가 아님 |
| 피킹 | 실시간 모니터의 대비/에지 기반 표시 | 있음. 실제 초점 거리·깊이 평면 표시 아님 |
| 인물·얼굴 검출/구도 추적 | `CompositionAnalyzer`, `CompositionSubjectTracker` | 있음. 얼굴 중심을 쓰며 눈 landmark나 AF 액추에이터 제어가 아님 |
| 터치 심도 위치 | `CameraModel.selectCompositionSubject(at:)` | AI 가이드가 꺼져 있어도 depthFocusPoint는 저장. AF 지점과 좌표 공간이 다르므로 통합 계약 필요 |
| 눈 AF·피사체 AF | landmark/native tracking/AF target 연동 호출 없음 | 추가 개발 |
| AF-S·AF-ON·영역 크기 | 독립 상태·조작 및 hardware rect 호출 없음 | 추가 개발 |
| MF 확대·A/B 랙 포커스·포커스 브래킷 | 관련 촬영 흐름 없음 | 추가 개발 |
| 노출·RAW·모니터 | 수동 ISO/셔터/WB/EV, RAW/ProRAW, 히스토그램/제브라 | 있음. RAW clipping/광학 f값 제어 아님 |
| 노출 브래킷 | `ExposureBracketPlan`: AUTO processed·3장, ±0.5~2EV·지원 범위 | 있음. HDR 합성·focus stack과 별개 |
| 촬영 속도 | 단일 capture transaction·busy 보호 | 있음. burst/ZSL/responsive capture의 새 요청 스케줄러는 없음 |

`rg`로 확인한 현재 소스에는 focus/exposure rect, face landmark, smooth AF, AF range restriction, zero shutter lag/responsive capture의 직접 호출이 없다. OS 기본값으로 동작할 수 있는 기능과 앱이 명시적으로 제어·검증하는 기능은 구분한다.

### 현재 동작에서 먼저 결정할 정책

1. `focusAndMeter`는 focusLocked를 false로 전달하여 탭이 기존 MF/잠금을 해제하고 AF로 전환할 수 있다. 버그라고 단정하지 않지만, AF-ON·추적 도입 전에 “탭이 잠금을 해제하는가”를 명시해야 한다.
2. 탭 표시가 장치 요청 완료 전에 생성된다. 노란 박스를 “초점 성공”으로 설명하면 안 된다.
3. readout의 `isAdjusting`는 AF/AE/AWB의 OR이고 최대4Hz다. 정밀 AF 상태·시간 측정에는 AF 전용 관찰·타임스탬프가 필요하다.
4. 구도 AI 활성 여부와 AF 분석 수요를 분리한다. 구도를 껐다고 눈 AF가 꺼지거나, 분석 보조 끄기가 사용자 잠금을 바꾸면 안 된다.

## 4. 공식 카메라 매뉴얼에서 얻은 제품 요구

### 4.1 Sony: 눈 우선과 눈 전용은 다르다

[α7 IV 공식 Eye AF 가이드](https://helpguide.sony.net/ilc/2110/v1/en/contents/TP1000657952.html)는 얼굴/눈 우선 AF와 커스텀 키 Eye AF의 차이를 설명한다. 전자는 눈이 없으면 다른 피사체로 초점을 옮길 수 있고, 후자는 얼굴/눈에 한정하는 동작이 있다.

PhotoP 적용 제안: 눈을 잃으면 얼굴→몸으로 부드럽게 전환하는 “눈 우선”과, 사용자가 명시한 눈 대상이 없으면 유지·대기하는 “눈 고정”을 구분한다. 모델이 눈을 못 찾았다고 배경으로 즉시 이동하지 않는다. Sony의 검출 수·성능을 PhotoP의 사양으로 복사하지 않는다.

[공식 AF-ON 설명](https://helpguide.sony.net/ilc/2110/v1/en/contents/TP1000657960.html)은 반셔터 없이 초점을 맞추는 조작을 명시한다. iPhone에는 DSLR 반셔터가 기본적으로 없으므로, 하단/엄지 위치의 별도 AF-ON과 셔터 동작 분리를 설계한다. 외부 버튼은 실제 하드웨어/API 지원을 별도 검증한다.

### 4.2 Nikon: 추적 이탈과 촬영 우선순위

[Z8 AF Activation](https://onlinemanual.nikonimglib.com/z8/en/csma_af_activation_209.html)은 Shutter/AF-ON과 AF-ON only, focus/release priority를 구분한다. [Focus Tracking with Lock-On](https://onlinemanual.nikonimglib.com/z8/en/csma_focus_tracking_with_lock-on_206.html)은 앞을 가로지르는 물체에 즉시 반응할지 기존 대상을 유지할지를 설정한다.

PhotoP에서는 대상 유지 시간·재획득 조건·셔터 대기 상한이 필요하다. 다만 AVFoundation의 adjusting/acquired를 DSLR의 확정적인 초점 성공 신호와 동일시할 수 없으므로 “초점 안정 우선”은 제한된 보조 정책으로 설명하고 수동 강제 촬영을 제공한다.

[Z8 Focus Shift Shooting](https://onlinemanual.nikonimglib.com/z8/en/psm_focus_shift_shooting_155.html)은 초점 위치를 바꿔 여러 장을 찍고, 나중에 focus stacking으로 합칠 수 있다고 설명한다. **촬영 시퀀스와 합성은 별도 기능**이다. 첫 프레임 노출 잠금·촬영 간격·원래 초점 복원도 참고할 요구다. Z8의300장/촬영 속도를 iPhone 목표로 그대로 사용하지 않는다.

[Z8 Interval Timer](https://onlinemanual.nikonimglib.com/z8/en/psm_interval_timer_shooting_153.html), [Metering](https://onlinemanual.nikonimglib.com/z8/en/psm_metering_141.html)도 직접 조회했다. interval은 현재 LONG 샘플 합성과 별도 흐름이고, DSLR의 측광 방식 선택은 iPhone의 POI 설정만으로 동일 구현이 아니다.

## 5. 추가 AF 기능 우선순위

| 우선순위 | 기능 | 구현 방향·제약 |
|---|---|---|
| P0 | AF-S/AF-C/MF와 잠금 상태 모델 | 요청 수락·탐색·안정 추정·잠금·유실·실패를 구분. 연속 AF와 일회성 AF를 명시 |
| P0 | AF/AE 분리·AF-ON | 탭 초점과 드래그 측광, 독립 잠금. 사용자 MF/AE/WB 보호 |
| P0 | MF 확대·피킹 개선 | 3×/5×/10× 디지털 확대 후보. 원본 미보정 영역 사용, 손떨림·노이즈 오검출 제한 |
| P1 | 피사체 추적 AF |27 native+metadata 우선, 그 외 Vision target→POI. 다른 컨트롤러와 동시 구동 금지 |
| P1 | 눈 우선/선택 눈 | Vision landmark·신뢰도·좌우 좌표 정의. face-driven AF를 Eye AF라고 이름 붙이지 않음 |
| P1 | AF 영역 S/M/L·Zone |26 hardware rect,17~25 대상 선택 영역+POI fallback. 실제 지원 크기 검사 |
| P1 | 대상 유지·가림 복구 | confidence·시간·움직임으로 identity 유지, 겹친 사람에게 바로 넘기지 않음 |
| P1 | 근거리/원거리 AF 제한 | 지원 시 native range restriction. 임의 미터 범위·무한대 보장 아님 |
| P2 | A/B 랙 포커스·smooth AF | 지원 시 느린 AF 또는 제한된 lens-position 이동. 지속 시간·완료값 측정 |
| P2 | 포커스 브래킷·합성 | 먼저 안전한 시퀀스·manifest, 이후 정렬·focus breathing 보정·stack |
| P2 | 재초점·다중 인물 초점 보조 | 심도 recipe와 연결. 촬영 후 재초점은 가상 흐림 변경이며 기록되지 않은 디테일 복원이 아님 |
| 연구 | 동물/새/차량 등 유형별 AF | 실제 검출 모델·데이터·권리·성능 평가 후. 범용 분할만으로 종별 AF를 완료 처리하지 않음 |

### 눈 AF의 구체적 설계

- `VNDetectFaceLandmarksRequest`의 눈 영역을 사용한다. 현재 얼굴 박스 중심을 눈 위치로 대체 표시하지 않는다.
- “화면 왼쪽”과 “피사체의 왼눈”을 구분하고 미러링·회전을 테스트한다.
- 작은 얼굴/선글라스/측면/가림은 신뢰도 기반으로 얼굴 또는 사용자가 선택한 대상에 복귀한다.
- 눈 지점 이동을 매 프레임 장치에 보내면 AF hunting이 커질 수 있다. 이동 임계값·시간 제한·장치 조정 상태·사용자 입력 우선순위를 적용한다.
-27 native bias는 대상의 가까운/먼 깊이 선호이며 좌우 눈 선택 명령이 아니다. 정확한 눈 선택은 시각적 대상 선택·재획득 정책과 함께 검증한다.
- 심도 초점면과 광학 AF는 동일 target identity를 공유하되, 실제 초점이 실패했는데 소프트웨어만 선명하게 만들었다고 표시하지 않는다.

### 수동 초점·보조 표시의 정직한 범위

[Apple lensPosition 문서](https://developer.apple.com/documentation/avfoundation/avcapturedevice/lensposition)는0~1이 물리 거리와 대응하지 않고, 장치 간 동일 거리도 아니며,1.0도 무한대가 아니라고 명시한다. 따라서 MF 슬라이더를 임의의 미터 눈금으로 바꾸지 않는다.

[minimumFocusDistance](https://developer.apple.com/documentation/avfoundation/avcapturedevice/minimumfocusdistance)는 최소 거리(mm)이며 현재 대상 거리나 lensPosition 보정표가 아니다. 실제 거리는 절대 깊이·보정·신뢰도가 있을 때만 근사 표시한다. 피킹은 대비·노이즈에 반응하므로 확정 초점 판정이 아니다.

## 6. AF 엔진·안전 설계

제안 구성:

```text
사용자 탭/AF-ON/눈 선택
          ↓
FocusIntent + target ID + lens/format generation
          ↓
FocusCoordinator(단일 소유자)
  ├─27 native tracking + metadata
  ├─17+ Vision-assisted POI
  └─AF-S / MF / 잠금
          ↓
CameraService 직렬 장치 적용
          ↓
실제 장치 관찰 + timestamp → 상태 UI·심도 초점 대상
```

상태는 최소 `idle → acquiring → tracking/settledEstimate → locked`, 유실 시 `temporarilyLost → reacquiring/idle`, 오류 시 `failed`로 나눈다. `settledEstimate`는 선명도 인증이 아니다. `isAdjustingFocus=false`, 추적 acquired=true, Sobel peak 중 어느 하나도 완벽한 초점 성공 신호로 쓰지 않는다.

요청 우선순위: 사용자 MF/잠금/터치 > 명시적 AF-ON/대상 전환 > 자동 추적 > 구도 제안. 렌즈·세션·방향·줌 변화는 좌표/작업 generation을 갱신하고 늦은 결과를 버린다. 수동 노출·화이트밸런스는 AF가 바꾸지 않는다. 사진/RAW/브래킷/LONG/녹화 상태와 충돌할 때 중지·복구 정책을 명시한다.

분석 자원은 AF·심도·구도·리뷰가 공유하므로 예산과 우선순위를 조정한다. 모든 모델을 프레임마다 실행하지 않는다. AF target 처리에 구도 AI 활성 토글을 재사용하지 않는다. 새로운 metadata output과 기존 video/photo output의 동시 지원도 실기기에서 확인한다.

## 7. AF 외 DSLR 기능 조사와 권고

| 기능 | 현재와 차이 | 실현 방식·주의 | 순서 |
|---|---|---|---|
| 셔터 우선·M+Auto ISO | 현재 AUTO/완전 수동 위주 |27 auto sentinel·지원 조합 우선, 낮은 OS fallback 별도 | P1 |
| 실제 조리개 우선 | 현재 PRO f는 가상 흐림 |27의 가변 aperture 지원 포맷에서만. 고정 렌즈는 진짜 Av 불가 | 조건부 P2 |
| 사용자 C1/C2/C3 | 룩 프리셋은 있으나 전체 촬영 설정 프리셋과 별개 | 렌즈/모드/AF/노출/WB/가상심도 저장, 복원 시 capability 재검사 | P1 |
| 빠른 촬영·제한 burst | 현재 single transaction |17+ ZSL/responsive/fast 지원 검사, 동시 요청 수·메모리·저장 backpressure | P1 |
| MF 확대·정밀 노출 표시 | 피킹·히스토그램 있음 | 확대 ROI, RGB waveform/false color 후보. SDR 기준·RAW clipping 아님 표시 | P1~2 |
| 측광 지점/영역·하이라이트 보호 | 현재 POI·EV·제브라 |26 AE rect·기존 POI 활용, 소프트웨어 EV 제안과 hardware meter 구분 | P1~2 |
| 움직임 대응·플리커 보조 | 일반 코치·셔터 제안 일부 |27 AE signals 평가. 모든 LED/주파수 완전 제거 보장 금지 | P2 |
| 포커스 브래킷/스태킹 | 노출 브래킷3장과 별개 | 렌즈 위치 시퀀스→정렬→선명 영역 합성. 움직임/호흡/halo 검증 | P2 |
| HDR·노출 합성 | 현재3장 원본 저장 | 정렬·ghost 처리·노출 메타데이터·톤매핑. LUT 단계와 별도 | P2 |
| 인터벌·타임랩스 | LONG은2fps/1280px 샘플 합성 | 고해상도 사진 시퀀스·간격·저장예산·중단 복구. iOS background 지속 보장 불가 | P2 |
| A/B 포커스 영상 | 현재 video 무보정 | lens position 곡선·smooth AF, native cinematic 제약과 구분 | P2 |
| 네이티브 Cinematic Video | 현재 일반 SDR 영상 |26 별도 모드·정해진 조리개/AF 제약. 기존 LUT/심도 이중 처리 방지 | 조건부 P2 |
| 노이즈 저감·다중 프레임 | 현재 LONG 평균은 제한적 | full-res 정렬·움직임 마스크·원본 보존·야간 IQ 실측 | P3 |
| 손떨림/수평·렌즈 보정 | 수평·지원 안정화 일부 있음 | 능동 OIS 구동을 가정하지 않고 제공 API/메타데이터 활용 | P2~3 |
| RAW 현상·Log/HDR/고급 코덱 | 현재 명시적으로 미구현 범위 | 별도 색 관리·센서/코덱/저장·기기 조합 검증 후 | 별도 대형 과제 |

백버튼/커스텀 컨트롤·외부 그립·볼륨 버튼은 현재 Apple 입력 API 및 접근성 충돌을 따로 조사해야 한다. 이번에 외부 하드웨어 제어까지 검증한 것은 아니다.

### 휴대폰 소프트웨어로 그대로 구현할 수 없는 기능

- 기계식 셔터·실제 ND·대형 센서·임의 렌즈 교환을 UI로 만들 수 없다.
- 고정 조리개 카메라의 광량을 소프트웨어 f값으로 조절할 수 없다.27 API가 있어도 hardware capability가 필요하다.
- DSLR 위상차 센서의 원시 AF 포인트/내부 모터 루프에 접근한다고 가정하지 않는다.
- 삼각대 센서 pixel shift를 OIS 임의 이동으로 구현한다고 주장하지 않는다. 정렬·다중 프레임 super-resolution은 별도 기술이다.
- 스마트폰의 최대 센서 노출을 넘는 진짜 Bulb를 샘플 합성과 동일하게 표시하지 않는다.
- 디지털 배경 흐림으로 촬영 위치·망원 원근감·기록되지 않은 피사체 디테일을 복원할 수 없다.

## 8. 통합 개발 순서

### A. 상태·조작 기반(P0)

FocusSettings의 bool 조합을 AF mode/잠금/target 의도로 정리하고 실제 장치 readout과 요청 상태를 분리한다. 독립 AF/AE·AF-ON·MF 확대·좌표 변환·대상 표시 정책을 먼저 확정한다. 기존 수동·잠금·RAW·LONG·LUT 회귀 테스트를 통과해야 한다.

### B. 가장 가치가 큰 네이티브 기능(P1)

27 native AF/metadata와 S/M+Auto ISO,26 rect,17 ZSL/responsive를 작은 호환성 실험으로 확인한다. 동시에17+ Vision 눈·객체 보조를 준비한다. 특정 OS/렌즈가 실패해도 기본 촬영은 유지한다. C1/C2/C3 및 지원 조합 표를 연결한다.

### C. 심도 엔진과 결합

실제 AF 대상과 가상 초점면의 target identity·시점·좌표를 공유한다. 정지 사진 경계/가림 품질을 먼저 확보하고, 이후 실시간 심도·LUT·AF 공존을 최적화한다. 전체 Phase는24 계획을 따른다.

### D. 시퀀스·영상·고급 처리(P2~3)

포커스 브래킷→스태킹, HDR, interval, 랙 포커스·별도 cinematic 순서로 확장한다. RAW 현상/Log/HDR은 작은 UI 항목이 아니라 별도 파이프라인 과제다.

## 9. 검증 항목

- 순수 정책: 모드 전이·잠금 우선순위·대상 유실·fallback·렌즈 generation·지원 조합.
- 좌표: 앞/뒤 카메라, portrait/landscape, aspectFit/fill, 줌·크롭·미러링, 눈 좌우·metadata rect.
- 장치 AF: 저조도·저대비·역광·작은 눈·안경·2명 교차·가림·빠른 접근·최소거리 밖.
-17/26/27: 낮은 OS 새 심볼 미호출, 미지원 rect/metadata 차단, native/Vision 이중 소유 금지, cinematic/tracking 상호 배제.
- 노출: AF가 수동 ISO/셔터/AE/WB 잠금을 바꾸지 않음, auto priority의 실제 적용과 EXIF 검증.
- 촬영: focus priority 대기 상한·강제 촬영·취소, AF-ON 사용 후 재구도, RAW/브래킷/LONG 복구, burst 저장 압력.
- 성능: 입력→대상 표시 지연, 재획득 시간, 틀린 대상 전환율, hunting 횟수, 지속 발열·전력·메모리. 수치는 실측 전 약속하지 않음.
- 복구: 전화/카메라 중단·background·렌즈 해제·metadata 만료·늦은 콜백·재시작 recipe 재현.

## 10. 이번 산출물과 후속 승인 범위

이번에는 원격 연결 확인·코드/공식 자료 조사·보고서 저장만 수행한다. 앱 소스·테스트·의존성·가중치는 변경하지 않는다. 경쟁 앱 실측과 iOS SDK/기기 검증은 아직 없다. 새 기능 구현·모델 탑재·푸시/메인 병합은 별도 요청 시 진행한다.
