# 추가 개발 기능 조사와 오픈소스 프로젝트 탐구

조사일: 2026-11-17. 기준: `main` `f6862b2`. 같은 날 `004d869`에서 3절의 코드 공백을 다시 확인했다(성능 계측에 `OSSignposter`가 추가된 것 외에는 동일). 처음 `claude/oss-feature-research-20261117`에 30번으로 올렸으나 main의 [30 최적화 구현 보고서](30-OPTIMIZATION-IMPLEMENTATION.ko.md)와 번호가 겹쳐 31번으로 옮겼다. 후속 과제 목록은 [32](32-NEXT-TASK-BACKLOG.ko.md). 범위: **조사와 우선순위 제안**. 앱 코드 변경·빌드·실기기 시험·성능 측정은 하지 않았다. 10월의 [1차 오픈소스 실사](03-OPEN-SOURCE-AUDIT.ko.md)(LUT·RAW 도구·스태킹 등 26개)와 [29 최적화 보고서](29-OPTIMIZATION-AND-ADVANCEMENT-AUDIT.ko.md)는 중복해서 다시 조사하지 않고 연결만 한다.

## 1. 결론

29 보고서의 P0(전체 회귀 복구·실기기 계측)을 먼저 끝낸다는 전제에서, 새 기능은 아래 순서를 권장한다.

| 순위 | 기능 | 한 줄 이유 | 오픈소스 의존 |
|---|---|---|---|
| 1 | 브래킷 **노출 융합**(Mertens) | 3장 브래킷 촬영·원본 보존이 이미 있고 합성 단계만 없다 | 없음(알고리즘 자체 구현, 참고 구현만) |
| 2 | **스코프 확장**(파형·RGB 퍼레이드·벡터스코프·False color) | 현재는 히스토그램·Zebra·피킹뿐. `Monitoring.metal`을 확장하면 된다 | 없음(OpenPocketCine은 구조 참고) |
| 3 | **Camera Control**(iPhone 16+) 연동, **원본 EXIF·게인맵을 보존하는 내보내기**·HEIC 출력 | 둘 다 Apple 네이티브 API로 가능 | 없음 |
| 4 | **포커스 스태킹** | 접사·제품 촬영. 수동 초점 제어가 이미 있다 | 알고리즘 참고(focus-stack, MIT) |
| 5 | **C2PA 콘텐츠 자격증명**(AI 심도·룩 적용 표기) | 차별점. 단 신뢰 인증서와 새 라이브러리 성숙도가 위험 | c2pa-ios(Apache-2.0 또는 MIT) |
| 6 | 심도 **매팅 품질** 비교(머리카락·안경) | 29 보고서 C01. 가중치 출처가 관건 | 후보 ViTMatte·MODNet(PoC만) |
| 7 | 인터벌·별궤적 | 기존 장노출 스태킹과 결합. 백그라운드 제약 | starlapse(10월 실사, MIT) |
| 8 | 멀티프레임 노이즈 저감·초해상 | 연구 과제. Apple 처리와 겹치는 구간이 크다 | 알고리즘 참고만 |

**도입하면 안 되는 것**(7절): AGPL-3.0인 `hdrplus-python`, 라이선스 파일이 비어 있는 `librectify`, 비상업 조건의 RMBG-2.0·MatAnyone·Depth Anything V2 Base/Large/Giant.

## 2. 증거 수준 표기

| 표기 | 의미 |
|---|---|
| [코드] | 이 저장소 `main`의 소스·설정을 직접 검색해 확인 |
| [저장소] | 해당 오픈소스 저장소를 2026-11-17에 얕게 clone해 LICENSE·README·트리·최신 커밋을 직접 읽음. 소스 정독이나 빌드는 아님 |
| [공식문서] | Apple 개발자 문서 원문을 직접 읽음 |
| [검색] | 웹 검색 요약만 근거. 1차 자료로 확인하지 못함 |

라이선스 판단은 법률 의견이 아니다. 배포 의무는 도입 전에 별도로 검토한다.

