# 단계별 구현·검증 기록

운영 방식: 각 구현 단위의 CI 결과를 확인한 다음 다음 단위 코드를 진행한다. 실패하면 해당 단위를 수정·재검증한다. 2026-10-21 사용자 지시에 따라 실기기 검증은 개발 진행을 막는 조건에서 제외한다. 미수행 실기기 항목은 별도 대기 상태로 추적하며, 자동 테스트 통과와 실기기 품질 검증을 구분한다. 실기기 확인이 필요한 Phase 전체를 검증 완료로 표시하지 않는다.

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

실제 iPhone에서 HEIF/JPEG·요청/장치/EXIF·전면 터치·잠금·편집 진입/복귀·Display P3→sRGB 차트·12.6MP peak memory·발열을 확인한다. 이 환경에는 연결된 iPhone이 없어 실기기 검증은 미수행이다. 해당 검증을 기다리며 개발을 멈추지 않고 자동 테스트가 통과한 후 후속 기능을 구현한다. Phase 1/2의 실기기 품질 검증은 미완료로 유지한다.

실시간 LUT는 CVPixelBuffer→Metal texture 경로·버퍼 수명·backpressure를 별도 구현하고, 현재 정지 사진용 waitUntilCompleted 경로를 매 프레임 호출하지 않는다. RAW/ProRAW·즐겨찾기·recipe 재열기·장노출·AI·영상·Android는 이후 작업이다. 원본/레시피/LUT 파일은 앱 삭제 시 함께 삭제되므로 필요한 자료는 앱 컨테이너에서 별도 보관해야 한다.

## 9. 실시간 처리를 위한 texture LUT 경로

