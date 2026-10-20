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

## 3. .cube 파서와 CPU 참조 처리

- 구현: 크기 2~65, 32MiB·행 길이 제한, 헤더 중복·순서·데이터 개수·유한값·domain 검사. red-fastest trilinear, 강도 0/0.5/1, edge clamp. 프로파일 변환 없이 입력값을 직접 처리한다.
- 최초 CI에서 CRLF 앞 주석 때문에 TITLE을 놓치는 실패를 발견했다. Swift Character의 CRLF 처리를 고려해 LF로 정규화하고 LF/CRLF/CR 회귀 검증을 추가했다.
- 수정 revision: cc331cbb1427ca21856d2a367fe0c008b9f4853b.
- [CI 39505987201](https://github.com/MetaParodica/PhotoP/actions/runs/39505987201) 성공: iPhone SDK build·Swift 33개·Python 7개 통과.
- 1D/shaper·Hald·Log/HDR 입력 지원은 미완료다. LUT 수학 구현과 전체 색관리 지원을 구분한다.

## 4. Metal LUT 처리

- 구현: encoded sRGB premultiplied RGBA8, 8점 trilinear, 강도 혼합, SDR clamp·8bit 양자화. actor 소유 GPU 작업·LUT/pipeline/shared buffer 재사용. 12MP 제한.
- 코드 revision: 6153e0a4ca25c3b26095aa09d6d14c7fe7854a4f.
- [CI 39506408330](https://github.com/MetaParodica/PhotoP/actions/runs/39506408330) 성공. iPhone SDK build·Swift 37개·Python 7개 통과.
- Metal 테스트 4개는 Simulator GPU에서 실제 실행했고 skip 없이 통과했다. identity·channel swap·domain·clamp·강도·alpha·부분 threadgroup을 CPU 기준 최대 1/255 오차로 비교했다.
- 이는 정지 이미지 버퍼 연산 검증이다. 실제 iPhone FPS·메모리·발열·카메라 live preview와 색 일치는 미검증이다.

## 5. 비파괴 SDR LUT 사진 편집

- 구현: 마지막 촬영 원본에서 편집 열기, 카메라 세션 일시 정지, 사용자 .cube import(sRGB 입력/출력 확인), 강도·원본 비교, 1024px preview, 12MP 이하 원해상도 JPEG 저장/공유.
- 처리: SDR base와 EXIF 방향을 ImageIO로 디코딩, embedded ICC→sRGB 변환, 공통 Metal 렌더러, JPEG sRGB/orientation=1. HDR gain map·원본 EXIF는 편집본에서 제외하고 원본은 bytes 그대로 보존한다.
- 저장: 원본/LUT SHA256·강도·처리 프로파일 레시피와 원본 LUT를 JPEG 옆에 보관. 임시 폴더에 완성한 뒤 이동, 오류 시 부분 폴더 제거.
- 코드 revision: df9137d34a60279381e5174cf7dfe6f1230dec8f.
- [CI 39507027351](https://github.com/MetaParodica/PhotoP/actions/runs/39507027351) 성공. iPhone SDK build·Swift 44개·Python 7개 통과. GPU 포함 통합 export, 방향, 색 프로파일, 원본 hash, 재현 자산, 실패 정리 검증.
- 미완료: 실기기 화면/컬러 차트 검증, 실시간 카메라 LUT, 즐겨찾기·레시피 재열기, 12MP 초과 export, RAW/Log/HDR 처리.


## 6. 가져오기·숫자 안정화

- 구현: FileHandle의 부분 read를 고려한 64KiB 단위 제한 읽기, 32MiB+1에서 즉시 거부. Float domain 차이 overflow와 극단 LUT 출력값의 GPU 보간 overflow 거부. 터치 Coordinator를 MainActor로 명시.
- 코드 revision: 8a7a7d99a402e58bfb5d7b0a15c27665150b6834.
- [CI 39507378208](https://github.com/MetaParodica/PhotoP/actions/runs/39507378208) 성공. iPhone SDK build·Swift 46개·Python 7개 통과. Swift actor isolation 경고 제거 확인.
- AppIntents 미사용 metadata 경고와 portrait-only 앱의 orientation 경고는 남아 있으며, 실기기 표시 검증을 대신하지 않는다.

## 7. iPhone 사진 치수 경계

- 발견: 정확히 12,000,000픽셀 제한은 iPhone의 일반적인 4032×3024(12,192,768픽셀)를 거부한다.
- 수정: 메모리 예산 상한을 12,600,000픽셀로 명시하고 UI도 12.6MP로 표시한다. 원본은 축소하지 않는다. 상한 초과는 명확히 거부한다.
- 코드 revision: 641806587e1f559531dffb88a5d6c7b64420a4ea.
- [CI 39507679940](https://github.com/MetaParodica/PhotoP/actions/runs/39507679940) 성공. iPhone SDK build·Swift 47개·Python 7개 통과. 4032×3024 강도 0 경로와 4200×3001 거부 검증.
- 이전 4/5단계 당시 상한은 12MP였으며, 현재 상한은 12.6MP다. 실제 전체 해상도 GPU peak memory/발열 측정을 대신하는 테스트는 아니다.

## 8. RGB 중간값·비선형 LUT 보간 검증

- 검증 보강: 서로 다른 RGB 중간값과 alpha를 포함하는 257픽셀 fixture, cross-channel 곱 LUT, 내부 cell을 가진 비선형 3×3×3 LUT를 CPU Double 기준과 비교한다.
- 코드 revision: 192abb3d1dd359f838062ffb3f08efc31964e3f7.
- [CI 39507974347](https://github.com/MetaParodica/PhotoP/actions/runs/39507974347) 성공. iPhone SDK build·Swift 49개·Python 7개 통과. GPU 비교와 SDR export 통합 테스트도 skip 없이 실행했다.
- 허용 오차: 같은 RGBA8 입력에서 CPU/GPU 각 RGB 채널 최대 1/255. 실제 디스플레이 색차·다른 크기의 preview/export 시각 일치·HDR tone mapping 검증과는 별개다.

## 다음 제품 gate

실제 iPhone에서 HEIF/JPEG·요청/장치/EXIF·전면 터치·잠금·편집 진입/복귀·Display P3→sRGB 차트·12.6MP peak memory·발열을 확인한다. 이 환경에는 연결된 iPhone이 없어 실기기 검증은 미수행이다. Phase 1/2 전체는 미완료로 유지한다.

실시간 LUT는 CVPixelBuffer→Metal texture 경로·버퍼 수명·backpressure를 별도 구현하고, 현재 정지 사진용 waitUntilCompleted 경로를 매 프레임 호출하지 않는다. RAW/ProRAW·즐겨찾기·recipe 재열기·장노출·AI·영상·Android는 이후 작업이다. 원본/레시피/LUT 파일은 앱 삭제 시 함께 삭제되므로 필요한 자료는 앱 컨테이너에서 별도 보관해야 한다.
