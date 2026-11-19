# 사진·영상 심도와 피사체 추적 조사

사용자 요청 기준일: 2026-11-19, Asia/Seoul. 기준 main `37eb109`. 공식 API·오픈소스 저장소/코드를 직접 조회한 조사이며 경쟁 화질·iPhone 실기기 성능을 측정한 결과가 아니다. 상세 조회 시각은 UTC로 [출처/복사 기록](research/2026-11-19-video-depth-tracking-sources.json)에 저장한다.

## 1. 목표와 현재 공백

PhotoP의 중심 기능을 사진·영상 모두에서 **선택한 피사체를 선명하게 유지하는 심도**로 확장한다. 기존 사진의 Natural/Portrait/Classic·전경 CoC·선택 매트·원본 보존을 재사용한다. 현재 영상은 무보정 MovieFileOutput 원본이며 심도 프리뷰/실제 출력이 연결되어 있지 않다. 기존 CompositionSubjectTracker는 중지된 구도 추천에 묶인 인물 연관 추정이며 범용 물체의 영상 추적/마스크 기억 시스템과 다르다.

AI 구도 추천·코치·자동 리뷰는 계속 중지한다. 새 피사체 추적은 사용자가 지정한 대상의 초점/심도를 유지하기 위한 별도 기능이다. SDR·원본 불변·품질 우선 계약을 유지한다.

## 2. 공식 Apple API에서 확인한 범위

