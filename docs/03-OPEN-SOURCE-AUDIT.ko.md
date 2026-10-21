# C. 오픈소스 1차 실사표

조사: 2026-10-21 KST. 사용자 후보 GitHub 25개는 모두 API에서 존재 확인; Siril GitLab 1개 추가 확인. 실제 테스트나 iOS 통합 완료를 의미하지 않는다. ExposureFusion은 저장소 식별자가 없어 별도 보류한다.

검증 단계: **R** = 저장소·README·라이선스/메타데이터 확인, **S** = R + 명시된 주요 소스 일부를 정적으로 읽음, **B** = 해당 revision 빌드, **D** = 실기기 검증. 이번 외부 후보에는 B/D 판정을 부여하지 않는다. 유지보수는 기본 브랜치 최신 커밋 날짜만 기록하며 최근 날짜가 품질·활동성을 보증하지 않는다. 세부 JSON에 전체 SHA·보관 여부·조회 시각을 남겼다.

## 비교표

| 프로젝트 / URL | 확인한 구현·README 기능 | 언어 | 플랫폼 | 라이선스 / 범위 | 최신 커밋 날짜 | 재사용 후보 | 난이도 | 우선 | 검증 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [IgnacioPro/iphone-raw](https://github.com/IgnacioPro/iphone-raw) | RAW/ProRAW·수동 제어·RAW 현상 구조 | Swift | iOS | 미확인 | 2026-02-08 | 노출·초점·WB 상태 모델 참고; 라이선스 확인 전 코드 도입 보류 | 중 | P1 | S |
| [NextLevel/NextLevel](https://github.com/NextLevel/NextLevel) | 사진·영상 캡처, WB·초점·노출 제어 | Swift | iOS | MIT | 2026-06-08 | 세션·녹화 관리 참고; MVP 전체 래퍼 채택 안 함 | 중 | P2 | R |
| [ooper-shlab/AVCamManual-Swift](https://github.com/ooper-shlab/AVCamManual-Swift) | AVCam 수동 노출·초점·WB 샘플 | Swift + Obj-C | iOS | Apple sample license | 2017-08-08 | 공식 API 호출 흐름 참고; 오래된 프로젝트 직접 통합 안 함 | 중 | P2 | R |
| [bjzhou/PhotonCamera](https://github.com/bjzhou/PhotonCamera) | README: 실시간 LUT, import, burst·stack 기능 | Kotlin | Android | Apache-2.0 | 2026-10-20 | LUT/버스트 정책 조사; AI LUT 생성의 서버 의존 별도 검토 | 상 | P2 | R |
| [LibreStatic/opencinecam](https://github.com/LibreStatic/opencinecam) | Camera2 전문 영상, LUT, thermal·capability evidence | Kotlin + native | Android | Apache-2.0 | 2026-10-12 | 기능 협상·지원 거부 근거·복구 구조 참고 | 상 | P1(Android) | R |
| [ryuheiyokokawa/FilmFrame](https://github.com/ryuheiyokokawa/FilmFrame) | 필름 LUT·cube 파서, 카메라 effect, RAW 관련 코드 | Kotlin / GLSL | Android | MIT | 2026-05-07 | 큐브 순서·trilinear 참고; 범용 파서는 직접 작성 | 중 | P1 | S |
| [fortunto2/starlapse](https://github.com/fortunto2/starlapse) | mean·lighten·sigmaClip, 별 정렬, GPU 누적 | Swift / Metal | iOS·CLI 수학 코어 | MIT | 2026-10-20 | StackCombiner·StarAligner·FrameAccumulator를 우선 분석 | 중 | P1 | S |
| [deepskystacker/DSS](https://github.com/deepskystacker/DSS) | 천체 프레임 등록·스태킹 | C / C++ | desktop | BSD-3-Clause (본문) | 2026-10-02 | 별 검출·정렬·평가 방식 참고; 모바일 앱 전체 포팅 비권장 | 상 | P2 | R |
| [opencv/opencv](https://github.com/opencv/opencv) | 영상 처리·기하·정렬·HDR 관련 모듈 | C++ | cross-platform | Apache-2.0 | 2026-10-20 | Phase 4에서 정렬만 필요 시 선택 빌드 | 중 | P1 | R |
| [MetalPetal/MetalPetal](https://github.com/MetalPetal/MetalPetal) | GPU graph·2D/3D LUT·강도·색변환 | Obj-C / Swift / Metal | Apple platforms | MIT | 2023-02-21 | MTIColorLookupFilter 후보; 직접 Metal 대비 측정 | 중 | P1 | S |
| [BradLarson/GPUImage3](https://github.com/BradLarson/GPUImage3) | GPU 필터 pipeline·lookup·blend | Swift / Metal | Apple platforms | BSD-3-Clause | 2024-02-19 | 셰이더·필터 연결 패턴 참고; MetalPetal과 중복 도입 안 함 | 중 | P2 | R |
| [Silence-GitHub/BBMetalImage](https://github.com/Silence-GitHub/BBMetalImage) | Metal 이미지·영상 필터 | Swift / Metal | iOS | MIT | 2021-10-25 | 단순 LUT·필터 대안 비교 | 중 | P2 | R |
| [AcademySoftwareFoundation/OpenColorIO](https://github.com/AcademySoftwareFoundation/OpenColorIO) | 색관리 config·CPU/GPU transform | C++ / Python | cross-platform tools | BSD-3-Clause | 2026-10-01 | 오프라인 LUT baking·참조 검증 우선; 모바일 전체 종속은 보류 | 상 | P1(tooling) | R |
| [TomPoczos/PoLUT](https://github.com/TomPoczos/PoLUT) | 비공식 필름 에뮬레이션 생성·scene-to-display LUT | Python / HTML / LUT | offline·LUT consumers | GPL-3.0 | 2026-08-04 | 광학/톤 설계 연구; 데이터·출력 자산 권한 확인 후 별도 도입 | 중 | P2 | R |
| [cedeber/hald-clut](https://github.com/cedeber/hald-clut) | HaldCLUT 모음과 생성·변환 작업 | Shell / PNG assets | LUT consumers | GPL-3.0 | 2019-03-21 | 분류·원저작자 추적; 색·크기 검증 자료 | 하(엔진)/상(권리) | P2 | R |
| [NatronGitHub/clut](https://github.com/NatronGitHub/clut) | B&W·negative·slide·print Hald 프리셋 | PNG assets | LUT consumers | CC-BY-SA-4.0 (README) | 2016-09-16 | 필름 종류·원출처 비교 | 하(변환)/중(권리) | P1(catalog) | R |
| [graplo/obs-film-luts](https://github.com/graplo/obs-film-luts) | RawTherapee 계열 Hald→OBS strip 자료 | PNG assets | OBS / LUT consumers | CC-BY-SA-4.0 (README) | 2026-09-20 | Hald와 strip 구분·카테고리 참고 | 하(변환)/중(권리) | P1(catalog) | R |
| [YahiaAngelo/Film-Simulator](https://github.com/YahiaAngelo/Film-Simulator) | 정지 이미지 LUT·기초 보정 편집 | Kotlin Multiplatform | iOS / Android | MIT | 2026-05-29 | 프리셋·내보내기 UX 참고; 카메라 엔진으로 오인 금지 | 중 | P2 | R |
| [DeMeerleerGilles/Lumix-film-simulation](https://github.com/DeMeerleerGilles/Lumix-film-simulation) | V-Log→타 브랜드 변환·에뮬레이션 자료 | LUT assets / docs | V-Log workflow | 미확인 | 2026-03-13 | 입출력 프로파일 분류와 검증용 연구 | 중 | P3 | R |
| [darktable-org/darktable](https://github.com/darktable-org/darktable) | RAW 현상·컬러·LUT·필름 관련 모듈 | C / C++ | desktop | GPL-3.0 | 2026-10-20 | 알고리즘 문헌·테스트 기준 연구; 현재 직접 종속 없음 | 상 | P2 | R |
| [RawTherapee/RawTherapee](https://github.com/RawTherapee/RawTherapee) | RAW 현상·색관리·필름 시뮬레이션 | C++ | desktop | GPL-3.0 | 2026-10-13 | RAW 품질·HaldCLUT 워크플로 참고 | 상 | P2 | R |
| [mergeos-bounties/PoseGuide](https://github.com/mergeos-bounties/PoseGuide) | scene tags→standing pose ranking·SVG; scoring scaffold | Python / web | CLI / browser demo | MIT | 2026-07-21 | 포즈 JSON·관절 overlay 스키마 참고 | 중 | P1(guide) | R |
| [ngocquy020196/Composition-Grid](https://github.com/ngocquy020196/Composition-Grid) | 6종 격자·회전·투명도·image/video overlay | TypeScript / React / HTML | browser extension | MIT | 2026-06-18 | SVG 기하 참고; SwiftUI 격자는 단순 수학 직접 구현 | 하 | P1 | R |
| [google-ai-edge/mediapipe](https://github.com/google-ai-edge/mediapipe) | pose·face 등 on-device perception toolkit | C++ / platform bindings | iOS / Android / web | Apache-2.0 | 2026-10-20 | Android pose 우선 후보; iOS Vision 대비 비용 측정 | 중 | P1(Android) | R |
| [open-mmlab/mmpose](https://github.com/open-mmlab/mmpose) | 포즈 추정 학습·평가·모델 zoo | Python | training/research | Apache-2.0 | 2025-08-04 | 모델 평가 연구; 전체 Python stack을 iOS에 넣지 않음 | 상 | P3 | R |
| [FA/Siril](https://gitlab.com/free-astro/siril) | 천체 정렬·스태킹·메모리/sequence 처리 | C / C++ | desktop | GPL-3.0-or-later 소스 헤더 | 2026-10-20 | 등록·타일 처리 연구 | 상 | P2 | R + registration/stacking 소스 일부 |
| ExposureFusion (식별 불명) | HDR 노출 융합이라는 알고리즘군과 개별 프로젝트를 구별해야 함 | 확인 필요 | 확인 필요 | 확인 필요 | 확인 필요 | OpenCV MergeMertens 등 명확한 구현으로 재실사 | 확인 필요 | P2 | 저장소 미확정 |

## 자산·외부 의존성 및 도입 판단

현재 PhotoP에는 위 후보의 소스·모델·LUT를 복사하거나 링크하지 않았다. 따라서 도입 승인을 완료한 의존성은 없다. 아래는 각 후보의 통합 전 점검 사항이다. 법률 의견이나 모든 파일의 권리 보증이 아니다.

- **IgnacioPro/iphone-raw**: 라이선스 미확인; 첫 소스 구간은 서비스 계약이며 실제 하드웨어 경로 전체 감사는 미완료.
- **NextLevel/NextLevel**: MIT; 외부 의존·샘플 자산 범위 확인 필요.
- **ooper-shlab/AVCamManual-Swift**: Apple sample license; 수정 파일·추가 자산 라이선스 재확인.
- **bjzhou/PhotonCamera**: Apache-2.0은 소스 기준; 모델·폰트·LUT 등 별도 고지 우선. README 품질 주장은 미검증.
- **LibreStatic/opencinecam**: Apache-2.0; README에서 APV/RAW video 비지원·실험 모드 제한을 명시.
- **ryuheiyokokawa/FilmFrame**: MIT 코드와 포함된 Fuji/기타 LUT 권리는 별도. 파서는 F-Log2 사전 변환과 domain 무시에 주의.
- **fortunto2/starlapse**: MIT; SkyMeter 등 내부 모듈, 셰이더·천체 데이터·샘플의 개별 출처 확인 필요.
- **deepskystacker/DSS**: LICENSE 본문 BSD-3-Clause 확인; GitHub 자동 판정 NOASSERTION과 구분. 하위 의존 별도.
- **opencv/opencv**: 현재 Apache-2.0; 선택 모듈·contrib·third-party·모델별 조건 별도 확인.
- **MetalPetal/MetalPetal**: MIT core, examples 별도 license, docs CC-BY-4.0. 최신성·툴체인 호환은 후속 빌드 필요.
- **BradLarson/GPUImage3**: BSD 계열(메타데이터 BSD-3-Clause); License.txt와 필터별 자산 권리 후속 확인.
- **Silence-GitHub/BBMetalImage**: MIT; 2021 이후 기본 브랜치 커밋 없음. 샘플 LUT 별도.
- **AcademySoftwareFoundation/OpenColorIO**: BSD-3-Clause core; OCIO configs와 포함 LUT의 별도 라이선스 확인.
- **TomPoczos/PoLUT**: GPL-3.0 표기. 생성 도구 라이선스가 모든 출력물의 재배포 권한을 자동 확정하지 않음.
- **cedeber/hald-clut**: 저장소 GPL-3.0; 원본/파생 LUT별 권리·고지 범위 별도 확인.
- **NatronGitHub/clut**: LICENSE 파일·GitHub 판정 없음; README의 CC-BY-SA-4.0 선언 확인. 원저작자별 검증 필요.
- **graplo/obs-film-luts**: README CC-BY-SA-4.0; 원본 컬렉션 attribution·파생물 고지 확인 후 번들 판단.
- **YahiaAngelo/Film-Simulator**: MIT 소스. FFmpeg-Kit·Skiko 등 배포물과 포함 LUT의 별도 조건 확인 필요.
- **DeMeerleerGilles/Lumix-film-simulation**: 최상위 라이선스 미확인; 공식 LUT 파생 관계·정확성·권리 확인 전 번들 제외.
- **darktable-org/darktable**: GPL-3.0 계열. 폐쇄형 배포에 소스 복사·링크를 도입하려면 배포 의무 별도 검토.
- **RawTherapee/RawTherapee**: GPL-3.0 계열 코드와 독립 Film Simulation 컬렉션 자산의 라이선스를 혼동하지 않음.
- **mergeos-bounties/PoseGuide**: MIT; 완성된 실시간 모바일 AI 구도 엔진이 아님. MediaPipe 모델 권리 별도.
- **ngocquy020196/Composition-Grid**: MIT; AI 장면 분석 기능으로 분류하지 않음.
- **google-ai-edge/mediapipe**: Apache-2.0 core; task 모델·weight·데이터셋 고지 별도.
- **open-mmlab/mmpose**: Apache-2.0 code; checkpoints·dataset·변환 모델 배포권 별도.

- **Siril**: GPL-3.0-or-later 헤더와 등록/stacking 구현을 확인. GTK·FFTW·OpenCV·입출력 의존과 `3rdparty_licenses`를 개별 검토해야 한다. 알고리즘을 참고하되 소스 포팅을 초기 계획에 넣지 않는다.

## 소스 정적 분석 근거

| 후보 | 읽은 경로 | 확인 내용 / 주의 |
| --- | --- | --- |
| Starlapse | Sources/StackKit/StackCombiner.swift | 픽셀별 count/mean/M2/peak, NaN 유효 마스크, mean·sigmaClip·lighten·comet. 루프 누적 메모리는 프레임 수에 비례하지 않음 |
| Starlapse | Sources/StackKit/StarAligner.swift | 최근접 대응과 회전+평행이동, 별점 수·잔차 판정. 대규모 움직임·일반 인물 정렬에 범용 적용 불가 |
| Starlapse | Sources/Starlapse/Services/FrameAccumulator.swift | Metal 누적·분산·decode 텍스처, 3개 display pool·축소 luminance. 12MP 이상 메모리 비용 직접 계산 필요 |
| iphone-raw | Sources/CameraKit/CaptureSessionService.swift 첫 구간 | Bayer/ProRAW capability·세션/노출/초점/WB 계약 확인. 실제 전체 어댑터·RAW 품질 검증은 별도 |
| FilmFrame | app/src/main/kotlin/com/filmframe/filmsim/CubeLutParser.kt | R-fastest·trilinear, sRGB→F-Log2 전제. DOMAIN_MIN/MAX를 건너뜀·단일 공백 split·특정 profile 사전 합성이라 범용 그대로 사용 불가 |
| MetalPetal | Frameworks/MetalPetal/Filters/MTIColorLookupFilter.m | 3D·square·strip LUT 분기, intensity, 2D→3D 변환. cube 텍스트 파서와 색공간 추론까지 제공한다는 뜻 아님 |
| Siril | src/registration/registration.c, src/stacking/sum.c | GPL 헤더, 등록·합성 구조 일부 확인. 최신 revision 전체 코드/빌드 검증 아님 |

README와 코드의 일치성 검토는 위 경로에 한정한다. 특히 PhotonCamera의 시스템 카메라 품질·AI LUT 생성, PoLUT의 물리적 충실도, Lumix 변환의 브랜드 재현 정확도는 README 주장으로 분류하고 독립 검증 전 제품 설명에 사용하지 않는다.

## 채택 순서와 성능 판단

1. iOS: 자체 최소 AVFoundation으로 캡처 계약을 먼저 실측한다. MetalPetal은 phase 2의 구현 후보이며 직접 Metal과 프레임 시간·메모리를 비교한다.
2. 합성: Starlapse의 테스트 가능한 수학 코어를 우선 참고한다. 1fps 천체 워크로드의 성능을 30/60fps 일반 카메라에 그대로 외삽하지 않는다.
3. Android: OpenCineCam의 capability/evidence, FilmFrame의 LUT 경로, PhotonCamera의 버스트 정책을 독립 검토한다. iOS 구현을 Kotlin으로 줄 단위 번역하지 않는다.
4. AI: iOS Vision → 필요 시 MediaPipe. PoseGuide는 포즈 카탈로그·규칙, Composition Grid는 격자 기하 참고다. MMPose는 학습·평가용이다.
5. OCIO·DSS·Siril·darktable·RawTherapee는 데스크톱 reference/tooling 연구를 먼저 한다. 모바일 전체 앱 의존성으로 편입하지 않는다.

모든 프로젝트의 실제 FPS·전력·메모리·사진 품질은 미측정이다. 난이도·우선순위는 구조를 바탕으로 한 엔지니어링 추정이다. 버전 고정, 하위 라이선스 inventory, 최소 빌드, identity/color fixtures, device benchmark가 끝나야 도입 확정으로 바꾼다.

## 공개 근거와 재현성

GitHub는 각 표의 저장소 URL 및 `/commits/<SHA>`로 조회할 수 있다. `research/repository-audit.json`은 API 기본 브랜치 SHA·언어·라이선스 판정·archive 상태·조회 시각을 보존한다. GitHub의 자동 라이선스 판정은 권리 검토를 대체하지 않으며 README/본문과 다르면 본문을 우선 읽고 차이를 기록했다.

Siril latest commit은 GitLab commits API에서 `bb91bcfe76af5ed6f59c449ea8f337f45f82798e`, 2026-10-20 확인. [등록 구현](https://gitlab.com/free-astro/siril/-/blob/master/src/registration/registration.c), [합성 구현](https://gitlab.com/free-astro/siril/-/blob/master/src/stacking/sum.c), [공식 저장소](https://gitlab.com/free-astro/siril).
