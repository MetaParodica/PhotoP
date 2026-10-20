# 단계별 구현·검증 기록

운영 방식: 각 구현 단위의 CI 결과를 확인한 다음 다음 단위 코드를 진행한다. 실패하면 해당 단위를 수정·재검증한다. 실기기 검증을 자동 테스트로 대체하거나 전체 Phase 완료로 처리하지 않는다.

## 1. HEIF/JPEG와 원본 컨테이너

- 구현: availablePhotoCodecTypes 기반 선택, 선택 포맷으로 capture 설정, ImageIO 컨테이너 확인, 실제 포맷 확장자와 원본 bytes 보관. 미지원 포맷을 요청하면 거부한다. 렌즈 전환으로 선택 포맷을 바꿔야 하면 UI에 알린다.
- 테스트: 지원 코덱 제한, JPEG bytes 보존, JPEG→HEIF 오표기 거부, 디스크 파일 bytes/확장자, 저장 실패 전파.
- 로컬: Python 자산 검증 7개 통과.
- 코드 revision: 39ea15d674b5d593e1d433da39a998864bcc7cd7.
- iOS CI: [39504500221](https://github.com/MetaParodica/PhotoP/actions/runs/39504500221) 성공. iPhone SDK build·Swift 17개·Python 7개 통과.
- 실기기: HEIF 실제 촬영·metadata·사진 앱 import는 미검증.

## 2. 터치 AF/AE와 AE·AF·WB Lock

- 구현: PreviewLayer 좌표 변환·영상 바깥 터치 거부, 렌즈 ID 일치 확인, 실제 locked/custom 상태 유지, 독립 Lock 요청과 AUTO 복귀. WB/AF는 현재 게인/렌즈 위치 상수로 잠근다. AE mode setter는 동기식이며 이를 센서 수렴 콜백으로 표시하지 않는다.
- 테스트: 좌표 범위·비유한값, 수동/잠금 유지, 미지원 항목 제외, Lock capability·수동 요청 충돌.
- 코드 revision: 7f03f29c3581c992fa621ca9f34b570f5b5b6734.
- iOS CI: [39504950163](https://github.com/MetaParodica/PhotoP/actions/runs/39504950163) 성공. iPhone SDK build·Swift 21개·Python 7개 통과.
- 실기기: 전면 mirror·회전·렌즈별 터치 위치와 AF/AE 수렴·잠금 유지 미검증.