## 3. 현재 코드에서 확인한 공백 [코드]

| 영역 | 현재 | 근거 |
|---|---|---|
| 모니터 도구 | 히스토그램·Zebra·피킹만. `waveform.path`는 SF Symbol 이름일 뿐 | `Processing/PreviewMonitoring.swift`, `UI/CameraView.swift` |
| 노출 브래킷 | 3장 원본 촬영·manifest까지. 합성 없음 | `Camera/ExposureBracket.swift` |
| 포커스 브래킷·스태킹 | 없음 | 키워드 검색 결과 없음 |
| 인터벌·타임랩스 | 없음(샘플링 장노출은 있음) | 키워드 검색 결과 없음 |
| 파생물 출력 | JPEG만. 원본 EXIF·HDR 게인맵은 파생에서 생략 | `Processing/SDRImage.swift`, `HighResolutionPhotoProcessor.swift`, README |
| 출처 증명(C2PA) | 없음 | 키워드 검색 결과 없음 |
| 위치(GPS) 태깅 | 없음. 위치 권한 문구도 없음 | `Info.plist` |
| Camera Control·App Intents | 없음 | `AVCaptureControl`·`AppIntent` 검색 결과 없음 |
| 이미지 미적 점수 | 없음. 구도 AI는 saliency·body·rectangle·horizon | `Composition/` |
| 초해상·AI 업스케일 | 없음 | 키워드 검색 결과 없음 |
| RAW 현상 | 없음(DNG 촬영·보존만) | 키워드 검색 결과 없음 |
| 성능 계측 | `004d869`에 `OSSignposter` 구간 추가([30](30-OPTIMIZATION-IMPLEMENTATION.ko.md)). MetricKit 수집은 없음 | 키워드 검색 |
| 심도 모델 | Depth Anything V2 Small(Apple Core ML), 약 48MiB, Apache-2.0 | `assets/depth-model/legal` |
| 배포 대상 | iOS 17.0 | `ios/project.yml` |

## 4. 후보 기능

| ID | 기능 | 사용자 가치 | 네이티브 우선 가능성 | 난이도 | 핵심 위험 |
|---|---|---|---|---|---|
| F1 | 노출 융합 | 역광·실내 3장 브래킷을 한 장으로. HDR 파이프라인 없이 SDR 계약 유지 | 정렬: 장노출의 ±8px 평행이동 정렬(`LongExposureStack.swift`)만 있음. Vision 이미지 정합 요청은 코드에서 쓰지 않으며 이번에 확인하지 않음. 합성은 자체 Metal | 중 | 움직이는 피사체 고스트. 정렬 실패 시 거부해야 함 |
| F2 | 스코프 확장 | 노출·색 판단. 영상 모드에도 재사용 | 자체 Metal(기존 `Monitoring.metal` 확장) | 중 | 프리뷰는 SDR 분석이라는 계약 유지. 실기기 성능 미측정 |
| F3 | Camera Control | 하드웨어 버튼으로 줌·노출·룩 선택 | **네이티브**: `AVCaptureControl`(iOS 18.0+) | 하 | iPhone 16 이상만. iOS 17 분기 필요 |
| F4 | EXIF·게인맵 보존 내보내기, HEIC 출력 | 편집본 메타데이터 손실 해소 | **네이티브**: ImageIO, `kCGImageAuxiliaryDataTypeISOGainMap`(iOS 18.0+) | 중 | HDR은 현재 SDR 계약과 별도 과제. 보존만 먼저 |
| F5 | 포커스 스태킹 | 접사·제품 사진 | 자체 구현(정렬+피라미드 병합) | 상 | 렌즈 호흡으로 인한 배율 변화, 메모리 |
| F6 | C2PA | AI 처리 투명성, 출처 | 네이티브 대안 없음 | 중 | 인증서·신규 릴리스(v0.1.0)·바이너리 의존 |
| F7 | 매팅 품질 | 머리카락·안경 경계 | Vision 매트(현행)와 비교 | 상 | 가중치·학습 데이터 권리, 모델 크기·지연 |
| F8 | 미적 점수 | 브래킷·연속 촬영에서 추천 컷 | **네이티브**: `CalculateImageAestheticsScoresRequest`(iOS 18.0+) | 하 | "점수는 제안, 정답 아님" 규칙 유지 |
| F9 | 인터벌·별궤적 | 야경·풍경 | 자체 구현 | 중 | 포그라운드 필요. 백그라운드 촬영 보장 불가 |
| F10 | 자동 수평·원근 보정 | 건축 사진 | 수평선은 Vision(현재 사용). 소실점은 자체 구현 | 상 | 가용 오픈소스 구현이 마땅치 않음 |
| F11 | 초해상·디지털 줌 화질 | 줌 화질 | iOS 26.0+ `VTSuperResolutionScalerConfiguration` | 상 | AI 생성 디테일은 원본이 아님 → 파생물·표기 필수 |