| API | 확인 내용 | PhotoP 판단 |
|---|---|---|
| [VNTrackObjectRequest](https://developer.apple.com/documentation/vision/vntrackobjectrequest)·VNSequenceRequestHandler | 선택한 사각 영역을 프레임 간 추적하는 Vision 요청 | 첫 단말 구현의 범용 대상 추적. 검출/추적을 신원 인식으로 표시하지 않으며 낮은 신뢰도·큰 이동·오래된 프레임을 거부 |
| [VNGenerateForegroundInstanceMaskRequest](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest) | 전경 인스턴스 분리 | 이미 있는 선택 매트 정제를 활용. 모든 인물을 하나의 평면으로 고정하지 않음 |
| [isCinematicVideoCaptureSupported](https://developer.apple.com/documentation/avfoundation/avcapturedeviceinput/iscinematicvideocapturesupported) | iOS26+, 현재 세션/카메라/포맷 지원에 따라 변경. 전경·배경 심도와 사람/동물 등 추적 지원. 공간 영상 동시 캡처 불가 | 지원값을 실기기에서 확인해야 함. iOS27.2라는 이유만으로 지원/화질 완료를 표시하지 않음 |
| [isCinematicVideoCaptureEnabled](https://developer.apple.com/documentation/avfoundation/avcapturedeviceinput/iscinematicvideocaptureenabled) | 렌더 파이프라인 재구성. 활성화 중 일반 focusMode 변경 시 예외 | 기존 수동 초점·AF/AE·렌즈 전환을 그대로 섞어 켜면 안 됨. 별도 캡처 어댑터 필요 |
| [simulatedAperture](https://developer.apple.com/documentation/avfoundation/avcapturedeviceinput/simulatedaperture) | 포맷의 min/max 범위 검증 필요. **녹화 중 값을 변경하면 예외**, 녹화 전에 설정 | 모든 설정 실시간 조작과 충돌. 이번 첫 출력 경로는 소프트웨어 파생 영상으로 구성하고 네이티브 Cinematic은 별도 단계에서 검증 |
| [setCinematicVideoTrackingFocus](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setcinematicvideotrackingfocus(at:focusmode:)) | 장치 좌표의 정규화 위치, strong/weak 초점 정책 | 이미지·뷰·장치 좌표를 같은 것으로 취급하면 안 됨. 일반 Vision 추적과 다른 어댑터 |
| Cinematic RenderingSession/ObjectTracker/AssetInfo | Cinematic 자산의 깊이/스크립트·렌더링/추적 편집 | 일반 단일 SDR MOV와 다른 자산 구조다. 기존 VideoStore 검증을 무조건 완화하지 않고 후속 별도 형식으로 다룸 |
| AVAssetReader/Writer·PixelBufferAdaptor | 프레임 처리·원래 타임스탬프·오디오 보존이 가능한 저장 경로 | 영상에 실제 심도를 적용한 별도 파일 구현. 프리뷰만 바뀐 상태를 ‘심도 영상 저장’으로 표시하지 않음 |

추정 거리·깊이와 광학 초점 상태는 다르다. `lensPosition`을 m로 변환하지 않는다. 사진/영상에서 동일 대상과 좌표 계약을 유지하되 MF·사용자 잠금은 무단으로 해제하지 않는다.

## 3. 오픈소스 비교 — 라이선스 종류와 무관하게 조사

12개 저장소의 고정 커밋 README·LICENSE와 선택한 핵심 구현13파일을 읽었다. GitHub의 `NOASSERTION` 표기만으로 조건을 판단하지 않고 실제 파일/가중치 설명을 대조했다. 사용자의 이번 지시가 기존 문서의 라이선스별 조사/복사 제외 권고보다 우선한다. 실제 복사는 원문 조건/출처와 함께 기록하며, 기술 적합성이 없는 큰 의존성을 이름만으로 앱에 넣지 않는다.

| 프로젝트 | 조사한 기능/구현 | 실제 라이선스 확인 | 이번 채택 판단 |
|---|---|---|---|
| [SAM2](https://github.com/facebookresearch/sam2) | 프롬프트 마스크, 메모리 attention, propagate_in_video·가림 후 재추적 | Apache-2.0 | 장기 마스크 추적 구조 참고. PyTorch/CUDA 구현을 그대로 iOS에 넣을 수는 없음 |
| [SAM3](https://github.com/facebookresearch/sam3) | 개념/다중 물체 영상 분할, 공유 메모리 계열 | 저장소 SAM License(별도 조건) | 최신 연구 후보로 포함. 단말 메모리·변환·가중치 검증 후 판단 |
| [EfficientTAM](https://github.com/yformer/EfficientTAM) | 작은 ViT·효율적 메모리 attention·교정 클릭, 메모리/영상 offload | 코드·체크포인트 Apache-2.0 | **차기 우선 PoC**. 저자는 iPhone15에서 >10fps를 소개하지만 PhotoP에서 재현한 수치는 아님. 저장소의 주된 Python 구현/체크포인트와 iOS 앱 배포를 구분 |
| [CoTracker](https://github.com/facebookresearch/co-tracker) | 다수 점의 공동 추적·온라인 스트림·가림 | 주된 부분 CC-BY-NC4.0, 일부 별도 조건 | 표면 점/움직임 검증 후보. 점 추적은 매트/깊이 자체가 아니므로 단독 아웃포커스 엔진으로 채택하지 않음 |
| [ByteTrack](https://github.com/FoundationVision/ByteTrack) | 높은/낮은 검출 점수의2단계 연관, IoU와 confidence 결합 | MIT | 점수 결합 함수를 참조 복사하고 Swift 스칼라 연관 게이트로 이식. 전체 ByteTrack/검출기를 실행한다고 주장하지 않음 |
| [BoT-SORT](https://github.com/NirAharon/BoT-SORT) | 이동 예측·외관·전역 카메라 움직임 보정 | 저장소 MIT, 별도 검출기 조건은 분리 | 카메라 이동과 대상 이동 분리 설계 참고. 이번에는 ReID 모델을 추가하지 않음 |
| [XMem](https://github.com/hkchengrex/XMem) | 단기/중기/장기 마스크 메모리와 압축, 사용도 관리 | MIT | 무제한 프레임 캐시 대신 제한된 상태/기억을 유지하는 원칙 채택 |
| [MatAnyone](https://github.com/pq-yang/MatAnyone) | 앞 프레임 매트/특징 기억, 영상 경계 안정화 | NTU S-Lab1.0 비상업 조건 | 라이선스 때문에 조사에서 제외하지 않음. Python 모델/가중치의 단말 변환·성능 증거가 없으므로 후속 PoC |
| [Robust Video Matting](https://github.com/PeterL1n/RobustVideoMatting) | 프레임 간 recurrent state를 이용한 인물 매팅 | GPL-3.0 | 인물 경계 전용 비교 후보. 모든 물체/거리의 깊이를 해결하는 모델은 아님 |
| [Video Depth Anything](https://github.com/DepthAnything/Video-Depth-Anything) |32프레임 창·겹침/keyframe, scale/shift 보정·스트리밍 변형 | Small Apache-2.0; Base/Large CC-BY-NC4.0 | 시간 일관 깊이의 차기 우선 PoC. 현재 단일 이미지 Core ML 모델과 동일 모델로 표시하지 않음 |
| [DepthCrafter](https://github.com/Tencent/DepthCrafter) | diffusion 기반 시간 일관 영상 깊이, 겹침 추론 | README의 별도 연구/가중치 조건 확인 대상 | 저자의 GPU 메모리 요구가 단말 예산과 맞지 않음. 서버/비교용 후보, 앱에 기본 포함하지 않음 |
| [Ultralytics](https://github.com/ultralytics/ultralytics) | 검출/분할·추적 통합 | AGPL-3.0 및 별도 상용 조건 | 검출기/모델 대안으로 조사. 이번 기본 추적은 새 검출기 의존성 없이 Vision으로 구성 |

## 4. 코드에서 얻은 개선 방향

- ByteTrack: 낮은 confidence 관측을 바로 새 대상으로 바꾸지 않고 기존 대상과의 연관으로 판단한다. PhotoP에서는 약한 관측을 내부 유지에만 사용하고, 안전한 심도/AF에 사용할 상태는 더 강한 조건으로 구분한다.
- SAM2/EfficientTAM/XMem: 대상 선택·기억·교정 클릭과 세대/렌즈 변경 초기화를 분리한다. 모든 프레임/마스크를 누적 보관하는 방식은 피한다.
- MatAnyone/RVM: 영상은 사진 매트를 프레임마다 새로 만드는 것만으로 경계 안정성이 해결되지 않는다. 반복 상태·잘못된 이전 상태 폐기와 실제 머리카락/가림 장면 인수가 필요하다.
- Video Depth Anything: 단일 이미지 상대 깊이는 프레임마다 척도가 흔들릴 수 있다. 올바른 대응점/장면 컷 판정 없이 깊이 맵 평균을 내지 않는다. 우선 신선한 깊이를 사용하고 안전한 정합 조건에서만 시간 보정을 적용한다.
- BoT-SORT/CoTracker: 박스 중심 이동만으로 동일 피사체를 보장하지 않는다. 가림 후 다른 사람으로 자동 점프하는 것보다 ‘대상 놓침/다시 선택’을 명확히 표시한다.

## 5. 복사/이식 기록

- ByteTrack 커밋·원문 hash·원본 행 범위는 출처 JSON의 `copied_sources`에 고정했다.
- `third-party/ByteTrack/reference_fuse_score.py`는 원문 `matching.py`의 `fuse_score`만 보존한 연구 참조본이다. Python/scipy/lap/cython_bbox를 앱에 추가하거나 실행하지 않는다.
- `third-party/ByteTrack/LICENSE`에 MIT 원문을 보존한다. Swift 스칼라 포트는 IoU×confidence의 연관 비용을 사용하며 파일 주석/NOTICE에 출처를 명시한다.
- 나머지 저장소는 README/LICENSE와 핵심 소스를 작업 공간의 연구 폴더에 내려받아 검토했다. 앱에 해당 모델/런타임을 포함한 것은 아니다. 출처·코드/가중치 조건·실제 사용 범위를 혼동하지 않는다.

## 6. 결정

이번 구현은 **공통 피사체 추적 + 사진/영상 심도 프리뷰 + 오디오·원본·타임스탬프를 보존하는 실제 파생 영상**까지 연결한다. 산업 최고 수준이라는 평가는 실제 iPhone15Pro/iOS27.2·중/원거리 전경·빠른 움직임·머리카락·가림 장면 인수 전에는 하지 않는다. 개발 순서/완료 기준은 [40 계획](40-VIDEO-DEPTH-IMPLEMENTATION-PLAN.ko.md)을 따른다.
