# 현재 개발 단계 보고

기준: 2026-10-21 KST. 저장소 MetaParodica/PhotoP, 브랜치 `codex/ios-camera-foundation`, Draft PR #1. 각 구현 단위의 테스트 결과는 [단계별 검증 기록](08-STEP-VALIDATION.ko.md)에 유지한다.

## 구현 기능

- SwiftUI·AVFoundation preview, 물리 렌즈 선택, 전후면, 기본 격자.
- 장치 지원 목록에서 HEIF/JPEG 선택, ImageIO로 실제 컨테이너 확인, 원본 bytes 보관 후 Photos add-only export.
- 수동 ISO·셔터·EV·초점·WB, 독립 AE/AF/WB 잠금, 터치 AF/AE. 수동 또는 잠금 항목은 터치로 덮어쓰지 않는다.
- 완료 콜백 집계, UUID로 중단·중복·이전 콜백 격리, timeout 복구. 설정 변경 중 촬영·렌즈 전환 차단.
- 최대 4Hz 장치 readout과 snapshot 순서 보호. custom/locked exposure는 speed 우선순위를 사용한다.
- 엄격한 3D .cube 파서와 CPU trilinear 기준 구현: 2~65 차원, 32MiB 제한, domain·행 수·숫자·헤더 검사, 강도 혼합, 입력 edge clamp.

- Metal actor 렌더러와 CPU/GPU 픽셀 비교: LUT·pipeline·입출력 버퍼 재사용, premultiplied alpha, SDR clamp.
- 마지막 사진의 비파괴 SDR/sRGB LUT 편집: 입력/출력 프로파일 확인, .cube import, 강도·원본 비교, 1024px 미리보기, 12.6MP 이하 JPEG export/공유.
- 편집본 폴더에 recipe.json·look.cube 저장. 원본/LUT SHA256, 강도, 색 프로파일과 처리 순서 기록. 원본 bytes 유지, 실패 시 부분 폴더 정리.

- 실시간 LUT: 켤 때만 native NV12 output, Core Video 프로파일→Core Image sRGB GPU 변환→공통 LUT texture→CAMetalLayer. 한 프레임 in-flight, 버퍼 수명 유지, 중단/복귀·늦은 알림 순서 보호.
- LUT 즐겨찾기: SHA256 식별자, 원본 .cube·프로파일 파일 저장, 중복 제거·변조/경로 이탈 거부, 사진 편집/실시간 프리뷰의 공통 선택 화면.

## 참고 소스와 접근

Apple AVFoundation·Core Video·Core Image·ImageIO·CoreGraphics·Metal·CryptoKit 공식 API에 기반해 독립 작성했다. 외부 소스·라이브러리·LUT·모델 weights를 추가하지 않았다. 프로젝트별 조사 및 라이선스는 [오픈소스 실사](03-OPEN-SOURCE-AUDIT.ko.md)에 별도 기록한다.

카메라는 기존 직렬 큐, UI는 MainActor가 소유한다. Capture request와 실제 device readout, 지원 가능성과 현재 실행 가능성을 구분한다. LUT 수학에는 임의의 색공간 변환을 숨기지 않는다.

## 주요 파일

Camera: CameraService.swift, CameraModel.swift, CameraTypes.swift, CameraControlApplication.swift, CapturedPhoto.swift, PointMeteringPolicy.swift.
UI: CameraView.swift, CameraPreview.swift, ManualControls.swift, CameraReadoutView.swift.
저장: PhotoStore.swift. 처리: CubeLUT.swift, MetalLUTRenderer.swift, LUT.metal, SDRImage.swift, LUTPhotoEditor.swift. 편집 UI: LUTEditorView.swift. 실시간: LiveLUTPreview.swift, LivePreviewImageProcessor.swift, MetalLUTTextureRenderer.swift, MetalPreviewDisplay.swift, LivePreviewSurface.swift, LiveLUTControls.swift. 공통 LUT 저장/선택: ImportedLUT.swift, LUTLibrary.swift, LUTFavoritesView.swift. 관련 XCTest는 ios/PhotoPTests에 유지한다.

## 검증

현재 Linux 작업 환경에는 Xcode가 없다. iPhone SDK unsigned build와 Simulator XCTest는 GitHub macOS CI로 실행한다. 실기기 검증은 수행하지 않았다. 각 단계 commit·CI·테스트 수·실패와 수정 결과는 단계별 기록이 기준이다.

## 제약과 미완료

현재값은 장치 readout이며 최종 사진 EXIF가 아니다. WB는 게인에서 환산한 추정이다. 설정 콜백은 자동 AE/AF/AWB의 최종 수렴을 보장하지 않는다. speed 우선순위의 화질 tradeoff는 기기에서 평가해야 한다.

실제 iPhone 설치·HEIF 촬영·EXIF·전면 좌표·잠금 유지·인터럽션·FPS·발열은 미검증이다. portrait-only이며 현재 activeFormat 내 최대 치수를 요청한다. 앱 재시작 시 마지막 사진 복원·전체 갤러리·RAW/ProRAW·기본 grain·장노출·AI·영상·Android는 미완료다. 포함 LUT는 0개다. Phase 1과 Phase 2 전체를 완료로 표시하지 않는다.

## 다음 개발과 검증

2026-10-21 사용자 지시에 따라 자동 테스트가 통과하면 다음 구현 단계로 진행하며, 실기기 검증은 별도 대기 목록으로 유지한다. 실기기 미검증 때문에 개발을 중단하지 않는다.

후속 기능은 기본 grain·레시피 재열기·RAW/고급 촬영이다. live 경로는 독립 texture 인코딩을 사용하며 정지 사진용 waitUntilCompleted를 호출하지 않는다. 실기기에서는 요청값→완료 콜백→장치값→사진 EXIF, 필터 프리뷰/사진 색상·화각, 전면 mirror, 중단/복귀·FPS·메모리를 대조한다. 현재 실시간 LUT의 렌즈 전환·터치 AF/AE 제한과 BT.709 SDR 입력 제한을 UI에 표시한다.
