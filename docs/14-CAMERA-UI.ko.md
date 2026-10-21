# 촬영 UI 개편 · 2026-10-21

## 구현 범위

사용자가 제공한 보라색 유리 카메라 이미지를 변경 없이 리사이즈하여 iPhone AppIcon(20/29/40/60pt @2x/@3x, App Store 1024px)에 적용했다. 레이어를 분리한 Icon Composer 아이콘은 아니며 원본 정사각 이미지의 흰 배경도 유지한다.

SwiftUI 촬영 화면을 뷰파인더·도구 레일·촬영 도크로 재구성했다. ISO/셔터/EV/WB/초점은 아이콘을 눌러 같은 화면의 패널에서 선택·슬라이더로 조절한다. 슬라이더를 놓으면 기존 AVFoundation 서비스에 설정을 적용한다. 자동/수동/잠금 조합은 상호 배타적이며 카메라의 실제 지원 범위를 조회한다. UI 표시값은 요청값과 실시간 readout을 구별한다.

상단 포맷 버튼에서 HEIF/JPEG, 지원 RAW 모드, 현재 포맷의 해상도 상한, 브래킷을 변경한다. 구도와 모니터도 촬영 화면 패널에서 조정한다. LUT 강도·원본 비교·필름 마감은 같은 화면에서 조절하며 파일 가져오기/전체 스타일 탐색, 장노출의 작업 진행·재처리, 사진 편집/기록은 별도 화면을 유지한다. 미구현 플래시·가짜 줌 배율·지원하지 않는 RAW 조합은 추가하지 않는다.

## 참고 자료와 적용

- [Apple HIG · Materials](https://developer.apple.com/design/human-interface-guidelines/materials): 콘텐츠 위의 조작 계층에 재질을 사용한다.
- [Apple Design Resources](https://developer.apple.com/design/resources/): 공식 UI Kit, Camera Control 템플릿 및 시스템 글꼴/심볼을 검토했다. Figma/Sketch 원본 템플릿을 앱 자산으로 복사하거나 편집했다고 주장하지 않는다. 구현은 SwiftUI 기본 컨트롤과 SF Symbols를 사용한다.
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views): iOS 26+ 및 지원 SDK에서 `.glassEffect(.regular)`를 사용한다. iOS 17~25/이전 SDK는 `.ultraThinMaterial`로 대체한다.
- [Apple HIG · Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons): 빈번한 조작의 터치 영역 44pt 이상, VoiceOver 레이블/값, 투명도 줄이기와 동작 줄이기를 반영한다.

색상은 아이콘의 연보라색을 활성 상태에만 사용한다. 촬영 영상에는 착색 레이어를 씌우지 않는다. 프리뷰는 3:4 aspect-fit을 유지한다. 패널을 열 때도 셔터와 하단 도구의 위치는 바뀌지 않는다.

## 검증 계획과 제한

- `CameraChromeTests`: 로그 ISO/셔터 스케일의 왕복 정확도, 선형 EV, 단일 하드웨어 값, 범위 제한 및 셔터 문자열.
- `CameraInteractionTests`: 네이티브 앱 실행, 구도/ISO/포맷 패널의 열기·닫기, 촬영 버튼 유지 및 시뮬레이터에서 촬영 불가 확인.
- GitHub macOS CI에서 iPhone SDK 빌드, 전체 단위 테스트, UI 테스트, `simctl` 화면 캡처 및 xcresult 저장.
- `--ui-review`는 Debug 시뮬레이터에서만 사용하는 검토 옵션이다. 카메라 세션을 시작하지 않으며 합성 배경에 UI 검토임을 표시한다. 캡처는 실제 SwiftUI 앱 실행 화면이고, 실기기 카메라 영상·촬영 품질 검증은 아니다.
- 기존 실제 카메라 권한·수동 설정·RAW·장노출·LUT의 하드웨어 검증은 iPhone에서 별도로 수행해야 한다.
- CI 결과는 실행 후 기록한다. 디자인 목업이나 렌더링만으로 실제 앱 테스트를 대체하지 않는다.

## 실행 결과와 화면

최초 macOS runner 미배정 실패는 재시도 후 해소되었다. `ea12093`의 실행39575774557에서 iPhone SDK·Swift142·UI1·Python13은 성공했고, 별도 캡처 단계가 Shutdown 상태를 만나 실패했다. UI 테스트의 xcresult에서 실제 화면을 회수했으며 캡처 전 boot/bootstatus 처리를 추가했다.

`7a15e0d`의 실행39579967039에서 SDK·Swift149·UI1·Python17, 원본/복사 앱의 LUT30개 검사, 기본/구도 화면 캡처가 모두 성공했다. 기본 격자와 구도 선택 상태를 통일한 최종 코드 `6c569e0`의 [실행39581407493](https://github.com/MetaParodica/PhotoP/actions/runs/39581407493)도 **SDK·Swift155·UI1·Python17·자산 검사·캡처 전체 성공**이다. UI 테스트는 삼분할→숨기기→삼분할과 패널 닫기/다른 도구 열기를 실제로 조작했다.

캡처는 iPhone16 Pro/iOS18.5 Simulator, Xcode16.4에서 `simctl`로 얻은 실제 SwiftUI 앱 화면이다. PNG 원본과 보기용 JPEG를 보관하고 코드/CI/해시를 `screenshots/provenance.json`에 기록했다. 이 환경에서는 iOS17~25용 system material fallback을 실행했으며 iOS26 native Liquid Glass 분기는 미검증이다. 실제 iPhone 촬영 영상이나 실기기 품질 승인이 아니다. 검토용 합성 배경은 화면에 명시한다.

| 기본 촬영 화면 | 구도 패널 |
| --- | --- |
| ![기본 화면](screenshots/camera.jpg) | ![구도 패널](screenshots/guide.jpg) |

이번 변경은 [Draft PR #2](https://github.com/MetaParodica/PhotoP/pull/2), `codex/camera-ui-refresh`에 보관한다. 이후 실제 iPhone의 지원 범위/파일·메타데이터/Photos·패널 터치/접근성·촬영 중단을 검증한다.
