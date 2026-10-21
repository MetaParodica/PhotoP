# 현재 개발 단계 보고

기준: 2026-10-21 KST. MetaParodica/PhotoP, `codex/ios-camera-foundation`, Draft PR #1. Phase 1/2 기반에 Phase 3 개발 범위를 구현하고 자동 검증했다. 실제 iPhone 품질 승인은 미완료다.

## 1. 구현 기능

- 기존 native 카메라·수동 제어·HEIF/JPEG·원본 보존·SDR LUT·실시간 GPU·즐겨찾기·grain·비파괴 재편집 유지.
- 현재 lens/output에서 DNG에 대해 광고한 RAW pixel format 조회·Bayer/ProRAW 구분, 지원 시 ProRAW 활성화. RAW 전용 요청, raw flag·container 검사, 원본 DNG 저장·Photos·공유.
- GPU SDR RGB/휘도 histogram·Zebra·Sobel focus peaking, threshold UI·LUT 전 입력 분석·1KiB histogram만 최대 4Hz 복사. 기존 한 프레임 in-flight와 GPU buffer 수명 재사용.
- native AUTO exposure bracket 3장, ±0.5/1/2 EV·장치 범위/최대 개수/모드 검사, sequence·bias·format·RAW flag·총수·누락·중복 보호.
- Original 파일 3개·requested EV/hash manifest 저장, 일반 저장 오류 시 새 원본 정리, Photos 묶음 추가·전체 재시도·원본별 공유. 오류는 최종 capture callback까지 유지하며 제한 시간·중단 후 오래된 ID를 거부.

## 2. 참고 소스와 라이선스

[Phase 3 조사](10-PHASE3-DESIGN-AND-VALIDATION.ko.md)에 Apple AVFoundation·Adobe DNG 규격과 고정 revision을 기록했다. iphone-raw는 LICENSE 미확인으로 도입 보류, NextLevel은 MIT 원문·해당 RAW TODO 확인, AVCamManual-Swift는 Apple sample custom license·오래된 bracket/RAW API 확인. 외부 소스 복사·runtime 의존성·LUT/model 자산 반입은 없다.

## 3. 기술적 접근

기존 직렬 capture adapter에서 capability와 실행 가능 조건을 각각 검사한다. 원본은 재인코딩하지 않는다. RAW 현상기 지원과 DNG container 보관 검사를 분리한다. 모니터는 기존 Core Image→Metal SDR 경로를 확장하고 캡처 원본에 보조 표시를 굽지 않는다. Bracket은 AVFoundation의 단일 native 요청을 사용해 수동으로 카메라 EV를 여러 번 바꾸는 세션 경쟁을 피한다.

## 4. 주요 생성·수정 파일

- 신규: DNGContainer.swift, ExposureBracket.swift, PreviewMonitoring.swift, Monitoring.metal, MonitoringControls.swift, CaptureSeriesStore.swift.
- 수정: CapturedPhoto.swift, CameraTypes.swift, CameraService.swift, CameraModel.swift, CameraView.swift, ManualControls.swift, LiveLUTControls.swift, LiveLUTPreview.swift, LivePreviewImageProcessor.swift, SDRImage.swift, PhotoStore.swift.
- 테스트: RawCaptureTests.swift, PreviewMonitoringTests.swift, ExposureBracketTests.swift. 문서 04/05/08/10·README 갱신.

## 5. 실행·테스트 결과

| 단위 | 코드 revision | CI | 결과 |
|---|---|---|---|
| RAW/DNG | bb48a56d1ac8e9b977065c871b19d07069f68880 | [39522296909](https://github.com/MetaParodica/PhotoP/actions/runs/39522296909) | iPhone SDK build·Swift 78·Python 7 성공 |
| 모니터 | 2978bb82e57b60434a0df1587928534bf8cb968f | [39522806940](https://github.com/MetaParodica/PhotoP/actions/runs/39522806940) | iPhone SDK build·Swift 83·Python 7 성공 |
| Bracket | 27794519bbdb39043f3972f6a5c96eab9da24bad | [39538033899](https://github.com/MetaParodica/PhotoP/actions/runs/39538033899) | iPhone SDK build·Swift 90·Python 7 성공 |

각 자동 검증 성공 후 다음 구현 단위로 진행했다. 최초 합성 RAW의 ImageIO image count 0과 bracket value의 private initializer 컴파일 오류를 발견·수정했다. GPU 테스트와 새 저장 테스트는 실행했다. 현재 환경은 Linux이므로 iOS build/XCTest는 GitHub macOS runner에서 실행했다. 실기기 실행은 하지 않았다.

## 6. 제약·미완료

ProRAW는 AUTO 노출, RAW는 live 끔, bracket은 일반 HEIF/JPEG·AUTO·live 끔으로 제한한다. DNG container parser는 제한적 식별기이며 전체 DNG conformance나 실제 센서 RAW의 현상 성공을 증명하지 않는다. 모니터는 encoded SDR 분석이며 RAW clipping·정확한 초점을 측정하지 않는다. 기존 portrait·live 중 렌즈/터치 제한·편집 JPEG 12.6MP 제한을 유지한다.

RAW 현상·RAW bracket·HDR 합성·전체 갤러리·장노출·AI·영상·Android는 미구현이다. 실제 촬영/EXIF·RAW 외부 호환·화질·FPS·메모리·발열·중단/timeout 복구는 미검증이다. 다중 파일 쓰기 중 OS 강제 종료에 대한 crash-atomic 복구는 아직 없다. 일반 파일 I/O 오류 시 이번 파일 정리만 자동 검증했다. 번들 LUT는 0개다.

## 7. 다음 단계

Phase 4: streaming frame average·Lighten, 명시적인 작업 시간·취소·메모리 상한·합성 중간 결과, 이후 정렬/NR. 실제 기기 검증은 계속 별도 대기하며 자동 검증을 통과한 다음 개발을 진행한다.
