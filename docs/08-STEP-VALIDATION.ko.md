# 단계별 구현·검증 기록

운영 방식: 각 구현 단위의 CI 결과를 확인한 다음 다음 단위 코드를 진행한다. 실패하면 해당 단위를 수정·재검증한다. 실기기 검증을 자동 테스트로 대체하거나 전체 Phase 완료로 처리하지 않는다.

## 1. HEIF/JPEG와 원본 컨테이너

- 구현: availablePhotoCodecTypes 기반 선택, 선택 포맷으로 capture 설정, ImageIO 컨테이너 확인, 실제 포맷 확장자와 원본 bytes 보관. 미지원 포맷을 요청하면 거부한다. 렌즈 전환으로 선택 포맷을 바꿔야 하면 UI에 알린다.
- 테스트: 지원 코덱 제한, JPEG bytes 보존, JPEG→HEIF 오표기 거부, 디스크 파일 bytes/확장자, 저장 실패 전파.
- 로컬: Python 자산 검증 7개 통과.
- 코드 revision: 39ea15d674b5d593e1d433da39a998864bcc7cd7.
- iOS CI: [39504500221](https://github.com/MetaParodica/PhotoP/actions/runs/39504500221) 성공. iPhone SDK build·Swift 17개·Python 7개 통과.
- 실기기: HEIF 실제 촬영·metadata·사진 앱 import는 미검증.
