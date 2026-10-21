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
