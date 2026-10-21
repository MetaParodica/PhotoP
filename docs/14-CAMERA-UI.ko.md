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

## 이번 실행 결과

- Linux 로컬: Python 검사 **13개 성공**(기존 LUT 11개 + 새 아이콘 무결성 2개). 아이콘 9개 슬롯의 실제 PNG 크기·알파 채널 부재·원본 변환 해시를 확인했다.
- GitHub [실행 39574960735](https://github.com/MetaParodica/PhotoP/actions/runs/39574960735): 최초 실행과 실패 작업 재시도 모두 runner 미배정(`runner_name` 빈 값), `steps: []` 상태로 종료했다. 작업 로그도 생성되지 않았다. 연결 도구는 주석 상세 조회를 지원하지 않아 근본 원인은 미확인이다.
- **현재 변경의 SDK 빌드·Swift 3개 신규 단위 테스트·UI 테스트·네이티브 실행 캡처는 미실행이다.** 기존 커밋에서 성공했던 Swift 139개 결과를 이번 UI 변경의 성공으로 계산하지 않는다.
- macOS 작업을 실행할 수 있게 되면 기존 워크플로가 빌드·테스트·두 화면 캡처·artifact 업로드를 수행하도록 구성했다. 실제 실행 사진은 아직 생성되지 않았다.
- 앞서 요청한 외부 LUT 추가·비 LUT 효과 확장은 수집/로컬 초안 상태를 유지한다. 이번 UI 단계의 자동 검증이 막혀 있으므로 다음 단계 완료로 처리하지 않는다.
