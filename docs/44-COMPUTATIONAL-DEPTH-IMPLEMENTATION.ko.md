# 컴퓨테이셔널 심도 고도화 구현·평가 보고서

2026-11-20 KST. [원문 지시서](research/2026-11-20-depth-engine-directive.ko.md) → [감사42](42-COMPUTATIONAL-DEPTH-AUDIT.ko.md) → [사전 계획43](43-COMPUTATIONAL-DEPTH-PLAN.ko.md) 순서로 작업했다. 기존 엔진을 확장했으며 DSLR/Leica 동급·업계 최고 품질 인수를 완료했다는 보고가 아니다.

## 1. 실제 기준 main

작업 시작 fetch 후 main/origin/main은 `9acbb2581b677bfb868f00d55b35d7dba366888f`, 작업 트리 clean, 열린 PR0. 해당 [CI44667252120](https://github.com/MetaParodica/PhotoP/actions/runs/44667252120) success 확인. 별도 작업 브랜치 `codex/computational-depth-20261120`에서 변경/검증한다. 최종 게시 SHA는08과 일지에 추가한다.

## 2. 기존 기능과 재사용 범위

signed CoC·가상50mm thin-lens·9/17 depth layers·near coverage 합산·초점면 보호·Natural/Portrait/Classic·RGB guided 매트/경계색 unmix·상대 깊이 affine·Vision flow·bbox 추적·ByteTrack score 참조·64MP halo 타일·원본 hash·UUID atomic publication·사진 재초점/v2-v3 레시피·8bit SDR 파생 MOV/PTS/오디오/방향 보존은 기존 구현이다. 라이브 affine을 새 기능으로 집계하지 않았다. AI 구도/코치/자동 리뷰 중지, 위치/원본 공유 정책은 변경하지 않았다.

## 3. 새로 구현한 기능

- CPU와 Metal의 동일한 공간 가변 PSF. aperture polygon/주변부 cat-eye, 선형 premultiplied RGB/alpha와 정규화 tap. 기존 large-radius pyramid와 bounded ROI 지원 유지.
- far-only normalized convolution 배경 확장. 관측되지 않은 큰 구멍은 원본으로 유지하고 전경 전체 blur를 배경 seed로 쓰지 않는다.
- 확실한 matte seed 고정, 대비/잔차 검증을 통과한 unknown만 제한 color-line alpha 보정. 새로운 neural matte 모델 추가는 아니다.
- 저장 영상에도 기존 flow/affine temporal 상태 연결. 대응 실패·컷·가림/깊이 불일치·0.25초 gap·대상 변경·추적 실패 시 history 폐기. flow 없는 무조건 평균 없음. 영상 매트256px, 사진 고품질 경로와 분리.
- 독자6스타일 Vista28/Street35/Standard50/Studio75/Velvet85/Reach90. 기존3개 보존. 가상 CoC 특성이며 실제 카메라 focal length/광학 줌/브랜드 복제가 아니다.
- 사진 비파괴 교정 brush(전경/배경·크기·softness·초점 범위 보호·undo/redo), depth/선택 매트/결측·혼합 경계/초점면 보기. v4 recipe는 원본 base depth와 명령 분리, v2/v3 복원 및 교정 해제 지원.
- 영상 키프레임 추가/삭제·실제 시점의 원본 frame·hold/linear/smooth focus 및 reciprocal f값 보간. 대상/추적 정책/프로필 변경을 앞당기지 않는다. 단일 시점 심도 미리보기는 전체 추적 replay가 아님을 UI에 표시한다.
- 라이브 stale/generation/deadline 조기 폐기, 실제10종 영상 evidence gate, 재현 가능한 synthetic baseline/외부 encoder 변환 probe.

## 4. 변경 파일과 주요 함수

| 파일 | 역할 |
|---|---|
| Processing/DepthProcessingCore.swift | DepthLensProfile, taps/offset/reference; DepthMatteCore.refine; DepthTemporalState 등록 필수 옵션 |
| Processing/DepthPSF.metal·DepthPSFProcessor.swift·DepthLensFilter.swift | CIImageProcessorKernel→Metal, bounded device pipeline cache·pyramid |
| Processing/SoftwareDepthPolicy.swift | radius 가상 focal 선택, replacingDepthPreservingBounds |
| Processing/DepthBackgroundExtension.swift·NaturalDepthEngine.swift | far-only 배경 확장, 기존 signed layer 합성에 연결 |
| Processing/VideoDepthStabilizer.swift·VideoDepthProcessor.swift·LiveDepthAnalyzer.swift | 160px flow 분석/지도 좌표 확대, 등록·실패 통계, stale 조기 폐기 |
| Processing/DepthCorrections.swift | bounded stroke/history·보호 범위·base 비파괴 |
| Processing/CaptureResultProcessor.swift·DepthPhotoEditor.swift | v4 저장/로드/reprocess, base hash·교정 복원·768px 진단 |
| Processing/VideoDepthPolicy.swift·VideoDepthFramePreview.swift | 하위 호환 보간·actual frame/심도 미리보기 |
| UI/DepthLensPicker.swift·CameraQuickControls.swift·DepthResultLibraryView.swift·VideoDepthEditorView.swift | legacy segment+추가 style menu·편집 UX |
| PhotoPTests/AdvancedDepthTests.swift·DepthPSFMetalTests.swift·NaturalDepthTests.swift·PhotoPUITests/DepthEditorInteractionTests.swift | 수학/이미지/GPU/레시피/편집 UI 회귀 |
| scripts/check_video_depth_evidence.py·test_video_depth_evidence.py·measure_depth_synthetic_baseline.swift·probe_efficienttam_coreml.py | 실제 evidence integrity·baseline·모델 변환 재현 |

위 iOS 상대 경로의 루트는 `ios/PhotoP/`다. Package.swift와 CI depth scope에 같은 production core/새 테스트를 포함했다.

## 5. 공식 연구·외부 재사용

[고정 SHA/URL/hash 레지스트리](research/2026-11-20-optics-model-sources.json)에8개 저장소와 실제 읽은 renderer/model·조건 파일을 기록했다. 이번에 외부 구현 코드를 앱에 새로 복사한 범위는 **없음**. 기존 MIT ByteTrack 고지/포트는 유지한다. 논문의 layered visibility·normalized convolution·color-line 개념을 참고해 기존 자체 코드를 수정했으며 Dr.Bokeh CUDA나 neural renderer 전체를 이식한 것으로 표현하지 않는다.

| 공식 대상 | 실제 확인/판단 |
|---|---|
| [Dr.Bokeh](https://arxiv.org/abs/2308.08843), [CUDA](https://github.com/ShengCN/DrBokeh-Src/tree/24d96e4fb76a698494e86835c84a7c45ae2ebc10) | arXiv2023/공식 프로젝트 확인, 지시서의 CVPR2024 표기는 해당 자료에서 확인되지 않았다. soft occlusion·CoC 면적 보정·정규화 scatter, layered RGBDA 입력. LaMa/MiDaS/LDF 및 CUDA 의존. 루트 LICENSE 미확인, 앱 코드/가중치 미포함. 프로젝트 bib.txt는 다른 SSN 논문이므로 근거로 쓰지 않음 |
| [BokehMe](https://github.com/JuewenPeng/BokehMe/tree/8b3ed556dc146207c9bb39fccd078a113f8d1bd8) | CVPR2022, classical scatter+neural boundary rendering. Apache2 code. BLB10 synthetic scenes×focus/blur 변화는 실제100장 평가가 아니다. gamma/highlight boost를 실측 광학 수치로 해석하지 않음 |
| [BokehMe++ 저자 서지](https://juewenpeng.github.io/), [IEEE10756626](https://ieeexplore.ieee.org/document/10756626) | TPAMI2024 확장 논문 존재 확인. 별도 공식 공개 구현/가중치는 이번 조사에서 확인되지 않아 CVPR2022 code를 ++ 구현이라 부르지 않음 |
| [Bokehlicious](https://github.com/TimSeizinger/Bokehlicious/tree/0d2c45824de076ffc57ce222b60578302fb80923) | ICCV2025, U-shaped/Transformer neural rendering, aperture/position conditioning과 RealBokeh3MP 데이터. 코드/데이터 상용 조건 확인·연락 요청 문구, 루트 LICENSE 미확인. 앱 미포함·자체 평가 없음 |
| [EfficientTAM](https://github.com/yformer/EfficientTAM/tree/abcd061ebd3cc6e7527d152d75b890126aaa53f6) | Apache2 code, 공식 HF apache2 card. 512 tiny checkpoint 실제71,620,052 bytes/SHA 일치. image encoder-only CoreML probe 아래 참조. 저자의 iPhone15 >10fps 문구를 자체 재현 성능으로 쓰지 않음 |
| [Video Depth Anything](https://github.com/DepthAnything/Video-Depth-Anything/tree/4f5ae23172ba60fd7bc11ef671cca678842c7072) | Small Apache2, Base/Large CC-BY-NC4 구분. streaming32 history/41gap, tensor cache concatenation과 초기/후속 frame 분기. checkpoint 실제116,440,756 bytes·29,080,193 tensor값/351 tensors. single-frame 모델을 바꾸는 것만으로 streaming이 되지 않음; 아직 CoreML 변환/영상 품질 비교 미실행 |
| [MatAnyone](https://github.com/pq-yang/MatAnyone/tree/e5ddc534c1fff9bb9e54cf476095d29071b7cb4f) | S-Lab non-commercial code; HF model card 별도 명시 미확인, safetensors141,199,924 bytes는 API metadata 수치. human matte+memory/초기 mask 요구. 이번에 다운로드/변환/앱 채택하지 않음 |
| [RVM](https://github.com/PeterL1n/RobustVideoMatting/tree/53d74c6826735f01f4406b5ca9075eee27bec094) | GPL3 code, recurrent human matting·ONNX/TorchScript 경로. 임의 물체 segmentation 대체가 아님. 앱 미포함·기존 Vision 대비 실제 alpha 평가 없음 |

모델 가중치/데이터는 코드 LICENSE와 별개로 기록한다. 실제 앱 채택 판단은 조건뿐 아니라 변환·기기 성능·경계 품질 비교가 충족되어야 한다.

### EfficientTAM 실제 encoder 변환 probe

[결과 JSON](research/2026-11-20-efficienttam-encoder-probe.json)·[실패 이력](research/2026-11-20-efficienttam-probe-failures.json). full17,866,018 / encoder6,163,840 parameters. PyTorch2.5.1 CPU·torchvision0.20.1·CoreMLTools8.3·numpy1.26.4, fixed1×3×512×512. torch.compile의 MPS 검사와 bicubic unsupported, numpy scalar 변환 실패를 수정했다. fixed512의 positional embedding을 동일 bicubic 값으로 bake: CPU 출력 차이0.0. iOS18 MLProgram/F16 package **13,328,126 bytes** 생성 성공, 두 출력1×256×32×32. package 각 파일 hash 보존, 생성물은 `/tmp/photop-coreml-probe`에만 있다.

이는 **encoder만**의 graph 변환이며 decoder/memory/multi-object tracker 전환·CoreML runtime 수치 parity·실제 Neural Engine 실행·peak memory·FPS 검증이 아니다. 앱은 기존 DepthAnythingV2Small/Vision을 유지한다. 후속은 prompt/mask decoder·bounded memory tensors의 fixed-state wrapper, macOS CoreML runtime parity, iPhone15Pro의 whole-pipeline benchmark 및 실제 경계 비교다.

## 6. 알고리즘의 변경과 한계

기존 GPU에만 있던 주변부 transform을 CPU 참조에도 포함하고 같은 tap/좌표식을 Metal에서 실행한다. 가상 focal은 CoC 계산에만 적용한다. 정규화 gather는 상수장을 보존하지만 공간 가변 PSF 전체를 정확하게 적분한 ray tracer가 아니다. 점광원 에너지 근사 오차를 별도로 측정하며 밝기 boost·색 LUT로 개선을 가장하지 않았다. 선택 색수차/구면수차·실측 비네팅·정확한 렌즈 PSF 캘리브레이션은 아직 추가하지 않았다.

matte alpha는 입력의 확실한0/1 seed를 고정하고 주변 foreground/background의 색 대비와 관측 RGB의 직선 residual이 충분할 때만 최대0.35×confidence×0.85 보정한다. seed가 없거나 유리/반사처럼 관측이 모호하면 입력을 유지한다. 없는 털/머리카락을 신경망으로 새로 복원한 구현은 아니다. 기존 linear RGB 입력·F/B unmix를 재사용한다.

temporal은 현재→이전 flow의 광도 대응이 충분할 때만 이전 깊이를 워프하고 기존 robust affine으로 상대 scale/shift를 맞춘다. 깊이 불일치 pixel은 섞지 않는다. flow 유효성만으로 장기 객체 identity/가림 후 재식별을 보장하지 않는다. 원래 bbox 추적 정책과 낮은 confidence 원본 fallback은 유지한다.

## 7. 재현 가능한 품질 결과

| 실제 실행 | 결과 / 범위 |
|---|---|
| 같은 synthetic color-line fixture의 실제 main9acbb 함수 vs 변경 함수 | boundary MAE **0.0983785→0.014756747**, hard seed MAE **0.000760964→0.0**. prior 입력 오차0.1과 구버전 결과를 구분. [baseline](research/depth-synthetic/baseline.json)/[candidate](research/depth-synthetic/candidate.json), Swift harness 보존 |
| 등록된 정지 synthetic30-frame 교대 깊이 noise | raw estimate 대비 MAE 비율 **0.5635766**. 새 컷/가림/등록 만료는 averaging 없이 현재값. 실제 움직이는 인물 성능 수치 아님 |
| 공간 가변 CPU PSF impulse | nine profiles, off-axis 밝기8 impulse/radius4, 최악 상대 에너지 편차 **0.00614864**(약0.615%, 허용3%). DC/중심/지원 반경 검증 |
| native Metal–CPU linear RGB | nine profiles 전체 canvas 비교/alpha 검증, 허용 maxabs0.006. 실제 native 결과는08에 기록 |
| native far-only 배경 fixture | blue far/red foreground에서 제한 확장 pixel에 red 유입 금지, 관측 없는 먼 hole 원본 유지 |
| saved recipe/original/고해상도/영상 | 기존 및 신규 native fixture의 검증 로그를08에 기록. 실제 사용자 사진/영상 수는0 |

합성 fixture를 실제 사진100장·상용 앱/DSLR blind 결과로 계수하지 않는다. 어느 결과도 Leica보다 우수하다는 증거가 아니다.

## 8. 성능·메모리·발열

기존64MP halo/디스크 raster·large-radius pyramid·CIContext/pool 재사용을 유지했다. Metal pipeline cache는 device4개 한도, 프레임 history는 이전 small RGB1장과 depth1개, 교정은64 strokes/총1024 points/32 undo 한도다. 화면의 expanded editor controls는 스크롤 한도로 canvas를 보존한다. 모델/flow 뒤 stale live job은0.75초를 넘기면 추가 매트/게시를 폐기한다.

EfficientTAM의 Linux CPU random fixture encoder1회 약0.313초는 graph 확인용 단일 실행으로 p95/실시간 benchmark가 아니다. iPhone15Pro/iOS27.2 기기가 연결되지 않아 app peak memory·ANE 배치·GPU 시간·10분 thermal·실기기 FPS/p95는 **미측정**. inference priority scheduler는 아직 전역 serial gate이며 deadline/thermal 우선순위 정책 전체를 구현 완료로 표시하지 않는다.

10bitSDR은 현8bitBGRA reader/writer에 Main10 태그만 붙여 해결되지 않는다. x420/linear16 입력·CI texture/pool·VideoToolbox 지원·색/range·HEVC Main10 및 player roundtrip/device 검증이 필요하다. 현재8bitSDR을 유지하며 HDR/HLG/PQ/Log/gainmap/C2PA는 추가하지 않았다.

## 9. 테스트 수·실패·해결

초기140 portable → 현재150 portable 통과/0실패. Python31→33 통과. 새 native388개 중387통과/기존 Vision flow1skip인 중간 source를 확인했으며 최종 source의 전체 native/LUT/UI와 정확한 수는08에 갱신한다. CI 두 초기 실패는 apply 반환형 Optional 오해와 fixture CIColor Optional 누락으로 각각 수정했다. 테스트 assertion 삭제/강제 skip으로 처리하지 않았다. 실제 영상 gate는0건으로 exit2, 기존 사진 gate도 미인수 상태를 유지한다.

## 10. 정확한 CI 소스와 실행

중간 [CI44671800000](https://github.com/MetaParodica/PhotoP/actions/runs/44671800000)는 `d5b87746a6bfff2233f90d323a01ecdebabc6c3f`의 native388/Flow1skip을 확인했다. 최종 성공 SHA/URL·전체/LUT/UI 수는08·당일 일지에서 확정하며 진행 중 실행을 성공으로 쓰지 않는다.

## 11. 실기기 미검증

실제 모발/역광/안경/손가락/털/식물/유리/반사/다중 인물, 중·원거리 전경 보케, LiDAR/실제 camera orientation/녹화/4K60 HEVC/AAC 동기, tracking/occlusion, 냉·열 상태 FPS/memory, 수정 결과의 64MP 실제 촬영 색/타일 seam, iOS27.2/SDK27 인수와 경쟁 제품 blind 평가. Simulator는 카메라/ANE/실측 화질을 대체하지 않는다.

## 12. 남은 우선순위와 phase 상태

| Phase | 상태 / 다음 작업 |
|---|---|
| 0 | 함수·호출·CI 감사42/계획43 완료 |
| 1 | 기준140·같은 함수 synthetic before/after·실제 evidence 형식 확보. 실제100장 기준선 미확보 |
| 2 | shared spatial Metal PSF/선형·far-only 확장 구현/자동 비교. 실측 optical PSF·선택 수차/고난도 실제 occlusion 품질 미인수 |
| 3 | constrained alpha 보정/합성 오차 개선. high-precision neural matting 모델 채택은 실제 경계 데이터/변환·성능 비교 대기 |
| 4 | 기존 flow/affine 저장 영상 통합/실패 fallback. VideoDepthAnything full streaming CoreML·10종 실제 영상 비교 대기 |
| 5 | six styles·비파괴 brush/v4·진단/시간 보간 구현. EfficientTAM 전체 mask tracking은 encoder-only probe 단계, 기기 통과 전 앱 채택 안 함 |
| 6 | 자동 회귀와 evidence gate 실행. 실제100장/10영상·3명 blind·3기기10분 trace 없음으로 최종 품질 인수 미통과 |

먼저 iPhone15Pro 실제 소스와 consented100장/10영상으로 신규/구버전·LeicaLUX/Focos/ReLens/기본카메라/DSLR 비교를 고정하고, 경계 실패의 ROI에 따라 neural matte/streaming tracker를 채택한다. 이후 inference priority/thermal scheduling·10bitSDR 기술 검증, C1~3/빠른 설정·수평계 등 미구현 UX를 기존32백로그와 대조하여 진행한다.

## 13. 커밋·브랜치·푸시 상태

감사 c0036f8 → PSF44d8df2 → matte/temporal01e708f → editor96337c6 → Optional fixture d5b8774 → UI/evidence8ddd968 → stale/probe28f4a24. 작업 브랜치로 정상 push하여 CI를 반복했다. 마지막 검증·main 반영 SHA는08 및 당일 일지에 기록한다. 원본/기존 결과/레시피를 삭제하지 않았고 강제 push하지 않았다.
