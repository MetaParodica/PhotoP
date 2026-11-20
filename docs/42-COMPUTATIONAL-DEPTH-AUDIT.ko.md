# 컴퓨테이셔널 심도 현행 감사 — 2026-11-20 KST

기준: fetch한 main `9acbb2581b677bfb868f00d55b35d7dba366888f`. 작업 브랜치 `codex/computational-depth-20261120`. 시작 때 미커밋 변경 없음, 열린 PR 없음. [main CI44667252120](https://github.com/MetaParodica/PhotoP/actions/runs/44667252120) success 확인. 기존 구현 검증 소스 f140234, 전체 CI44665022130·UI44665022029와 구분한다. 전체 사용자 지시서는 [원문](research/2026-11-20-depth-engine-directive.ko.md)을 보존했다.

AGENTS·CLAUDE·08·28·29·32·34·37~41 및 당일 일지와 실제 호출 경로를 대조했다. 아래의 검증은 자동 테스트 범위이며 실제 기기/경쟁 제품 화질 인수가 아니다.

| 기능 | 상태 | 실제 코드·함수 / 개선 지점 |
|---|---|---|
| signed CoC·9/17 깊이 레이어·초점면·전경 확산 | 구현 및 자동 검증 완료, 품질 개선 필요 | SoftwareDepthPolicy.radius/layerCoordinates → NaturalDepthEngine.renderField. 전경 coverage 합산 보존 필요. 숨은 배경 복원 없음 |
| PSF | 일부 구현 | DepthLensKernel.taps/reference → DepthLensFilter.kernelBlur. CI 소스 커널; CPU 참조에는 GPU Classic 주변부 변형이 빠져 있다. CPU/GPU 공간별 픽셀 비교 필요 |
| 선형 광량·고해상도 | 구현 및 자동 검증 완료, 기기 대기 | HighResolutionPhotoProcessor.renderJPEG·NaturalDepthEngine. extendedLinearSRGB, 최대64MP halo 타일. 큰 반경 pyramid 보존 |
| 선택 매트·경계색 | 구현되었으나 품질 개선 필요 | DepthMatteRefiner → DepthMatteCore.refine/unmix. RGB guided3×3·배경9×9. 새 neural matte 없음 |
| 라이브 시간 정렬 | 일부 구현 | LiveDepthAnalyzer → DepthTemporalState.alignHistory/update, DepthFusionCore.calibrate. flow·광도 검증과 affine 이미 존재. 등록 실패 후 무조건 history 사용 방지 필요 |
| 저장 영상 심도 | 구현 및 자동 검증 완료, 시간 품질 개선 필요 | VideoDepthProcessor.render: 프레임별 DepthAnythingV2+선택 매트. 기존 시간 상태를 아직 호출하지 않는다 |
| 추적 | 구현 및 자동 검증 완료, 일부 구현 | SubjectTrackingAnalyzer/Policy → CameraModel/Service 및 VideoDepthProcessor. Vision bbox+ByteTrack 점수 융합, generation/실패 fallback. mask memory/ReID 아님 |
| 사진 편집 | 일부 구현 | DepthPhotoEditor.preview/save → CaptureResultProcessor.loadSession/reprocess/render. v2/v3 recipe, hash 검증·원자적 UUID, 브러시 없음 |
| 영상 시간 설정 | 일부 구현 | VideoDepthIntent.parameters/append → VideoDepthProcessor, VideoDepthEditorView. timestamp hold만 존재. 부드러운 보간·편집 UI 없음 |
| 렌즈 스타일 | 일부 구현 | Natural/Portrait/Classic 보존. 독자6스타일 없음 |
| 자원·동시성 | 일부 구현, 기기 대기 | CIContext/pool 재사용·actor 단일 작업·취소·generation. 전역 inference NSLock, 우선순위 scheduler 없음 |
| 품질 인수 | 실기기 검증 대기 | 실제 평가 사진0장, 사용자 blind 평가0건, iPhone15Pro/iOS27.2 trace 없음. 기존 acceptance gate를 낮추지 않음 |

## 기준선과 최소 변경 모듈

이번 환경 Swift6.0.3/Linux에서 프로덕션 portable 테스트140개, 실패0(직접 실행). 네이티브 테스트는 기존 CI의 결과이며 로컬 Xcode 없음. 새 phase별 native/UI 결과는08과 일지에 별도 추가한다.

변경 대상은 DepthLensKernel/Filter와 PSF Metal, 기존 DepthMatteCore·DepthTemporalState, 영상 호출부, recipe/editor의 비파괴 교정, 렌즈 선택 UI다. 모델을 무조건 교체하거나 카메라/RAW/LUT/AF·AI 구도 중지 정책을 재작성하지 않는다. 기존 저장 레시피와64MP/8bitSDR 계약을 유지한다. 성능 수치는 실행 환경과 측정 범위를 함께 표시한다.
