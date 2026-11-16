# iOS 17~27 카메라·AF·노출 확장 조사

직접 조회: 2026-11-16 KST. 기준: PhotoP `main dc75be6`. 상태: **Apple 공식 웹 문서 검토·설계이며 SDK 컴파일/실기기 검증이 아니다.** 사용자 요청에 따라 조사 상한을 iOS27까지 확대했다. 최소 배포 버전을27로 올리자는 제안은 아니다.

## 1. 근거의 범위

후속 확인: [Apple Xcode 지원표](https://developer.apple.com/support/xcode/)에는 조회 시 Xcode27/27.2 및 iOS27 SDK, 요구 macOS26.6 이상이 등재되어 있었다. 따라서 아래 초기 조사 당시의 SDK 배포 미확인은 이 근거로 보완한다. 현재 환경에 실제 SDK가 설치되었거나 기기/CI 검증을 통과했다는 뜻은 아니다. 후속 구현·기본 CI와27 선택 검사 상태는 [27 보고서](27-AF-NATURAL-DEPTH-IMPLEMENTATION.ko.md)를 참조한다.

Apple Developer의 공식 페이지와 같은 사이트의 `/tutorials/data/documentation/...json`을 직접 받았다. API의 Discussion과 JSON `metadata.platforms`의 iOS `introducedAt`을 확인했다. 원문 URL·수신 본문 SHA-256·플랫폼 메타데이터는 [출처 장부](research/2026-11-16-official-camera-sources.json)에 있다.

이번에 조회한 iOS27 항목은 공식 문서에서 `introducedAt: 27.0`으로 표시된다. 예시 항목의 플랫폼 메타데이터에는 beta 필드가 없었다. **beta 필드 누락은 정식 출시/일반 배포/현재 설치 가능한 SDK의 증거가 아니다.** OS27 출시 여부·지원 iPhone 목록·Xcode 배포 상태·Apple Developer 계약상의 접근 조건은 이번 문서 확인만으로 확정하지 않는다. Linux 환경에는 Xcode/iOS SDK/iPhone이 없다. 실제 채택은 사용할 SDK 선언·availability와 실기기 capability를 다시 검증해야 한다.

마지막으로 확인한 PhotoP는 iOS17+·Swift5 언어 모드다. 제안은17 기본 경로 +26 선택 어댑터 +27 선택 어댑터이며, 존재하지 않는 API를 낮은 OS에서 호출하지 않는다. 중간 버전의 모든 카메라 API를 전수 조사한 것은 아니다.

## 2. 기능별 지원 범위

| 기능/API | 공식 iOS 도입 표시 | 적용·주의 |
|---|---|---|
| `focusPointOfInterest`, `isAdjustingFocus` | 4.0 | 좌표 설정만으로 AF가 시작되지 않음; adjusting=false는 선명도 보증 아님 |
| `autoFocusRangeRestriction`, smooth AF | 7.0 | 지원 기기에서 근거리/원거리 제한·부드러운 렌즈 이동 |
| `lensPosition`, 기존 custom exposure | 8.0 | 0~1 위치는 거리 아님. duration/ISO 고정과 auto sentinel을 혼동하지 않음 |
| `VNDetectFaceLandmarksRequest`, `VNTrackObjectRequest` | 11.0 | 눈 검출·영상 좌표 추적이지 직접 렌즈 Eye AF API 아님 |
| `minimumFocusDistance` | 15.0 | mm·미확인 -1. 현재 대상 거리 아님 |
| `isFaceDrivenAutoFocusEnabled` | 15.4 | 얼굴 고려 AF. 직접 제어 시 auto-adjust 속성 및 lock 절차 필요 |
| `VNGenerateForegroundInstanceMaskRequest` | 17.0 | 객체 분할. 실제 깊이·정밀 머리카락 알파와 동일하지 않음 |
| zero shutter lag / responsive / fast capture | 17.0 | 출력의 별도 supported 플래그·실제 조합 확인 필요 |
| `focusRectOfInterest`, `minFocusRectOfInterestSize` | 26.0 | 실제 크기를 가진 AF 영역. 활성 포맷 최소 크기 준수 |
| `exposureRectOfInterest` | 26.0 | 실제 AE 영역. DSLR 모든 측광 알고리즘 선택을 뜻하지 않음 |
| `AVCaptureDeviceInput.isCinematicVideoCaptureEnabled` | 26.0 | 네이티브 시네마틱 영상 처리·긴 재구성·AF 모드 제약 |
| input `simulatedAperture` | 26.0 | 시네마틱 효과의 소프트웨어 조리개. 녹화 중 변경 불가 |
| `setCinematicVideoTrackingFocus` | 26.0 | 지원 시네마틱 구성에서 strong/weak 초점 의도 |
| `isContinuousAutoFocusTrackingEnabled` 및 format 지원값 | 27.0 | 일반 연속 AF 네이티브 추적. 시네마틱과 동시 사용 불가 |
| tracking lens-position bias / acquired | 27.0 | 깊이 프로필의 가까운/먼 부분 선호·획득 상태. 좌/우 눈 선택 아님 |
| `AVMetadataFocusTrackedObject` | 27.0 | 추적 대상 출력. 메타데이터 구독이 중요 |
| `autoISO`, `autoExposureDuration`, `autoLensAperture` | 27.0 | 시스템 AE를 유지하는 우선 모드용 특수 값 |
| 조리개 포함 custom exposure / 지원 조합 검사 | 27.0 | 가변 조리개 여부 및 각 포맷 지원 조합 확인 |
| exposure signals·native constituent lock | 27.0 | 장면별 AE 정책·가상 카메라 주 렌즈 고정 후보 |

도입 표시가 낮아도 모든 렌즈에서 지원된다는 뜻은 아니다. OS/SDK → device → active format → output/session 조합 순서로 확인한다.

## 3. iOS27 네이티브 피사체 추적 AF

핵심 근거: [isContinuousAutoFocusTrackingEnabled](https://developer.apple.com/documentation/avfoundation/avcapturedevice/iscontinuousautofocustrackingenabled).

공식 Discussion에서 확인한 동작:

1. 기본값은 false다. `activeFormat.isContinuousAutoFocusTrackingSupported`가 true여야 한다.
2. 속성을 true로 하고 focus mode를 `continuousAutoFocus`로 설정하면 현재 POI의 피사체를 잡아 추적한다.
3. `AVCaptureMetadataOutput`을 연결하고 `focusTrackedObject`를 구독해야 추적 업데이트를 받는다. 구독하지 않으면 acquired 속성은 false로 남는다고 명시한다.
4. 추적 중 `focusPointOfInterest`·`focusRectOfInterest`는 대상 움직임에 맞춰 갱신되지 않는다. 추적 UI는 메타데이터에서 얻어야 한다.
5. 가상 카메라는 `activePrimaryConstituent`에서만 추적한다.
6. 시네마틱 캡처 구성에서 true로 설정하면 예외가 발생한다. 설정에는 configuration lock이 필요하다.
7. 끌 때는 false 지정 후 continuous AF를 재적용하거나 다른 focus mode로 전환한다.

권장 절차(설계 의사코드이며 실행한 Swift가 아님):

```text
OS27와 사용 SDK 심볼 확인
  → active format의 tracking 지원 확인
  → 시네마틱 비활성·metadata output 구성 지원 확인
  → focusTrackedObject 출력 구독
  → 올바른 카메라 좌표로 사용자 target 지정
  → configuration lock 안에서 tracking on + continuous AF 재적용
  → 획득 상태 + metadata를 generation/lens/time 검증 후 UI 반영
```

`isContinuousAutoFocusTrackingSubjectAcquired`는 대상이 추적되고 있다는 뜻이다. 눈동자가 정확하게 선명하다는 보증이나 피사체 신원 정보가 아니다. [AVMetadataFocusTrackedObject](https://developer.apple.com/documentation/avfoundation/avmetadatafocustrackedobject)를 통해 화면 대상 정보를 얻는다. 지원 metadata type도 출력에서 확인한다.

PhotoP에서는 네이티브 경로가 가능하면 우선 평가하고,17~26 또는 미지원 포맷에서는 Vision 객체/눈 좌표 → AF POI의 보조 추적 경로를 사용한다. 두 컨트롤러가 동시에 POI·렌즈를 움직이지 않게 한다. 기존 구도 추적기는 안내용이며 장치 AF를 직접 제어하는 기능이 아니다.

### 3.1 깊이 프로필 bias

[continuousAutoFocusTrackingLensPositionBias](https://developer.apple.com/documentation/avfoundation/avcapturedevice/continuousautofocustrackinglenspositionbias)는 -1~1이다. 기본0은 대상 깊이 프로필의 중앙값, -1쪽은 가까운 부분, +1쪽은 먼 부분을 선호한다. 움직여도 그 bias를 유지한다.

- 변경 후 continuous AF를 재적용해야 한다.
- tracking이 false이거나 시네마틱 캡처 중 비영 값을 설정하면 예외다.
- 값은 미터·diopter·좌우 눈 ID가 아니다. “가까운 눈 우선”을 완성해 주는 단일 설정으로 표시하지 않는다.
- UI는 먼저 기본0으로 시작하고 실제 인물·사물 비교 후 고급 조절을 공개한다.

## 4. iOS26 AF/AE 영역

근거: [focusRectOfInterest](https://developer.apple.com/documentation/avfoundation/avcapturedevice/focusrectofinterest), [exposureRectOfInterest](https://developer.apple.com/documentation/avfoundation/avcapturedevice/exposurerectofinterest).

포인트 대신 위치와 크기를 설정할 수 있다. 각 supported 속성과 active format에 따른 최소 rect 크기를 확인하고 `lockForConfiguration()`을 획득한다. 범위를 벗어나거나 너무 작은 영역을 그대로 전달하면 예외가 가능하다.

이전 OS에서 화면에 S/M/L 사각형을 그리는 것과, 실제 하드웨어에 해당 AF rect를 전달하는 것은 다르다.17~25에서는 영역 내 대상 선택 후 POI를 보내는 보조 방식이라고 표시한다. 정규화 rect라도 프리뷰 방향·미러링·aspectFill 크롭 좌표 변환이 필요하다.

전체 프레임 rect를 주는 것은 범위를 지정하는 것이지, Nikon의 Matrix/Highlight-weighted 또는 DSLR의 모든 측광 방식을 선택하는 공개 인터페이스는 아니다.

## 5. iOS27 노출 우선 모드

근거: [autoISO](https://developer.apple.com/documentation/avfoundation/avcapturedevice/autoiso), [autoExposureDuration](https://developer.apple.com/documentation/avfoundation/avcapturedevice/autoexposureduration), [조리개 포함 custom exposure](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setexposuremodecustom(lensaperture:duration:iso:completionhandler:)).

기존 `current...`는 “현재 값을 잠근다”는 뜻이다. 새 `auto...`는 “시스템 AE가 그 파라미터를 계속 조절한다”는 뜻이다. 기존 `.custom`은 모두 수동이라는 PhotoP의 가정은 새 모델에서 더 이상 성립하지 않을 수 있다.

| 제안 모드 | 노출 시간 | ISO | 물리 조리개 | 조건 |
|---|---|---|---|---|
| S/Tv | 고정 | Auto | Auto 또는 현재 고정 | 해당 조합 지원 확인 |
| M + Auto ISO | 고정 | Auto | 고정/현재 | 시스템 AE gain 제어 유지 |
| A/Av | Auto | Auto 또는 별도 고정 | 지정 | 실제 가변 조리개·조합 지원 시에만 |
| P 계열 | Auto | Auto | Auto | 모든 조합·명칭을 실제 지원과 대조 |
| 완전 M | 고정 | 고정 | 고정/현재 | 기존 수동 계약과 노출 적용 검증 유지 |

[supportsExposureModeCustom(lensAperture:duration:iso:)](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/supportsexposuremodecustom(lensaperture:duration:iso:))로 조합을 검증해야 한다. Current sentinel로 locked/auto의 일반적인 조합도 질의할 수 있다. 고정 조리개 장치에서는 ApertureAuto와 ApertureCurrent의 지원이 동등하다고 명시한다.

지원되지 않는 조합에 대해 앱이 AE를 고빈도로 흉내 내는 것을 우선 해법으로 삼지 않는다.17~26은 기존 AUTO/M 또는 명시적으로 제한된 소프트웨어 보조로 남기고 시스템 우선 모드와 구분한다.

### 5.1 물리 조리개와 가상 f값

공식27 문서는 포맷의 `minLensAperture`·`maxLensAperture`·`recommendedLensApertureStops`를 노출한다. 이것만으로 특정 iPhone에 가변 조리개가 탑재되었다고 단정하지 않는다.

데이터 모델은 다음을 분리한다.

- `opticalAperture`: 장치 실제 값/지원 범위. 광량·광학 심도에 관여.
- `simulatedAperture`: PhotoP/네이티브 시네마틱의 가상 심도. 실제 센서 광량을 바꾸지 않음.
- 사용자 렌즈 프로필의 기준 f값: 가상 렌즈 모델 파라미터.

기존 PRO f값을 자동으로 물리 조리개 제어로 바꾸지 않는다. 고정 렌즈에서 소프트웨어 f11을 선택해도 실제 f11 노출·회절이 생기는 것은 아니다.

### 5.2 프리뷰·캡처·콜백

27 custom exposure 문서는 auto 파라미터가 있을 때 프리뷰 노출 시간이 `activeMaxExposureDuration`으로 제한되면서 사진에서는 전체 시간이 적용될 수 있다고 설명한다. 모든 값이 고정이면 영상 프레임 길이에 영향을 줄 수 있다. 프리뷰와 사진 EXIF가 언제나 같다고 보장하면 안 된다.

완료 콜백은 장치 clock 기반 첫 적용 버퍼 timestamp다. 프레임 clock으로 변환 없이 비교하지 않는다. 요청 ID·렌즈 generation·timeout을 계속 사용한다.

고정 노출을 사진에서도 지키려면 `photoQualityPrioritization = .speed`가 필요하다는 문서 제약을 유지한다. `.balanced`에서는 저조도 다중 프레임 처리가 ISO/시간을 바꿀 수 있다. 문서는 speed가 이미지 안정화를 비활성화하고 안정화를 다시 켜면 고정값 계약을 무너뜨릴 수 있다고 설명한다. 실제 EXIF·품질 차이는 기기 인수 대상이다.

## 6. iOS27 AE 장면 신호

근거: [AVCaptureDeviceExposureSignal](https://developer.apple.com/documentation/avfoundation/avcapturedeviceexposuresignal), [enabledExposureSignals](https://developer.apple.com/documentation/avfoundation/avcapturedevice/enabledexposuresignals).

직접 읽은 개별 공식 항목:

| 신호 | 문서 설명 요지 | 오해하지 말 것 |
|---|---|---|
| `subjectMotion` | 움직임이 많으면 조리개/노출 시간을 조절해 흔들림을 줄일 수 있음 | 스포츠 AF 속도·최소 셔터 보장 아님 |
| `groupPhoto` | 여러 얼굴에서 조리개를 조여 심도를 늘릴 수 있음 | 소프트웨어 얼굴별 무한 초점 기능 아님 |
| `flicker` | 조리개·시간을 활용해 인공 조명 주파수와의 문제를 피하도록 AE가 조절할 수 있음 | 50/60Hz 완전 제거·모든 LED 대응 보장 아님 |
| `starburst` | 조리개를 열어 점광원의 회절 아티팩트를 줄일 수 있음 | 별 모양 광원을 합성하는 필터가 아님 |

`document` 항목은 상위 공식 목록에서 확인했지만 별도 Discussion을 읽지 않았으므로 동작을 추정하지 않는다. `supportedExposureSignals`의 부분집합만 enabled에 넣고, 수동 설정 시 `automaticallyEnablesExposureSignals=false`와 configuration lock이 필요하다. 자동 활성 상태에서 직접 지정하면 예외다. `activeExposureSignals`는 AE가 현재 장면에서 고려하는 특성이지 앱의 확정적인 사물 분류 결과가 아니다.

## 7. iOS26+ 네이티브 Cinematic Video는 별도 모드

근거: [isCinematicVideoCaptureEnabled](https://developer.apple.com/documentation/avfoundation/avcapturedeviceinput/iscinematicvideocaptureenabled), [simulatedAperture](https://developer.apple.com/documentation/avfoundation/avcapturedeviceinput/simulatedaperture), [tracking focus](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setcinematicvideotrackingfocus(at:focusmode:)).

- input의 supported 확인 후 설정한다. 활성화는 긴 렌더 파이프라인 재구성이 필요하므로 셔터/녹화 직전 임의 토글하지 않는다.
- movie output뿐 아니라 video data output·metadata·preview layer에도 시네마틱 효과가 적용될 수 있다고 명시한다. 기존 분석 입력이 무보정이라는 가정을 그대로 유지할 수 없다.
- 활성화하면 continuous AF로 전환되며 일반 focus mode 변경은 허용되지 않는다. 기존 MF/AF-S를 동시에 적용하면 예외가 가능하다.
- 지원 범위 내 simulated aperture를 **녹화 시작 전** 설정해야 한다. 녹화 중 변경은 예외다. 하단 f값을 녹화 중 자유롭게 조절하는 UX를 이 API만으로 약속하면 안 된다.
- strong/weak focus 의도와 대상 선택을 지원하지만 별도 구성·메타데이터 검증이 필요하다.
- 27 일반 continuous AF tracking과 동시 사용하지 않는다.

사진용 PhotoP 맞춤 보케, 일반 영상, 네이티브 시네마틱 영상을 구분한다. 네이티브 효과 위에 PhotoP 심도를 다시 굽는 이중 처리를 막는다. 기존 영상의 “무보정 저장” 계약을 유지하려면 새 영상 모드를 명시적으로 선택하도록 해야 한다. 줌/FPS/해상도·LUT·안정화 동시 지원은 포맷별 실측 전 미확정이다.

## 8. 주 렌즈 고정과 촬영 반응성

27 [주 constituent 고정](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setprimaryconstituentdeviceswitchingbehaviorlockedwith(_:))은 별도 지원값·configuration lock을 요구한다. 고정 뒤 virtual camera의 일부 속성은 그대로이고 실효 값은 active constituent에서 얻어야 한다. 줌 범위가 바뀌면 현재값/램프가 clamp·취소될 수 있다. 따라서 “절대 화각 변화 없음”을 보장하지 않는다. 기존 물리 렌즈 선택과도 구분한다.

17부터의 [zero shutter lag](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/iszeroshutterlagenabled), [responsive capture](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/isresponsivecaptureenabled), [fast capture prioritization](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/isfastcaptureprioritizationenabled)은 기회가 있다. 단, 조사한 속성 문서의 짧은 설명만으로 RAW·깊이·고해상도·브래킷의 모든 조합을 허용한다고 추정하지 않는다. 기존 capture transaction은 단일 진행 요청 중심이므로 단순 플래그 추가가 아니라 제한된 다중 요청·메모리·취소 정책을 먼저 설계한다.

## 9. 구현·검증 게이트

1. 사용할 Xcode/SDK에27 심볼이 실제 있는지 확인한다. `#available`만 추가해도 오래된 SDK가 새 심볼을 컴파일할 수 있는 것은 아니다. 새 플랫폼 타입을 독립 어댑터에 격리하고 SDK별 소스/빌드 구성을 운영한다.
2. 최소 배포17 유지,17/26/27 런타임 분기와 미지원 fallback을 프로토콜·순수 정책 테스트로 검증한다.
3. lens/format/session 변경 때 tracking·ROI·노출 조합·metadata·조리개 범위를 다시 조회한다. OS 버전만으로 UI를 켜지 않는다.
4. AF/AE/수동 잠금/시네마틱을 단일 소유자로 직렬화한다. 기존 settings.pending·capture timeout과 충돌하지 않게 한다.
5. 기기별 raw capability, 지원된 요청, 실제 적용값, 사진 EXIF, 오류/성능을 따로 기록한다. 불확실한 지원 목록을 제품 사양으로 고정하지 않는다.
6.17 기본 촬영·LUT·RAW·LONG 회귀,26 ROI/시네마틱,27 native tracking/우선 노출/렌즈 고정을 각각 검증한다.

필수 테스트: metadata 미구독 acquired 상태, 대상 가림/재획득, 렌즈·줌·회전, 시네마틱과27 tracking 상호 배제, 기록 중 f값 금지, unsupported 조합 UI 차단, 사진/프리뷰 노출 차이, 늦은 콜백 무시, background·중단 복구.

## 10. 결론

27까지 조사하면 설계 우선순위가 바뀐다. **지원 기기에서는 네이티브 추적 AF와 시스템 우선 노출을 먼저 활용하고, 미지원 환경을 Vision/기존 AUTO·M으로 보완**하는 것이 맞다. 반면 맞춤형 사진 보케·머리카락 매팅·비파괴 재초점은 별도 엔진 과제로 남는다.

이 보고서는 공식 문서 확인을 완료한 범위와 제안이다. 실제 API 호출·컴파일·기기별 지원·OS27 출시 상태를 검증한 결과는 아니다.