## 5. 오픈소스 프로젝트 탐구

모든 날짜는 기본 브랜치 최신 커밋(2026-11-17 조회)이다. 최근 커밋이 품질을 보증하지는 않는다.

### 5.1 HDR 출력·포맷

| 프로젝트 | 라이선스 [저장소] | 최신 커밋 | 확인한 사실 | PhotoP 판정 |
|---|---|---|---|---|
| [google/libultrahdr](https://github.com/google/libultrahdr) | MIT 또는 Apache-2.0 이중. `NOTICE`에 "Gain Map technology under license by Adobe" 표기 | 2026-10-26 | README 검증 플랫폼은 Android·Linux·macOS·Windows. **iOS는 명시되지 않음**. `ISO 21496`·`ISO gain` 문자열이 `lib/src/gainmapmetadata.cpp`·`jpegr.cpp`와 문서에 있음(지원 범위는 코드를 읽어 확인하지 않음) | 안드로이드 호환 Ultra HDR JPEG이 필요할 때만 후보. iOS 빌드는 직접 해야 하고 미검증. Apple 네이티브 경로가 우선 |
| [libjxl/libjxl](https://github.com/libjxl/libjxl) | BSD 계열 + `PATENTS` 파일 | 2026-11-16 | Apple ImageIO의 JPEG XL 디코딩은 iOS 17+ [검색] | 필요성 낮음. 인코딩이 필요할 때만 검토 |
| [AOMediaCodec/libavif](https://github.com/AOMediaCodec/libavif) | BSD-2-Clause. 동봉 서드파티 고지(Apache-2.0 등)가 같은 파일에 있음 | 2026-11-16 | — | AVIF의 사진 앱 호환성이 불확실해 보류 |

**Apple 네이티브** [공식문서]: `kCGImageAuxiliaryDataTypeISOGainMap`은 iOS 18.0+, iPadOS 18.0+, macOS 15.0+. 문서는 선언만 보여 주고 사용법은 설명하지 않는다. Apple 방식과 Adobe/Google 방식의 메타데이터가 다르다는 호환성 이슈는 [검색] 근거이다.

### 5.2 출처 증명(C2PA)

| 프로젝트 | 라이선스 [저장소] | 최신 커밋 | 확인한 사실 | PhotoP 판정 |
|---|---|---|---|---|
| [contentauth/c2pa-ios](https://github.com/contentauth/c2pa-ios) | Apache-2.0 또는 MIT | 2026-11-12(`v0.1.0` 릴리스 갱신) | iOS 16.0+ / macOS 14.0+, Swift Package·XCFramework. **Secure Enclave 하드웨어 서명** 지원. 테스트용 서명 서버·CA 포함. 사전 빌드된 `C2PAC.xcframework`가 저장소에 있음 | 후보. 신규 릴리스라 성숙도 미확인. 실서비스 서명 인증서 발급 절차는 README에서 확인하지 못함 |
| [contentauth/c2pa-rs](https://github.com/contentauth/c2pa-rs) | Apache-2.0 또는 MIT | 2026-11-16 | c2pa-ios가 감싸는 Rust 코어. C FFI 포함. 커밋 메시지에 C2PA 2.5 반영 | 직접 의존하지 않음. c2pa-ios를 거쳐 사용 |

### 5.3 멀티프레임 합성

| 프로젝트 | 라이선스 [저장소] | 최신 커밋 | 확인한 사실 | PhotoP 판정 |
|---|---|---|---|---|
| [PetteriAimonen/focus-stack](https://github.com/PetteriAimonen/focus-stack) | MIT | 2026-01-11 | 포커스 스태킹 CLI·앱. Windows·Ubuntu·macOS 바이너리. 알고리즘은 OpenCV 기반, 웨이블릿 병합·깊이 지도 [검색] | F5 알고리즘 참조. 이식 시 OpenCV 의존이 따라오므로 자체 Metal 구현 권장 |
| [timothybrooks/hdr-plus](https://github.com/timothybrooks/hdr-plus) | MIT | 2026-01-12 | HDR+ 구현. 현재 유지관리자는 원저자가 아님(README). Halide 기반 [검색]. 빌드는 Nix·CMake | 정렬·병합 구조 참조 |
| [Jamy-L/Handheld-Multi-Frame-Super-Resolution](https://github.com/Jamy-L/Handheld-Multi-Frame-Super-Resolution) | MIT | 2026-09-30 | Wronski 등 논문의 **비공식** Numba(CUDA) 구현. README: Google보다 느리고 교육·과학용. DNG 버스트 입력 | 알고리즘 검증용 기준 구현. 모바일 이식은 별도 설계 |
| [amonod/hdrplus-python](https://github.com/amonod/hdrplus-python) | **AGPL-3.0** | 2022-06-27 | HDR+ Python 구현 | **코드 참조·이식 금지**. 논문과 IPOL 설명만 사용 |
| 노출 융합 구현 | — | — | 알고리즘은 Mertens·Kautz·Van Reeth 2007. IPOL 논문 구현이 정렬 단계를 추가해 고스트를 줄인다 [검색]. iOS용 Swift·Metal 구현은 찾지 못함 [검색] | 외부 의존 없이 자체 구현. 10월 실사의 MetalPetal·OpenCV는 참고 |

### 5.4 촬영 보조 스코프

| 프로젝트 | 라이선스 [저장소] | 최신 커밋 | 확인한 사실 | PhotoP 판정 |
|---|---|---|---|---|
| [erik-sutton95/OpenPocketCine](https://github.com/erik-sutton95/OpenPocketCine) | Apache-2.0 + `NOTICE` | 2026-11-16 | DJI Osmo용 iOS·Android 모니터 앱. `ScopeTraceMetalView.swift`(Metal), 파형·퍼레이드·히스토그램 오버레이, False color 4가지 방식(CineStop·Video·IRE·Limits, IRE는 6개 구간)을 가짐(`FalseColorAssist.swift` 안내문 기준). 자체 모듈(MonitorUI 등)과 DJI 피드에 결합 | 구조·구간 정의 참고용. 코드 이식은 비권장. 인용 시 `NOTICE` 유지 |

### 5.5 업스케일·심도·매팅 모델

| 프로젝트 | 라이선스 | 최신 커밋 | 확인한 사실 | PhotoP 판정 |
|---|---|---|---|---|
| [xinntao/Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) | BSD-3-Clause [저장소] | **2024-04-03(2년 이상 정체)** | Core ML 변환본이 Hugging Face에 여럿 있음. 4배 모델은 512 입력·약 59MB 등 [검색]. 변환본의 가중치 출처는 미확인 | F11 PoC 후보. 생성형 디테일이므로 원본과 분리·표기 |
| [hustvl/ViTMatte](https://github.com/hustvl/ViTMatte) | 코드 MIT [저장소] | 2025-08-13 | 일부 체크포인트는 Adobe Composition-1k 데이터셋 조건 때문에 비상업 제한 [검색] | 가중치 출처 확인 전 도입 보류. 오프라인 비교 PoC만 |
| [ZHKKKe/MODNet](https://github.com/ZHKKKe/MODNet) | README: 코드·모델·데모 **Apache-2.0** [저장소] | 2022-07-30(정체) | 검색 요약은 비상업이라고 했으나 현재 README는 Apache-2.0. **검색 요약이 틀렸고 저장소 원문이 맞다** | 경량 인물 매팅 비교 후보. 학습 데이터 권리는 미확인 |
| [DepthAnything/Depth-Anything-V2](https://github.com/DepthAnything/Depth-Anything-V2) | Small **Apache-2.0**, Base/Large/Giant **CC-BY-NC-4.0** [저장소 README] | 2026-03-24 | 현재 앱의 Small은 라이선스에 맞음 | **상위 모델로 교체 금지**(비상업) |
| [apple/ml-depth-pro](https://github.com/apple/ml-depth-pro) | 코드·가중치 모두 `LICENSE`(Apple 소프트웨어 라이선스) 조건 [저장소 README] | 2026-09-11 | LICENSE에서 비상업·연구 한정 문구는 검색되지 않음. 모델 크기·지연은 미확인 | 절대 깊이 연구 후보. 모바일 적합성 미확인 |
| [john-rocky/CoreML-Models](https://github.com/john-rocky/CoreML-Models) | 저장소 Apache-2.0. **변환된 모델은 각자 원 라이선스** | 2026-11-16 | `NOTICE`가 모델 라이선스를 별도로 명시 | 모델 탐색 목록일 뿐 의존 대상 아님 |
| RMBG-2.0(BRIA), MatAnyone | CC BY-NC 4.0 / S-Lab 1.0(비상업) [검색] | — | — | **제외** |

### 5.6 기하·렌즈 보정

| 프로젝트 | 라이선스 [저장소] | 최신 커밋 | 확인한 사실 | PhotoP 판정 |
|---|---|---|---|---|
| [lensfun/lensfun](https://github.com/lensfun/lensfun) | 라이브러리 **LGPL-3.0**, 앱 GPL-3.0, 렌즈 DB **CC BY-SA 3.0** | 2026-11-04 | 왜곡·색수차·비네팅 보정 DB | **비권장**. iPhone은 고정 렌즈이고, 링크 조건(LGPL)과 DB 재배포(SA) 의무가 크다. 기기 DNG 메타데이터 보정과의 관계는 미확인 |
| [RomanJuranek/librectify](https://github.com/RomanJuranek/librectify) | **`LICENSE` 파일이 0바이트**(권리 불명) | 2023-11-09 | 소실점·직교 수렴선으로 변환 계산, 워핑은 사용자 몫 [검색] | **도입 금지**. Lee 등 2014 논문 알고리즘만 참고 |

## 6. Apple 네이티브 API [공식문서]

| API | 가용 | 문서에 적힌 제약 | PhotoP 영향 |
|---|---|---|---|
| `AVCaptureControl`·`AVCaptureSlider` | iOS 18.0+ | Camera Control 버튼은 iPhone 16 기기용으로 설명. 제약은 이 외 기재 없음 | F3. iOS 17 기기는 분기. 구성한 컨트롤의 실제 동작은 실기기 필요 |
| `kCGImageAuxiliaryDataTypeISOGainMap` | iOS 18.0+ | 선언만 있음 | F4 |
| `CalculateImageAestheticsScoresRequest` | iOS 18.0+ | 시뮬레이터 제한은 문서에 없음. 포럼 언급[검색]은 시뮬레이터 미지원 | F8. UI 테스트는 시뮬레이터에서 실행 불가능할 수 있음 |
| `VTSuperResolutionScalerConfiguration` | iOS 26.0+ | ML 모델 다운로드가 필요할 수 있음. `isSupported` 확인 | F11. iOS 17 배포 대상과 불일치 |
| `VTLowLatencySuperResolutionScalerConfiguration` | iOS 26.0+ | 첫 세션 시작이 프레임 시간보다 오래 걸릴 수 있음. 입력 크기 `min/maximumDimensions`(값 미기재) | 영상 중심 API. 정지 사진 적합성은 미확인 |
| `VTTemporalNoiseFilterConfiguration` | iOS 26.0+ | 입력 크기 제한 있음(값 미기재) | 영상 중심 API |

## 7. 라이선스 장벽 요약

| 부류 | 해당 프로젝트 | 이유 |
|---|---|---|
| 네트워크 카피레프트 | hdrplus-python(AGPL-3.0) | 앱 배포·서비스와 충돌 가능성이 커서 코드 도입 금지 |
| 강한 카피레프트 | darktable·RawTherapee·Siril(GPL-3.0, 10월 실사), lensfun 앱(GPL-3.0) | 소스 포팅 금지. 알고리즘 문헌 참고만 |
| LGPL·ShareAlike | lensfun 라이브러리(LGPL-3.0)와 DB(CC BY-SA 3.0) | iOS 정적 링크 조건, DB 재배포 의무. 재구현하면 DB는 그대로 적용됨 |
| 비상업 | RMBG-2.0, MatAnyone, Depth Anything V2 Base/Large/Giant | 상업 배포 금지 |
| 권리 불명 | librectify(빈 LICENSE) | 라이선스 부여 확인 불가 |
| 모델 가중치 | ViTMatte 일부 체크포인트, 각종 Core ML 변환본 | 저장소 라이선스가 가중치에 적용되지 않을 수 있음 |
| 귀속 의무 | libultrahdr(Adobe Gain Map 고지), OpenPocketCine(`NOTICE`) | 도입 시 고지 유지 |

PhotoP의 기존 원칙("외부 소스는 복사하지 않고 검토 후 독립 구현")과 일치하는 도입 방식은 **알고리즘 참조 + 자체 구현**이다. 바이너리 의존(c2pa-ios)은 의존성 감사(출처·해시·빌드 재현성)를 따로 거친다.

## 8. 권장 PoC

| PoC | 목표 | 합격 기준 | 필요한 것 |
|---|---|---|---|
| P-1 노출 융합 | 기존 3장 브래킷을 Metal로 융합 | 정렬 잔차 한도 초과 시 거부, 원본 hash 불변, 파생 JPEG 저장, 고스트 장면 오분류 시험 | 실기기 브래킷 샘플 약 30세트 |
| P-2 스코프 | 파형·퍼레이드·벡터스코프·False color | 프리뷰 1024px 기준 p95 지연·메모리 측정(29 보고서 6절 계측 계획과 같은 방식), SDR 분석 계약 표기 | 실기기 |
| P-3 메타데이터 보존 | 편집본에 EXIF·ICC 보존, HEIC 출력, 원본 게인맵 보존 | 원본/파생 EXIF 대조 일치, 게인맵 유무 시험, iOS 17 분기 | iOS 18 실기기 |
| P-4 Camera Control | 줌·EV·룩 선택 컨트롤 | 컨트롤 변경이 장치 설정 완료 콜백과 충돌하지 않음 | iPhone 16 이상 |
| P-5 C2PA | 파생물 서명·검증 | 서명 파일이 외부 검증 도구에서 읽히고 변조 감지, 원본 불변 | 서명 인증서, 신규 라이브러리 의존 감사 |
| P-6 매팅 비교 | 현행 Vision 매트 대비 머리카락·안경 | 100장 이상 블라인드 평가(29 보고서 6절) 전에 가중치 출처부터 확정 | 가중치 출처 증빙 |

## 9. 한계

- 빌드·설치·실기기 시험·성능 측정은 하지 않았다. 난이도와 위험은 코드 구조와 문서에서 추정한 값이다.
- [저장소] 항목은 LICENSE·README·트리·커밋 날짜 수준이다. 구현을 정독하지 않았고 포팅 가능성이나 품질을 확인하지 않았다.
- [검색] 항목(Real-ESRGAN Core ML 변환본, ViTMatte·RMBG 가중치 조건, libjxl의 BSD 세부 조항, Apple의 JPEG XL 디코딩, HDR+ Halide 기반 여부, focus-stack 알고리즘 세부)은 1차 자료로 확인하지 못했다.
- Apple 문서는 가용 OS와 선언만 확인했고 동작·품질은 확인하지 않았다. `AVCaptureControl`의 iPhone 16 한정 여부는 문서의 설명 문구만 근거이다.
- 렌즈 보정이 iPhone에서 필요 없다는 판단은 추정이다. 기기 DNG에 보정 정보가 있는지는 확인하지 않았다.
- 첫 검색 요약에서 MODNet 라이선스가 비상업이라고 나왔으나 저장소 README 원문은 Apache-2.0이었다. 검색 요약만으로 라이선스를 판단하지 않는다는 점을 이번 조사가 보여 준다.

## 10. 근거 목록

- 저장소: [libultrahdr](https://github.com/google/libultrahdr), [c2pa-rs](https://github.com/contentauth/c2pa-rs), [c2pa-ios](https://github.com/contentauth/c2pa-ios), [focus-stack](https://github.com/PetteriAimonen/focus-stack), [hdr-plus](https://github.com/timothybrooks/hdr-plus), [hdrplus-python](https://github.com/amonod/hdrplus-python), [Handheld MFSR](https://github.com/Jamy-L/Handheld-Multi-Frame-Super-Resolution), [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN), [ViTMatte](https://github.com/hustvl/ViTMatte), [MODNet](https://github.com/ZHKKKe/MODNet), [libjxl](https://github.com/libjxl/libjxl), [libavif](https://github.com/AOMediaCodec/libavif), [lensfun](https://github.com/lensfun/lensfun), [OpenPocketCine](https://github.com/erik-sutton95/OpenPocketCine), [librectify](https://github.com/RomanJuranek/librectify), [CoreML-Models](https://github.com/john-rocky/CoreML-Models), [Depth-Anything-V2](https://github.com/DepthAnything/Depth-Anything-V2), [ml-depth-pro](https://github.com/apple/ml-depth-pro)
- Apple: [AVCaptureControl](https://developer.apple.com/documentation/avfoundation/avcapturecontrol), [AVCaptureSlider](https://developer.apple.com/documentation/avfoundation/avcaptureslider), [kCGImageAuxiliaryDataTypeISOGainMap](https://developer.apple.com/documentation/ImageIO/kCGImageAuxiliaryDataTypeISOGainMap), [CalculateImageAestheticsScoresRequest](https://developer.apple.com/documentation/vision/calculateimageaestheticsscoresrequest), [VTSuperResolutionScalerConfiguration](https://developer.apple.com/documentation/videotoolbox/vtsuperresolutionscalerconfiguration), [VTLowLatencySuperResolutionScalerConfiguration](https://developer.apple.com/documentation/videotoolbox/vtlowlatencysuperresolutionscalerconfiguration), [VTTemporalNoiseFilterConfiguration](https://developer.apple.com/documentation/videotoolbox/vttemporalnoisefilterconfiguration)
- 검색 요약 출처: [Ultra HDR 포맷 v1.1](https://developer.android.com/media/platform/hdr-image-format), [Content Authenticity c2pa-ios 문서](https://opensource.contentauthenticity.org/docs/c2pa-ios), [IPOL 노출 융합 구현](https://www.ipol.im/pub/art/2018/230/article.pdf), [IPOL Handheld 초해상 구현](https://www.ipol.im/pub/art/2023/460/), [Real-ESRGAN Core ML(Hugging Face)](https://huggingface.co/mlboydaisuke/Real-ESRGAN-x4-CoreML), [BRIA RMBG-2.0](https://huggingface.co/briaai/RMBG-2.0), [MatAnyone Core ML](https://huggingface.co/mlboydaisuke/MatAnyone-CoreML), [libjxl 개요](https://GitHub.com/libjxl/libjxl)
