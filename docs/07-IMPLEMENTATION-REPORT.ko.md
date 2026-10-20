# 첫 개발 단계 보고

기준: 2026-10-21 KST. 작업 저장소: MetaParodica/PhotoP, 개발 브랜치 `codex/ios-camera-foundation`, Draft PR #1.

## 1. 구현 기능

SwiftUI 프리뷰, JPEG 사진 촬영, 기기에서 발견한 물리 카메라 선택, ISO·셔터·AUTO EV·수동 focus·WB 입력, 삼분할 격자, 원본 JPEG 바이트의 앱 저장, add-only Photos export와 마지막 원본 공유를 작성했다. 권한·촬영 중 변경 차단·중단·재시작의 기본 경로를 포함한다. 수동 제어의 적용 완료·센서 readout은 아직 완성되지 않았다.

## 2. 참고 소스와 라이선스

Apple AVFoundation·Photos 공식 API를 기반으로 독립 작성했다. 초기 앱에 외부 프로젝트 소스, 모델, LUT를 복사/링크하지 않았다. 후보 26개의 출처·license·우선순위·정적 검토 범위는 실사표에 기록했다. 도입 시 MIT/BSD/Apache core와 별도 LUT/모델 자산 고지를 독립 검토한다.

## 3. 기술적 접근

iOS 17, SwiftUI, 직렬 큐 소유 AVFoundation, MainActor UI, JPEG 원본 bytes 우선 저장이다. XcodeGen으로 프로젝트를 생성한다. 앱·알고리즘 전체를 공통 프레임워크로 추상화하지 않았다. Android·GPU·RAW·AI·합성은 설계 계약과 후속 phase로 남겼다.

## 4. 생성 파일

README, iOS 앱 8개 Swift 파일과 Info.plist, XcodeGen 설정, Swift 테스트 1개 파일(5 test methods), 자산 manifest·Python 검증/테스트, macOS CI, A–F 문서 7개와 저장소 조사 JSON을 추가했다. 정확한 파일 목록과 diff는 PR Files changed가 기준이다.

## 5. 실행·테스트 결과

- Linux: Python 자산 검증 회귀 테스트 7개 통과. 현재 상용 번들 LUT는 0개.
- Linux: Info.plist XML과 카메라/Photos 추가 권한 설명 확인.
- macOS CI 첫 run: XcodeGen 생성과 unsigned iPhone SDK build 통과. Xcode 16.4 / iOS 18.5 SDK가 로그에서 확인됨.
- 첫 Simulator 테스트: 앱 실행 시 카메라 usage description 누락으로 실패. XcodeGen `info.path`가 원본 plist를 재생성한 것이 원인. 해당 설정을 제거하고 생성 후·빌드된 앱의 권한 설명 검사를 추가했다.
- Simulator에서 실제 카메라 접근은 시도하지 않도록 명시했다. 모델 테스트와 하드웨어 테스트를 분리한다.
- 수정 후 CI 최종 상태: 아래 검증 기록에 갱신한다.
- 실제 iPhone 설치·촬영·EXIF·해상도·성능·발열·저장 실패·인터럽션 검증: 미수행.

## 6. 확인된 제약

현재 JPEG 전용·portrait-only이며 마지막 원본만 화면에서 공유한다. 앱 재실행 시 마지막 사진 UI 복원·전체 갤러리는 미구현이다. 앱 제거 시 앱 로컬 원본도 삭제된다. 사진 앱에 성공적으로 내보낸 파일은 별도 Photos 자산이다.

최대 해상도는 현재 activeFormat이 제공하는 최대 치수를 요청하며, 모든 가능한 activeFormat 중 센서 최대를 탐색하지 않는다. 프리뷰 60FPS를 강제/실측하지 않았다. ISP 영상 프리뷰와 JPEG 파일이 픽셀 단위로 같다고 보장하지 않는다. 수동 설정은 요청값을 표시하며 실제 ISO/셔터·AWB readout은 추후 연결한다.

RAW/ProRAW, LUT 렌더링, 장노출, HDR·night 합성, AI 구도, 영상, Android, 100+ 필름, 상용 배포 준비는 모두 미완료다. 외부 의존성의 하위 파일·모델·자산 전체 감사를 완료한 것은 아니다. 경쟁 제품 표의 미확인 셀은 기능 부재를 뜻하지 않는다.

## 7. 다음 단계

수정 후 macOS CI를 통과시킨 뒤 실제 지원 iPhone에서 preview→PRO 설정→촬영→EXIF 검증을 수행한다. 기기/포맷/렌즈별 request·actual·capabilities를 기록하고 settling·렌즈 전환·인터럽션·디스크 오류를 보완한다. Phase 1 gate 이후 공통 레시피·strict cube 파서·Metal preview/export를 시작한다.

## 최종 검증 기록

검증 코드 revision: `aa44e55937a454b0be7089e5215184bb8c71f31e`.

수정 후 [CI run 39453213994](https://github.com/MetaParodica/PhotoP/actions/runs/39453213994) 성공: XcodeGen 생성, 생성 후 Info.plist 설명 검사, unsigned iPhone SDK build, 빌드된 앱의 카메라/Photos 설명 검사, Simulator 모델 테스트, LUT 검증 단계가 모두 통과했다. 같은 revision의 push run 39453206925도 성공했다. 문서만 추가하는 후속 commit의 CI 결과는 PR checks에 별도로 표시된다.

실기기 테스트는 여전히 미수행이다. 기기 확인 전에는 Phase 1을 완료 처리하지 않는다.
