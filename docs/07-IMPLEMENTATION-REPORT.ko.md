# 현재 개발 단계 보고

기준: 2026-10-21 KST. 작업 저장소: MetaParodica/PhotoP, 개발 브랜치 `codex/ios-camera-foundation`, Draft PR #1.

## 1. 현재 상태 확인

재개 시 최신 revision은 `1a9dbae0e2a6b711cd346429e1048cb55cb220a4`였다. PR #1은 열려 있고 main에는 초기 README만 있으며 기능 코드는 개발 브랜치에 있다. 이 revision의 macOS CI run 39453856953 / 39453849981은 성공했다. 기존 앱은 SwiftUI preview·JPEG·물리 렌즈·PRO 입력·격자·원본 보관/Photos export를 포함했다.

## 2. 이번 구현

- custom/locked 노출에서 ISO·셔터를 보존하도록 사진 우선순위를 speed로 선택한다. AUTO는 quality를 유지한다.
- 설정 적용은 노출/EV, 수동 초점, 수동 WB의 완료 콜백을 모두 기다린다.
- 작업 UUID·step 집합으로 중복·순서 역전·중단 후 이전 콜백·이전 timeout을 구별한다.
- 설정 변경 중 촬영·렌즈 전환을 차단한다. 중단/백그라운드/오류는 대기를 종료하고 timeout은 카메라 정지 후 재시작을 안내한다.
- ISO·셔터·EV·정규화 렌즈 위치·WB 추정값과 조정 상태를 4Hz로 표시한다. 편집 가능한 요청값과 구분한다.
- snapshot revision으로 UI에 늦게 도착한 과거 상태를 무시한다.
- 수동 WB는 custom device gains 지원 여부까지 확인한다.

## 3. 참고 자료와 접근

Apple AVFoundation 공식 API를 기반으로 독립 작성했다. 외부 라이브러리나 LUT/모델 파일을 추가하지 않았다.

- [Custom exposure](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setexposuremodecustom(duration:iso:completionhandler:)): manual/locked 노출과 사진 품질 우선순위 계약.
- [Focus completion](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setfocusmodelocked(lensposition:completionhandler:)): 변경 완료 콜백.
- [WB custom gains](https://developer.apple.com/documentation/avfoundation/avcapturedevice/islockingwhitebalancewithcustomdevicegainssupported): 수동 게인 지원 조건.

기존 직렬 큐·MainActor 구조를 유지한다. CameraControlApplication은 콜백 집계와 취소를 하드웨어 없이 검증하는 작은 값 타입이다. 범용 카메라 프레임워크나 별도 서비스 추상화는 추가하지 않았다.

## 4. 생성·수정 파일

새 파일: CameraControlApplication.swift, CameraReadoutView.swift, CameraControlApplicationTests.swift.

수정: CameraService.swift, CameraTypes.swift, CameraModel.swift, CameraView.swift, ManualControls.swift와 README·기술 설계·로드맵·검증 문서. 전체 diff는 PR Files changed가 기준이다.

## 5. 실행·테스트

재개 작업의 로컬 실행 환경은 사용할 수 없어 코드 수정은 GitHub에 직접 반영하고 macOS CI로 빌드·테스트했다. 실기기 실행을 수행했다고 주장하지 않는다.

검증 대상 코드 revision: `e07f695d0ac91fb1902cd811207f116fa0504af1`.

기존 Swift 설정 테스트 5개에 회귀 테스트 7개를 추가했다. 새 검증은 전체 완료 대기, 중복 콜백, 중단 후 늦은 콜백, 이전 timeout, 겹친 작업 거부, custom/locked speed 정책, AUTO quality 정책이다. Python 자산 정책 테스트 7개는 유지한다.

macOS CI에서 unsigned iPhone SDK build·권한 설명 검사·Swift XCTest 12개·Python 자산 정책 테스트 7개가 모두 통과했다.

## 6. 제약과 미완료

현재값은 장치 readout이며 최종 사진 EXIF가 아니다. WB는 게인을 Kelvin/Tint로 환산한 추정이다. 설정 완료 콜백은 자동 AE/AF/AWB의 최종 수렴을 보장하지 않는다. speed 우선순위의 계산 사진 화질 tradeoff·요청/장치/EXIF 일치 여부는 기기에서 확인해야 한다.

실제 iPhone 설치·촬영·EXIF·화면 배치·발열·FPS·인터럽션·timeout 복구는 미검증이다. JPEG 전용·portrait-only, 현재 activeFormat 내 최대 치수 요청, 마지막 원본만 공유하는 제약은 유지된다. 앱 재시작 시 마지막 사진 복원·전체 갤러리·터치 AF·HEIF·AE/AF/WB Lock·RAW/ProRAW·LUT 렌더링·장노출·AI·영상·Android는 아직 미완료다. 포함 LUT는 0개다.

## 7. 다음 단계

실제 iPhone에서 요청값→완료 콜백→장치 현재값→촬영 EXIF를 대조하고 수동/자동 촬영의 화질을 비교한다. 설정 변경 중 잠금/홈/전화·기기 오류·렌즈 전환을 반복 검증한다. Phase 1의 터치 AF/노출 point·HEIF·기록/복구를 이어서 보완한 뒤 LUT 파서·Metal 단계로 넘어간다. Phase 1 전체는 아직 완료 처리하지 않는다.

## 검증 기록

[CI run 39456300371](https://github.com/MetaParodica/PhotoP/actions/runs/39456300371) 성공. 코드 revision `e07f695d0ac91fb1902cd811207f116fa0504af1`에서 iPhone SDK 빌드·권한 설명 검사·Simulator Swift 테스트 12개(0 failures)·Python 7개(OK)·빈 LUT 허용 목록 검증이 모두 통과했다. 문서만 수정하는 후속 commit과 실기기 검증은 이 코드 실행 증거와 구분한다.