- 구현: 사진 buffer와 live texture가 같은 Metal 보간 함수를 사용한다. LUT table·숫자 검증·Swift/Metal 파라미터 ABI를 공유한다. texture 경로는 명령만 인코딩하며 CPU readback이나 waitUntilCompleted를 호출하지 않는다.
- 테스트: 3×3×3 LUT·중간 RGB·alpha·강도 0/0.5/1을 CPU Double과 기존 사진 buffer 경로에 비교. BGRA 채널 순서·in-place·크기 불일치·암묵적 sRGB texture·잘못된 강도 거부.
- 코드 revision: cdae706d8972af6c9b0ed2458cfc56dc263dbbc0.
- [CI 39510047929](https://github.com/MetaParodica/PhotoP/actions/runs/39510047929) 성공. iPhone SDK build·Swift 52개·Python 7개 통과. 새 texture GPU 테스트 3개 모두 실제 실행했다.
- 실기기 FPS·메모리·발열은 대기 항목이며 후속 구현 진행을 막지 않는다.

## 10. YUV 색관리·화면·프레임 수명

- 구현: 8비트 NV12에서 명시된 BT.709 primaries·709/sRGB transfer·601/709 matrix만 허용한다. Core Video 메타데이터로 입력 ColorSync 프로파일을 생성하고 Core Image GPU에서 encoded sRGB texture로 변환한다. HDR/Log·불명 프로파일은 거부한다.
- 표시: 긴 변 1024px의 재사용 texture 2개, aspect-fit·검은 여백, Core Image→Metal 상하 방향 보정. 1프레임 in-flight와 세대별 ticket으로 중단/화면 변경 후 오래된 완료를 무시한다.
- 발견·수정: Metal 예약어/Swift CFString 비교 컴파일 오류, 상하 반전, display 709와 video matching 프로파일 차이, iOS 18 전용 profile 상수, 합성 프로파일의 optional name 가정을 수정했다. CPU 기준은 명시된 동일 입력 프로파일의 독립 ColorSync 색 변환이며 단순 BT.709 수식과 동일하다고 주장하지 않는다.
- 코드 revision: 3ae13dd69e0fc561a7db5ca92a02574cfbb1c1a3.
- [CI 39511844179](https://github.com/MetaParodica/PhotoP/actions/runs/39511844179) 성공. iPhone SDK build·Swift 56개·Python 7개 통과. YUV→sRGB→Metal 화면의 회색·방향·alpha·letterbox GPU 검증과 프레임 수명 검증 통과.

## 11. 카메라 실시간 LUT 연결

- 구현: 켤 때만 AVCaptureVideoDataOutput 추가, 광고한 NV12 full/video range 중 선택, portrait 90도·전면 mirror 연결. GPU 완성 프레임을 받기 전에는 기존 프리뷰와 대기 표시를 유지한다. 입력/인코딩 오류는 LUT를 해제하고 설명한다.
- 처리: Core Image GPU sRGB 변환→공통 Metal LUT→CAMetalLayer. 최대 1개 in-flight, discard late frames, GPU 완료까지 CVPixelBuffer 유지. live 경로에 CPU 픽셀 복사/readback·waitUntilCompleted 없음.
- 수명: 백그라운드·인터럽션·설정 timeout 시 중단, resume 시 새 세대. 촬영/설정 중 LUT 제거는 작업 완료까지 지연한다. 사진 캡처는 기존 PhotoOutput 원본 경로이며 LUT를 굽지 않는다. Stream 변경 후 현재 activeFormat에서 photo 치수를 다시 조회한다.
- UI: 사용자 .cube·sRGB 확인·강도·원본 비교·켜기/끄기. 현재 LUT를 켠 동안 렌즈 전환·터치 AF/AE·다른 LUT import는 제한하며 화면에 표시한다. 카메라 device color/HDR 설정을 강제로 바꾸지 않으며 미지원 입력 프로파일이면 해제한다.
- 코드 revision: 9263e8dda643dd24b98ee64f896dddae1e9a972a.
- [CI 39512508734](https://github.com/MetaParodica/PhotoP/actions/runs/39512508734) 성공. iPhone SDK build·Swift 58개·Python 7개 통과. NV12 video range와 stopped camera 거부 검증 추가. 새 Swift concurrency 경고 없음.
- 실기기 프레임 전달·실제 preview/사진 화각·색상 일치·전면 mirror·복귀·FPS·발열은 미검증으로 별도 대기한다. 이 항목을 기다리며 다음 기능 개발을 중단하지 않는다.

## 12. LUT 즐겨찾기 영속 저장·공통 선택

- 구현: Application Support/UserLUTFavorites 아래 SHA256 ID 폴더에 원본 .cube·sRGB profile.json 저장. 완성 전 임시 폴더를 쓰고 성공 시 이동한다. 동일 파일 중복 저장을 막고 저장된 bytes·프로파일·ID를 다시 검증한다.
- UI: 사진 편집과 live preview 모두 현재 LUT 저장·즐겨찾기 불러오기·삭제 지원. LUT 원본 파일과 사진 edit bundle은 삭제하지 않는다. 사용자 파일을 app bundle이나 상용 LUT 승인 목록에 자동 추가하지 않는다.
- 코드 revision: 3ccccb90182ce2de95fd68e9c7273a7ca99d3a7f.
- [CI 39513020492](https://github.com/MetaParodica/PhotoP/actions/runs/39513020492) 성공. iPhone SDK build·Swift 64개·Python 7개 통과. 재시작/중복, 변조 bytes, 프로파일 mismatch, 경로 이탈, 삭제 후 원본 보존, 저장 준비 실패 전파의 6개 테스트 추가.
- 라이선스: 독립 작성, 추가 의존성 없음. 저장하는 LUT는 사용자 import이며 번들 LUT 0개를 유지한다.

## 13. Live UI 알림 순서 회귀

- 발견: frame queue·GPU completion·UI lifecycle에서 MainActor로 보낸 waiting/ready 알림의 도착 순서가 바뀌면 오래된 알림이 새 화면 상태를 덮을 수 있다. CameraSnapshot과 live 이벤트의 도착 순서도 보장되지 않는다.
- 수정: lock 안에서 이벤트 순번을 발급하고 MainActor는 현재 renderer ID·현재 순번만 수용한다. 프레임 준비 여부와 session snapshot은 각각 보존하고 화면 표시 때 두 상태를 함께 확인한다. detach도 이전 이벤트를 무효화한다.
- 코드 revision: caa73055bb2bfc96273884b1a3bfe444bf8e275e.
- [CI 39514120122](https://github.com/MetaParodica/PhotoP/actions/runs/39514120122) 성공. iPhone SDK build·Swift 65개·Python 7개 통과. 이전 attach/stop 알림의 늦은 수용을 거부하는 회귀 테스트 추가.

## 현재 후속 범위

실기기 항목은 계속 대기 목록으로 유지한다. 개발은 자동 테스트 통과를 기준으로 이어간다. 기본 grain·레시피 재열기는 아래 14/15 단계에서 구현·자동 검증했다. RAW/고급 촬영·장노출·가이드·영상·Android는 후속 구현 대상이다. 현재 live LUT는 BT.709 SDR 입력, sRGB creative LUT, portrait, 렌즈/터치 제한을 가진 초기 구현이다. 실기기 화질/FPS를 측정한 완성 제품으로 표시하지 않는다.


## 14. 기본 그레인

- 기능·접근: 독립 작성한 정수 해시·bilinear value noise, 512-cell 정규화 좌표, 중간톤 envelope, LUT와 별도 강도·UInt32 seed. 사진 buffer와 live texture가 같은 함수를 사용하며 원본 비교는 양 효과를 끈다. recipe v2에 grain 설정 저장.
- 소스·라이선스: MetalPetal MIT, GPUImage3 BSD-3-Clause, BBMetalImage MIT, darktable GPL-3.0-or-later의 실제 관련 파일을 비교. 코드 복사·runtime 통합은 없다. [상세 검토](09-PHASE2-SOURCE-REVIEW.ko.md).
- 파일: GrainSettings.swift, MetalLUTResources.swift, MetalLUTRenderer.swift, MetalLUTTextureRenderer.swift, LUT.metal, LivePreviewImageProcessor.swift, LiveLUTPreview.swift, CameraModel.swift, LUTPhotoEditor.swift, LiveLUTControls.swift, LUTEditorView.swift, GrainTests.swift.
- 코드 revision: `996a906c310520c8355830d6c5985742f8768f8f`.
- [CI 39518986854](https://github.com/MetaParodica/PhotoP/actions/runs/39518986854) 성공: iPhone SDK build·Swift 67개·Python 7개. 신규 GPU 테스트도 skip 없이 실행. CPU reference 대비 및 still/texture 대비 채널당 오차 1/255 이하, seed 반복/변경·alpha·강도 검증 통과.
- 제약: 기본 단색 입자이며 실제 특정 필름 모델은 아니다. 해상도별 샘플링·JPEG 차이는 허용하며 display/FPS/발열 기기 측정은 대기.
- 다음: 자동 검증 성공 후 15단계 진행.

## 15. 저장된 편집 재열기

- 기능·접근: 앱 재시작 후 편집 기록 목록에서 선택, managed Documents 경로·64KiB recipe·32MiB cube 제한, version/profile·원본/LUT SHA256 확인, symlink·경로 이탈 거부. version 1은 grain 0, version 2는 grain 설정 복원. 새로 저장하면 새 bundle 생성, 기존 원본/편집본 보존. 카메라는 기록 화면에서도 정지한다.
- 파일: SavedEditStore.swift, SavedEditsView.swift, CameraView.swift, LUTEditorView.swift, LUTPhotoEditorTests.swift, 소스 검토 문서.
- 코드 revision: `6b80f1ee7ea4a9c831af0c1ce04e5f444e93dfae`.
- [CI 39519356635](https://github.com/MetaParodica/PhotoP/actions/runs/39519356635) 성공: iPhone SDK build·Swift 73개·Python 7개. 재열기→동일 preview JPEG→새 export 일치, 원본 불변, v1, 변조·누락·잘못된 프로파일/version/grain·경로·oversize·symlink·목록 검사 통과.
- 제약: 전체 갤러리·원본 삭제/이동 관리 UI는 미구현. 원본을 제거하면 기존 recipe를 재처리할 수 없으며 명시 오류를 낸다. 실제 앱 재실행 UI·카메라 복귀·메모리는 기기 대기.
- 판정: Phase 2 개발 기능과 자동 검증 완료. 실기기 품질 승인은 분리해 미완료로 유지한다.


## 16. 동적 RAW/DNG·지원 ProRAW

- 구현: DNG에 대해 제공된 RAW pixel format 조회·Bayer/ProRAW 구분, 지원 시 configure 단계 ProRAW enable, 요청 RAW 전용 capture. byte order·TIFF directory·DNGVersion·치수의 제한적 container 검사, isRawPhoto 확인, 원본 bytes 저장/공유. ProRAW AUTO·RAW/live 제한 명시, SDR 편집기 DNG 차단.
- 소스·license: Apple 공식 API·Adobe DNG 규격 참고. iphone-raw LICENSE 미확인, NextLevel MIT, AVCamManual custom Apple sample license. 구체적인 코드 검토는 [10 문서](10-PHASE3-DESIGN-AND-VALIDATION.ko.md). 소스 복사·의존성·자산 반입 없음.
- 파일: DNGContainer.swift, CapturedPhoto.swift, CameraTypes.swift, CameraService.swift, CameraModel.swift, CameraView.swift, SDRImage.swift, RawCaptureTests.swift.
- 발견: 합성 CFA/linear DNG를 Simulator ImageIO가 public.tiff·count 0으로 보고해 두 번 실패. RAW decoder 성공을 원본 보관 조건으로 쓰지 않고 container 식별을 분리하고 손상 directory 회귀 검증 추가.
- revision `bb48a56d1ac8e9b977065c871b19d07069f68880`, [CI 39522296909](https://github.com/MetaParodica/PhotoP/actions/runs/39522296909): SDK build·Swift 78·Python 7 성공. 합성 파일은 sensor sample/ProRAW 실측으로 표시하지 않는다.
- 제약: 실제 DNG 촬영·외부 현상·Photos metadata는 기기 대기. 자동 성공 후 17 진행.

## 17. GPU histogram·Zebra·focus peaking

- 구현: LUT 전 encoded SDR RGB/Y 64 bins, 최대 256px 표본 격자·4Hz, zero-alpha 제외. SDR max RGB threshold stripes, Sobel edge threshold peaking. UI·원본 비굽기, texture 재사용·한 프레임 in-flight, GPU 완료 전 1KiB counts 복사.
- 파일: PreviewMonitoring.swift, Monitoring.metal, LivePreviewImageProcessor.swift, LiveLUTPreview.swift, CameraModel.swift, MonitoringControls.swift, CameraView.swift, LiveLUTControls.swift, PreviewMonitoringTests.swift.
- revision `2978bb82e57b60434a0df1587928534bf8cb968f`, [CI 39522806940](https://github.com/MetaParodica/PhotoP/actions/runs/39522806940): SDK build·Swift 83·Python 7 성공. CPU bins·LUT 전 입력·zebra stripes/threshold·step edge·uniform·표본 상한·alpha·잘못된 설정 검증.
- 제약: 센서 RAW clipping/정확한 초점 측정 아님. LUT/monitor on에서 RAW·렌즈·터치 제한 유지. 실제 위치·시각적 유용성·FPS·발열은 기기 대기. 자동 성공 후 18 진행.

## 18. native 3장 노출 브래킷·원본 묶음 저장

- 구현: 현재 output max count·actual EV 범위에서 3장 AUTO·일반 HEIF/JPEG, 간격 ±0.5/1/2 EV. 범위 밖 clamp 대체 금지. OIS는 지원 시만 enable. request ID·sequence·bias·format·RAW flag·최종 예상 개수·중복·누락 확인, 처리 오류는 최종 callback까지 유지·capture timeout.
- 저장: Original bytes 3개와 요청 EV/hash manifest, 일반 I/O 실패 시 이번 원본만 삭제. Photos 단일 변경 작업으로 3개 asset 추가, 실패 시 앱 원본/공유 보존·전체 재시도. SDR 편집은 중앙 원본을 선택한다.
- 파일: ExposureBracket.swift, CaptureSeriesStore.swift, CameraService.swift, CameraModel.swift, CameraTypes.swift, CapturedPhoto.swift, PhotoStore.swift, CameraView.swift, ManualControls.swift, ExposureBracketTests.swift, RawCaptureTests.swift.
- 발견·수정: private 상태를 둔 value의 자동 initializer 접근 오류를 explicit init으로 수정. 기존 SinglePhotoDelivery는 시리즈 delivery로 대체하고 사용하지 않는 새 helper는 제거했다.
- revision `27794519bbdb39043f3972f6a5c96eab9da24bad`, [CI 39538033899](https://github.com/MetaParodica/PhotoP/actions/runs/39538033899): SDK build·Swift 90·Python 7 성공. 범위·미지원 조합·역순 callback·누락/중복/틀린 bias·RAW 대체·원본 bytes·manifest·부분 저장 정리·정지 세션 거부 검증.
- 제약: RAW bracket·HDR 합성 미구현. native callback·실제 노출/EXIF·Photos 3장·중단/timeout·강제 종료 복구는 기기 대기/미구현. 일반 파일 오류 정리가 crash-atomic 저장을 의미하지 않는다.
- 판정: Phase 3 개발 범위·자동 검증 완료, 명시한 실행 제한과 실기기 품질 승인은 별도 유지. 다음 제품 단계는 Phase 4.

## 19. 장노출 선형 누적·제한 정렬

- 구현: 선형광 streaming mean·whole RGB luminance Lighten, 픽셀별 유효 weight, ±8px integer translation과 texture/error/ambiguity 거부. bounded source1280·frames1200. Starlapse MIT 실제 source를 비교하고 독립 작성.
- 파일: LongExposureStack.swift, LongExposureStackTests.swift.
- revision `b03dc5b1110f49709ba84ea1e871f506f73de7dd`, [CI 39539398038](https://github.com/MetaParodica/PhotoP/actions/runs/39539398038): SDK·Swift96·Python7 성공. 평균188·RGB 선택·known shift/valid edge·ambiguous reject 검사. 자동 성공 후20 진행.
- 실기기/고해상도/일반 handheld 정렬·median/motion-aware는 미완료.

## 20. 샘플 장노출 촬영·archive·재처리

- 구현: 별도 NV12 output, SDR1280·2fps·1~300초, progress/cancel/thermal, lossless PNG128MiB disk budget·actual elapsed/early end, atomic result bundle·hash 검증·sequential reprocess·Photos/공유. 오리지널 센서 연속 노출로 표시하지 않는다.
- 파일: LongExposureCapture/LongExposureArchive, CameraService/Model/View, SDRImage, LongExposureView, LongExposureArchiveTests.
- revision `29ce647a03492e69b454fb9544fecb8812504463`, [CI 39539994340](https://github.com/MetaParodica/PhotoP/actions/runs/39539994340): SDK·Swift101·Python7 성공. PNG 재처리·hash 변조·cancel pending 정리·중복 완료·정지camera 검사. 자동 성공 후21 진행.
- 실제 샘플 간격/품질/FPS/RAM/300초·crash orphan recovery·재시작 browser는 미검증/미완료.

## 21. 독립 구도·포즈와 온디바이스 Vision

- 구현: 9종 목표 포즈·고급 격자, saliency/body/rectangle/horizon optional2Hz·단일 작업, confidence/stale/generation·aspect-fit mapping. Apple Vision API, PoseGuide README의 synthetic-scaffold 성격 확인 후 자체 도식 작성.
- 파일: CompositionGuide/CompositionAnalyzer, CompositionControls, LiveLUTPreview, CameraModel/View, CompositionGuideTests.
- 초기 `e6a13e788e0668fcd98f21fb18fcf35c7bef2b58`의 Swift106은 통과했으나 buffer Sendable 경고 확인. read-only retained holder로 소유권을 명시한 `995dac8e854f80ad55722bd38c583529ceeda730`, [CI 39540831878](https://github.com/MetaParodica/PhotoP/actions/runs/39540831878): SDK·Swift106·Python7 성공, 새 concurrency 경고 없음. 자동 성공 후22 진행.
- 실제 Vision 정확도/latency·가로 UI·건축 semantic/소실점·자동 원근 보정은 미검증/미구현.

## 22. 독립 필름 마감과 레시피 v3

- 구현: fade/vignette/bloom/red halation 각 강도, buffer/texture 공통 Metal 함수·zero bypass·alpha, live/editor controls·recipev3·v1/v2 호환.
- 파일: FilmFinish.swift/.metal, FilmFinishControls, MetalLUTRenderer/TextureRenderer, LivePreviewImageProcessor/LiveLUTPreview, CameraModel, LUTPhotoEditor/EditorView, SavedEditStore, FilmFinishTests/LUTPhotoEditorTests.
- 초기 `5ee41f9718495dc18a9701e26f1d75fc599eec55`은 SDK 성공·복잡한 test 배열 표현식 compiler timeout. fixture를 명시 loop로 수정한 `589961ae989e83861bb0e7e397663f02003bb832`, [CI 39541479961](https://github.com/MetaParodica/PhotoP/actions/runs/39541479961): SDK·Swift112·Python7 성공. expected endpoints/neighbors·same-input texture/still1/255·alpha·recipe 검사. 자동 성공 후23 진행.
- 실제 광학/유제 모델이 아닌 SDR 창작 효과; 해상도별 halo/미학 평가는 대기.

## 23. 자체 스타일12·전체 룩 preset·Hald

- 구현: 17³ cube 생성 자체12종, 검색/분류/합성chart, author/source/license/credit/hash, UUID full-look preset·restart restore·삭제·동일cube 다른설정, Hald PNG level2~8→cube, editor/live 연결·recipe provenance 보존.
- 파일: FilmStyleLibrary/STYLE-PERMISSION, FilterPresetLibrary, HaldLUT/ImportedLUT, FilmStylesView, LUTEditorView/LiveLUTControls, CameraModel, LUTPhotoEditor/SavedEditStore, FilmStyleLibraryTests.
- 참고: hald-clut README/tree·혼합 asset source와 GPL metadata, 공식 ARRI/Sony/Fuji/Panasonic 웹페이지. 외부 source/asset 복사 없음. 자체 profile data에 한정된 PhotoP-Style-Permission-1.
- revision `ca05d5cdc9b50108f7f5095d5ebdbaadbd4b1a25`, [CI 39542442343](https://github.com/MetaParodica/PhotoP/actions/runs/39542442343): unsigned iPhone SDK·Swift120·Python7 성공, skip0. hash재현/12unique·finite/gray ramp·trilinear chart·mono·검색·preset 재시작/변조/설정/version/경로·Hald red-fastest/swapped channels/invalid bounds/rotation/alpha 검사.
- Phase6 제한 개발 범위 자동 gate 통과. 외부 bundle0·자체12, 100+ 품질 승인·외부 재배포권·실제 사진 미학은 미완료. 다음 제품 단계는7. 상세 제한은11/12 문서에 기록한다.

## 24. preview GPU pass 생략·PSO 재사용·thermal budget

- MetalPetal의 실제 MTIContext cache 코드와 MIT LICENSE 검토 후 독립 구현. immutable compute PSO만 device/function별 공유, mutable frame 자원은 renderer 소유 유지.
- 중립 preview에서 LUT compute/graded texture 생략, off scratch 해제. nominal1024/60Hz·저전력720/30Hz·serious720/20Hz·critical480/10Hz 처리 admission과 Vision/histogram 감속. 센서/촬영 설정 변경 없음.
- `6d7d2eae672735dff4122bc5e4372010672066b1`, [CI39544188467](https://github.com/MetaParodica/PhotoP/actions/runs/39544188467): SDK·Swift124·Python7 성공. neutral/identity pixels·source texture 재사용/분리·PSO identity·budget/시간 guard 검증 후25 진행. 실측FPS/발열/배터리 향상량은 미검증.

## 25. 사진별 실제 지원 해상도 상한 선택

- activeFormat.supportedMaxPhotoDimensions와 output 상한의 양축 내 실제 값만 표시·요청. 같은 output max 반복 설정을 피하고 사진별 settings만 변경. RAW/bracket 정책 유지, unsupported 선택 시 명시 거부·구성 변경 UI 복귀. 파일 실제 픽셀 크기는 ImageIO metadata.
- Apple maxPhotoDimensions 공식 계약 확인. `6977d87b5a7275211ff76ebf1a11c70429d97d37`, [CI39544511878](https://github.com/MetaParodica/PhotoP/actions/runs/39544511878): SDK·Swift128·Python7 성공. 중복/양축/없는 크기/RAW/bracket/실제 파일 metadata 검증 후26 진행. 실제24/48MP delivery·latency·EXIF는 대기.

## 26. standalone1D cube 직접 보간

- OCIO IridasCube 소스·BSD3 원문 검토 후 자체 parser/CPU/Metal 확장.1D2~65536 RGB행 직접 보간,3D2~65 유지, mixed shaper+3D 거부. 낮은 크기의3D로 굽지 않음.
- `f274a26e2936951299d5ef89380982fc046d6569`, [CI39544857433](https://github.com/MetaParodica/PhotoP/actions/runs/39544857433): SDK·Swift132·Python7 성공. domain/채널/클램프/강도/잘못된 표·65536행·CPU/사진GPU/textureGPU 일치 검증 후27 진행.

## 27. 자체24+외부5·batch·출처/공유 보존

- slay5개 원본과 Git blob/SHA256 일치·모든33³ RGB행·README/LICENSE 전문·생성기를 확인. 원본 LUT/license만 포함, 입력 profile 미기재는 sRGB 가정으로 기록·사용자 확인. 자체12종 추가,29종 검색/분류/생성chart,32개 순차 가져오기와 부분 성공, favorite/preset/recipe/JPEG caption credit 보존. 배포 app에 실제 복사된 manifest/LUT/license도 검사.
- 첫 `c355558cb807c4da7f40a24c9c5188a5a7c397e8`, [CI39550127056](https://github.com/MetaParodica/PhotoP/actions/runs/39550127056): SDK 성공, Swift138 중1실패. Neon Rose에서17³ 보간 오차0.01604가 기존0.015 초과. 허용 오차를 유지하고 해당 표를33³로 높여 near-clipped blue 회귀 추가.
- 수정 `3abee4006a3298a49eb63dde8dae710a37c747c9`, [CI39550566621](https://github.com/MetaParodica/PhotoP/actions/runs/39550566621): unsigned SDK·Swift139·Python11 성공, skip0. source와 실제 app bundle 자산5개 hash·credit/license/profile 확인·chart/GPU·변조거부·attribution 재시작/recipe/JPEG·batch 부분 성공/선택 제한 검증.
- 자체24+외부5 총29이며100종 검수/브랜드 재현 완료가 아니다. 실제 사진 미학/색차·FPS/메모리/발열/기기 촬영은 미검증. 자세한 소스·파일·기술 계약은13 문서.

## 28. 촬영 화면 내 조절과 제공 아이콘

CameraChrome/CameraQuickControls로 뷰파인더 중심 UI와 같은 화면 패널·44pt 조작/접근성 레이블·재질 fallback을 구현했다. 장치 범위를 사용하며 셔터 위치를 유지한다. 제공 이미지를 아이콘9개 슬롯으로 변환하고 해시/PNG 형식을 검사한다. `ea12093`, 실행39575774557 재시도: SDK·Swift142·UI1·Python13 성공. 캡처는 종료된 Simulator로 실패했으며 xcresult 화면 회수·명시적 부팅으로 복구했다. 상세는14 문서.

## 29. 확보 외부 LUT25 전부·SDR 프로파일 변환

원본25개+해시/출처/권리 미확인 상태, V-Log→SDR 근사65³ 캐시, 프로파일 미확인 WDR 원본만 제공, preset/provenance 복원 및 실제 앱 리소스 검사. `7a15e0d`, [실행39579967039](https://github.com/MetaParodica/PhotoP/actions/runs/39579967039): SDK·Swift149·UI1·Python17·자산30개 양쪽 컬렉션 검사·자동 캡처 전체 성공. 자동 검증 후30으로 진행했다. 브랜드 공식 배포·센서 재현·권리 승인을 주장하지 않는다.

## 30. 비 LUT 공간 효과3·프리셋8·격자 상태 통일

같은 Metal 패스에 소프트 포커스/방사 색수차/가로 광원 확산을 추가하고 구형 레시피 복원·알파·중립·방향·채널·preset/편집 재시작을 검사했다. 기본 격자와 메뉴를 통일했고 UI 테스트가 메뉴로 삼분할→숨기기→삼분할을 수행한다. `6c569e0ec22f0521899bfd6cb0a9aca7d296024e`, [실행39581407493](https://github.com/MetaParodica/PhotoP/actions/runs/39581407493): SDK·Swift155(skip0)·UI1·Python17·자산30개·두 화면 캡처 전체 성공. buffer/texture의 전체 마감은1code 이내.59룩+기술3, 외부 원본30개. 실기기 품질/성능은 별도 대기.

## 31. Phase 7 영상: 선택 오디오·손떨림 보정

- 오디오: 영상 패널의 **오디오 녹음**을 켤 때만 마이크 권한을 요청하고 세션에 마이크 입력을 추가한다. 사진 모드 복귀·무음 전환 시 입력을 제거한다. 요청한 오디오 트랙(정확히 1개)이 없거나 무음 요청에 트랙이 있으면 Pending에 보관하고 확정하지 않는다. `NSMicrophoneUsageDescription`을 추가하고 CI에서 원본/앱 plist를 확인한다.
- 손떨림 보정: 활성 포맷과 연결이 보고하는 끔/표준/시네마틱/확장만 제공한다. 프리셋 변경 시 미지원 모드는 끔으로, 같은 프리셋에서 미지원 요청은 거부한다. 시네마틱 모드의 화각 감소·지연을 UI에 표시한다. 실제 적용 모드(`activeVideoStabilizationMode`)는 기록하지 않고 요청값만 기록한다.
- manifest v2: 구성에 `audio`·`stabilization`을 기록하고 `audioRequested`와 일치해야 한다. v1은 무음·보정 미상(`nil`)으로 계속 열린다. 알 수 없는 버전은 거부하며 파일을 삭제하지 않는다. Pending 복구는 오디오 트랙 0~1개를 허용하고 보정 요청은 미상으로 기록한다.
- 테스트: 구성 검증(오디오/보정 미지원 거부), 보정 모드 필터, v1 JSON 디코딩·v2 왕복, 오디오 트랙 수 일치, v1 manifest 재열기·불일치/미지원 버전 거부를 추가했다. 실제 마이크 동기·AAC 품질·보정 화각/지연은 실기기 검증 대기다.
- 남은 Phase 7: 녹화 중 LUT/분석 모니터는 MovieFileOutput과 VideoDataOutput 동시 사용 가능성을 기기별로 확인하거나 AVAssetWriter 경로로 바꿔야 하므로 실기기 없이 진행하지 않는다. Apple Log/HDR은 포맷 단위 선택과 별도 색 계약이 필요하다.

## 32. 사진 중심 촬영 화면 2차 개편

- 전폭 뷰파인더와 오버레이 헤더/레일, 인물 실루엣 가이드(프레이밍5·위치3·1~3명·눈높이/발끝선·Vision 이동 피드백), 최근 촬영 썸네일·확인 화면, 화각 기반 렌즈 배율·핀치/디지털 줌(최대5×, RAW 1× 제한), 지원 플래시·셀프타이머·1:1/16:9 프레이밍 가이드, 포맷 빠른 메뉴, 룩 분리 버튼, AUTO(읽기 전용 값)/PRO(M·L 표시) 레일을 구현했다. 상세는 [14 문서](14-CAMERA-UI.ko.md).
- 테스트: `PhotoShootingTests`(플래시 해석·순환, 타이머/비율 순환, 프레이밍 사각형, 줌 범위·화각 배율·라벨, RAW 줌 제한, 인물 배치·크롭·그룹·피드백), UI 테스트(AUTO/PRO 레일, 룩 버튼, 포맷 메뉴, 프레이밍·타이머, 최근 촬영 화면 경유 영상 보관함, 인물 가이드 선택)와 CI 캡처 `person` 화면을 추가했다.
- 실기기 미검증: 실제 배율 표기, 플래시, 타이머 촬영, 인물 피드백 정확도, 썸네일 지연.

## 33. 주석형 구도 프리셋·하단 카드 선택

- 참고 이미지 방식의 주석형 구도 프리셋 12종(3분할·점선 영역/원/연결선·손글씨 메모·화살표), 인물 영역 Vision 피드백, 구도/룩 공용 하단 카드 선택 UI를 구현했다. 상세는 [14 문서 3차](14-CAMERA-UI.ko.md).
- 테스트: `CompositionPresetTests`(ID 고유·프레임 내부 좌표, 인물 프리셋만 주제 영역, 관절 범위 피드백, 화살표 경로), UI 테스트(카드로 프리셋 선택·서랍 닫기 후 유지·룩 카드), CI 캡처 `guide`(2/3 프리셋)·`looks` 화면.
- 이전 2차 개편 코드는 [실행39602679861](https://github.com/MetaParodica/PhotoP/actions/runs/39602679861)에서 SDK·전체 테스트·캡처 성공.
- 결과: `7384cfa`, [실행39614392835](https://github.com/MetaParodica/PhotoP/actions/runs/39614392835) SDK·Swift186·UI5·Python17·캡처 성공. 중간 실패(실행39604154344·39606862163·39608523260: UI 테스트 카드 탭/중복 ID, 39610737746: 20분 제한 취소)는 원인 수정 후 재검증했다.

## 34. AI Composition Phase 1 코드 통합 (실영상 인수 대기)

- 기준 `bddf682`, 이번 변경은 로컬 작업 트리. 인물/얼굴 실제 Vision 요청, 위치 대응/평활화/일시 가림 복구, 탭 선택과 기존 AF/AE 공존, 삼분할 목표/방향/완료 상태/햅틱, 만료/세대/발열 예산을 추가했다. 자세한 파일·제약·실기기 검사표는 [18 문서](18-AI-COMPOSITION-PHASE1.ko.md).
- Swift 6.0.3/Linux에서 프로덕션 구도/추적 핵심을 Swift 5 언어 모드·strict concurrency complete로 컴파일하고 XCTest 17개 실행, 실패 0개. 최초 타입 추론 시간 초과를 switch로 단순화한 뒤 재검증했다. Python17·기존 자산 무결성 검사 통과, iOS Swift112개 구문 검사 통과.
- iOS 전용 분석 예산/AI UI 테스트를 추가하고 CI에 portable `swift test`를 추가했다. 이번 변경의 iOS SDK build·앱 테스트·스크린샷·새 CI 결과는 아직 없다. 핵심의 합성 검출 입력 테스트는 Vision의 실제 인물 검출 정확도 검증이 아니다.
- 실제 iPhone 카메라 검출·좌표 일치·추적 품질·햅틱·성능·촬영/저장 공존은 인수 대기다. 이번 첨부 지시서의 Phase 1 전체를 완료 처리하거나 후속 촬영 의도/코치/사진 리뷰를 함께 확대하지 않는다.

## 35. 전체 화면·촬영 결과 룩·PRO 심도·LONG 시간 입력

- 이전 AI 변경을 보존하고 전체 뷰파인더 뒤에 반투명 제어를 배치했다. LUT 실시간/예시 프리뷰를 끄고 원본 보존 후 별도 JPEG로 처리한다. 별도 DEPTH 모드 대신 PRO f값에서 실제 사진 깊이 기반 흐림을 제공한다. LONG 레일/패널 맨 앞에는 1~300초 총 합성 시간과 직접 입력을 제공한다. 상세·제약은 [19 문서](19-FULLSCREEN-CAPTURE-WORKFLOW.ko.md).
- Swift 6.0.3/Linux portable XCTest26(기존17+정책9)·Python17·기존 LUT 무결성 검사 통과. iOS Swift116 구문 검사·diff 검사 통과. SDK 빌드가 아니다.
- iOS 저장/룩 상태 테스트4 및 레이아웃/PRO f/시간 입력 UI 테스트는 추가/수정만 했으며 미실행이다. 실제 Depth 전달·화면·흐림 품질·촬영/저장·성능은 실기기 인수 대기다. 새 CI/커밋/푸시 기록은 없다.

## 36. AI Composition & Intelligent Camera Coach 전체 Phase 코드 통합

- 2026-10-23 KST, 후속 사용자의 전체 Phase 구현 요청에 따라 34단계 당시의 후속 코드 보류를 해제했다. 7개 촬영 의도, 자동 추천/수동 도식 29항목, 인물·관심 영역·직선·사각형·수평 기반 구도, 지원 렌즈/배율의 탭 줌 및 SDR 노출/기울기 코치, 촬영 리뷰·제한된 전후 비교·선택적 구도 횟수 학습을 통합했다. AUTO/PRO/RAW/LONG/VIDEO 실제 경로만 사용하며 원본/수동 설정을 보존한다. 상세는 [20 문서](20-INTELLIGENT-CAMERA-ALL-PHASES.ko.md).
- 라이브/리뷰 추론 공유 게이트, 사진/RAW·브래킷/장노출 중 추론·출력 해제와 복구, 영상 2.5Hz 상한, 새 촬영/녹화·백그라운드 시 리뷰 취소, 결과 만료·렌즈/배율 재확인·해시/스키마 검증과 유한 캐시를 추가했다. 새 외부 의존성·모델·이미지 자산 없음.
- Swift 6.0.3/Linux portable XCTest63(추적17+촬영 정책9+코치/구도28+리뷰9), Python17, 기존 LUT 무결성 검사 통과. iOS Swift127개 구문 검사 및 diff 검사 통과. SDK 타입 검사/앱 실행이 아니다.
- iOS 전용 통합 테스트5개와 라이브러리 UI 테스트1개 추가, CI 원본/번들 모션 권한 문구 검사 추가. Xcode/iOS SDK/Simulator/iPhone이 없는 환경이므로 이번 SDK 빌드·앱/UI 테스트·새 스크린샷·실제 검출·FPS/발열/저장 검증은 미수행이다. 과거 CI를 이번 코드의 성공으로 인용하지 않는다. 커밋·푸시는 하지 않았다.

