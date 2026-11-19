# 유명 카메라 앱·카메라 비교와 PhotoP 추가 개선 제안

조사일: **2026-11-19 / Asia/Seoul(KST)**. 기준 main/HEAD `2c1a7b3`, 현재 작업 브랜치 `codex/camera-depth-ux-20261118`의 **미커밋 UI·심도 변경도 별도로 대조**했다. 이번 작업은 공식 자료 조사·소스 대조·개발 제안이며 앱 구현이나 경쟁 제품 비교 촬영이 아니다.

## 1. 판단

**추가 개선할 여지가 크다. 다만 새로운 기능 수보다 촬영 성공률·조작 횟수·심도 경계·저장 품질을 먼저 개선하는 편이 효과적이다.**

현재 수동 노출, AF-S/AF-C, AF-ON, AF/AE 구분, 피킹, LUT, 스코프, 재초점, 브래킷 융합은 이미 있다. 이를 신규 기능처럼 다시 개발할 필요는 없다. 다음 순서를 권장한다.

1. 전날 박스형 뷰파인더·CoC 변경의 **Xcode/실기기 검증**과 중·원거리 전경 화질 확인.
2. 이미 확정한 **품질 우선 저장·공유 위치 제거·원본 위치 보존·AI 처리 표기**의 실제 구현.
3. **촬영 설정 프리셋(C1–C3), 편집 가능한 간편 메뉴, 독립 수평계**로 반복 조작 감소.
4. **광학 AF와 소프트웨어 초점 대상 일치, 초점 위치 확대, 심도/불확실 영역 표시**.
5. **고품질 심도 출력과 촬영/후처리 분리**, 이후 선택적 깊이 보정 브러시와 RAW 현상 등 확장.

AI 구도 추천·코치·자동 리뷰는 임시 중지 상태를 유지한다. HDR/게인맵·Log·C2PA는 도입 후보로 되돌리지 않는다. 카드별 룩 실시간 예시도 다시 켜는 제안이 아니다.

## 2. 조사 방법과 증거 수준

- 공식 제조사/개발사 페이지, 카메라 설명서, Apple의 앱 설명/API 문서를 직접 조회했다. **42회 조회 중39회 HTTP200**, 이 중 본문 근거31건·목차/탐색5건·중복/본문 불충분3건이다. HTTP 오류3건은 근거에서 제외했다.
- 제품 비교 대상은 **앱7개와 카메라5개 제품군**이다. 조회 시각(UTC)·최종 URL·상태·응답 SHA-256은 [공식 출처 기록](research/2026-11-19-camera-competitor-sources.json)에 저장했다. 보고서 날짜는 KST라 조회일의 UTC 날짜와 다를 수 있다.
- 웹 페이지의 HTML 주석·스크립트·스타일·템플릿은 본문에서 제외했다. 숨겨진 초안/주석과 목차 제목만으로 기능 출시를 판단하지 않았다.
- Focos·ReLens는 **Apple App Store의 개발사 제공 설명**을 읽었다. 앱 설명과 제조사 마케팅은 기능 소개 근거이며, 화질·속도·거리 정확도·경쟁 우위의 독립 검증은 아니다.
- 앱 구독/국가별 제공 기능·실기기별 조합을 직접 체험하지 않았다. Sony/Canon 등의 하드웨어 기능을 iPhone에서 동일하게 제공할 수 있다는 의미도 아니다.

## 3. 유명 카메라 앱 비교

| 앱·공식 출처 | 직접 확인한 특징 | PhotoP 현황 | 도입/개선 판단 |
|---|---|---|---|
| [Leica LUX](https://leica-camera.com/en-int/photography/leica-apps/leica-lux) | 렌즈별 디지털 렌더링, Color/Monochrome/Artist Looks, 그레인, 수동 노출·초점·WB, RAW/ProRAW | 실시간 LUT·마감·그레인·Natural/Portrait/Classic과 RAW 보존 있음 | 룩 수보다 **색 처리와 보케 프로필의 일관성**, 한 번 선택해 촬영까지 가는 흐름을 참고. 상용 렌즈와 같은 광학 특성을 재현했다고 표시하지 않음 |
| [Halide](https://halide.cam/), [Process Zero 개발 설명](https://www.lux.camera/introducing-process-zero-for-iphone/) | 노출/초점 제스처, 피킹·초점 확대, 처리 방식 선택, 센서 RAW 기반 최소 처리와 재현상. 저조도 노이즈 등 대가도 설명 | 피킹·중앙 MF 확대·DNG 보존은 있음. RAW 현상/최소 처리 출력은 없음 | 우선 **선택 초점 위치 확대와 조작 단순화**. RAW 최소 처리 경로는 후순위 PoC. ProRAW를 단순히 ‘AI 없는 RAW’로 부르지 않음 |
| [ProCamera](https://www.procamera-app.com/en/), [카메라 프리셋](https://procamera-app.com/en/custom-camera-presets/), [그레이 카드](https://procamera-app.com/en/graycardcalibration/), [브래킷](https://procamera-app.com/en/exposure-bracketing/) | 노출·WB·초점 설정 저장/복원, 그레이 카드 WB, EV 브래킷, RAW/ProRAW·TIFF/JPG/HEIF 출력 소개 | 룩 프리셋은 있음. 촬영 설정 전체 프리셋·그레이 카드 보정은 없음. 브래킷/SDR 융합은 있음 | **촬영 프리셋과 WB 보정**이 유효. 출력은 지원 형식/색/메타데이터 비교가 먼저이며 TIFF/HEIF가 항상 더 좋은 결과라는 뜻은 아님 |
| [ProShot](https://www.riseupgames.com/proshot) | 다이얼 중심 전환, Auto/Program/Manual과 사용자 Custom 모드2개, 수동 촬영·피킹·히스토그램·수평계·타임랩스 소개 | AUTO/PRO/LONG/VIDEO와 수동 제어 있음. 촬영 Custom 모드·독립 수평계·인터벌은 없음 | **C1–C3·독립 수평계·빠른 전환**을 참고. 웹 페이지의 Android/iOS 전용 기능을 서로 같은 지원으로 간주하지 않음 |
| [Blackmagic Camera](https://www.blackmagicdesign.com/products/blackmagiccamera) | HUD에서 직접 값 조절, 터치 초점/길게 눌러 잠금, Zebra·False Color·피킹, LUT 모니터링/기록 구분, 미디어 관리 | 터치·잠금·스코프·SDR 영상·프리뷰 LUT는 있음. 영상 LUT 굽기/작업별 미디어 정리는 미완료 | **모니터링과 저장 결과의 명확한 구분**, 미디어 상태/남은 저장공간 안내를 참고. HDR/Log/클라우드 협업은 이번 범위에 도입하지 않음 |
| [Focos: 개발사 제공 앱 설명](https://apps.apple.com/us/app/id1274938524) | 촬영 후 탭 재초점, 가상 조리개/보케 형태, 렌즈 특성, 깊이 시각화·깊이 맵 수정, 3D 조명 소개 | 저장 깊이 재초점·f값·가상 프로필 있음. 깊이 수정/깊이 표시/재조명은 없음 | **깊이 표시와 선택적 보정**이 유효. 이미 있는 재초점을 신규로 중복 개발하지 않음. ‘3D/light-field’ 마케팅을 실제 계측/가려진 장면 복원의 증거로 취급하지 않음 |
| [ReLens: 개발사 제공 앱 설명](https://apps.apple.com/us/app/id1638027598) | 가상 조리개·여러 보케 형태·광학 효과, 깊이 브러시·영역별 조정, 촬영/편집 품질 옵션 소개 | 가상 프로필·f값·선택 매트·원본 보존 있음. 깊이 브러시/품질 선택은 없음 | **고품질 오프라인 합성과 고급 보정 도구**를 참고. 앱 설명의 DSLR급·초해상 화질·줌 배율을 독립 확인된 성능으로 인용하지 않음 |

### 앱 비교에서 중요한 점

- LUX/Focos/ReLens의 공통 강점은 단순한 ‘블러 강도’보다 **렌즈 표현·초점 선택·촬영 후 복구**의 연결이다. PhotoP는 연결 기반이 있으므로 자동 경계/전경 품질을 먼저 검증해야 한다.
- Halide의 선택권을 참고할 수 있지만 **최소 처리=항상 최고 화질**은 아니다. 단일 RAW는 노이즈·다이내믹 레인지에서 시스템 계산사진보다 불리할 수 있다.
- ProCamera/ProShot의 저장·호출 구조는 조작 수를 줄인다. 현재 요청처럼 복잡한 심도 설정을 기본 화면에 더 늘리는 방향보다 적합하다.
- Blackmagic과 PhotoP의 공통 모니터 도구는 상당 부분 이미 있다. 실제 동작/입출력 구분을 다듬는 작업이 신규 스코프 추가보다 우선이다.

## 4. 유명 카메라 비교

| 제품·공식 설명서 | 확인한 기능 | PhotoP에 적용할 원칙 | 동일 구현을 주장할 수 없는 부분 |
|---|---|---|---|
| Sony α7 IV — [Fn](https://helpguide.sony.net/ilc/2110/v1/en/contents/TP1000616725.html), [AF-ON](https://helpguide.sony.net/ilc/2110/v1/en/contents/TP1000657960.html) | 자주 쓰는 기능을 Fn에 등록, 촬영 중 빠른 조절, 셔터와 AF 동작 분리 | 사용자 지정 간편 메뉴, 엄지로 접근할 AF-ON·잠금 해제, 사진/영상별 메뉴 유지 | iPhone에 DSLR 반셔터/모든 전용 다이얼/동일 AF 모듈이 있다는 의미 아님 |
| Canon EOS R5 Mark II — [Quick Control](https://cam.start.canon/en/C017/manual/html/UG-01_Preparations_0140.html), [C1–C3](https://cam.start.canon/en/C017/manual/html/UG-07_Set-up_0300.html), [MF 가이드](https://cam.start.canon/en/C017/manual/html/UG-04_AF-Drive_0070.html), [포커스 브래킷](https://cam.start.canon/en/C017/manual/html/UG-03_Shooting-1_0270.html) | 촬영 설정 등록·호출, MF 확대/피킹/방향 가이드, 포커스 브래킷과 선택적 기기 내 합성·소스 보존 | 촬영 프리셋, 초점 대상 확대·상태 피드백, 제품/접사용 스태킹 | Dual Pixel 기반의 정확한 앞/뒤 초점 방향을 iPhone API에서 그대로 얻는다고 가정하면 안 됨 |
| Nikon Z8 — [i 메뉴](https://onlinemanual.nikonimglib.com/z8/en/csmf_customize_i_menu_260.html), [Lock-On](https://onlinemanual.nikonimglib.com/z8/en/csma_focus_tracking_with_lock-on_206.html), [Focus Shift](https://onlinemanual.nikonimglib.com/z8/en/psm_focus_shift_shooting_155.html), [Pre-Release](https://onlinemanual.nikonimglib.com/z8/en/csmd_pre-release_capture_options_233.html) | 사용자 메뉴, 가림/불규칙 움직임에 대한 추적 반응 설정, 단계별 초점 이동, 반셔터 버퍼 | 가림 시 즉시 다른 물체로 튀지 않는 대상 유지, 실패/재선택 규칙, 스태킹 설계 | 초점 이동 촬영과 최종 스태킹을 구분. 전용 카메라의 선행 촬영/고속 원본 버퍼를 프리뷰 프레임 저장으로 대체하면 품질 계약이 달라짐 |
| Fujifilm X-T5 — [Q 메뉴](https://fujifilm-dsc.com/en/manual/x-t5/shortcuts/quick_menu/), [My Menu](https://fujifilm-dsc.com/en/manual/x-t5/shortcuts/my_menu/), [화질/커스텀](https://fujifilm-dsc.com/en/manual/x-t5/menu_shooting/image_quality_setting/), [MF 표시](https://fujifilm-dsc.com/en/manual/x-t5/taking_photo/manual-focus/) | 빠른 메뉴·사용자 메뉴, 필름 시뮬레이션/톤/WB/그레인과 커스텀 저장, 초점 확대·피킹·심도 표시 | 룩+노출/WB/심도 조합 저장, 선택 초점 위치 확대, 화면 표시 항목 선택 | 실제 광학 거리/심도 표시와 AI 상대 깊이는 다름. 제조사 필름 처리와 임의 LUT를 동일 결과로 표시하지 않음 |
| [Leica Q3](https://leica-camera.com/en-int/photography/cameras/q/q3-black) | 실제 Summilux 28 f/1.7 렌즈·매크로, hybrid AF와 피사체 인식, 물리 조작 중심 제품 | 필요한 조작만 우선 노출하고 촬영 흐름 일관성 확보 | Q3의 센서/렌즈·광학 매크로와 앱의 소프트웨어 f값은 다른 기능. 앱 프로필 추가만으로 같은 광학 결과를 보장할 수 없음 |

카메라의 포커스 스태킹은 **여러 거리를 함께 선명하게 만드는 기능**이다. 배경/전경 아웃포커스 개선과는 목적이 다르므로 두 과제를 섞지 않는다.

## 5. PhotoP에서 직접 확인한 공백

| 영역 | 현재 소스/미커밋 상태 | 근거와 개선 의미 |
|---|---|---|
| 기본 촬영 조작 | 수동·AF-S/AF-C·AF-ON·AF/AE 범위·네이티브 추적 분기 있음 | [FocusControlPolicy](../ios/PhotoP/Camera/FocusControlPolicy.swift), [간편 패널](../ios/PhotoP/UI/CameraQuickControls.swift). **AF 기능 전체 미구현으로 분류하면 틀림** |
| 촬영 프리셋 | 룩 LUT/마감 프리셋만 저장. 촬영 설정 전체 C 슬롯은 없음 | [FilterPresetLibrary](../ios/PhotoP/Storage/FilterPresetLibrary.swift). F13의 실질적 공백 |
| AF와 가상 초점 대상 | 탭 좌표 기반 연결은 있음. 추적 중 심도는 제한하고 MF/잠금과 탭 정책을 구분 | [CameraModel](../ios/PhotoP/Camera/CameraModel.swift), [CaptureWorkflowPolicy](../ios/PhotoP/Camera/CaptureWorkflowPolicy.swift). C04/C05의 대상/좌표·실패 복귀 통합이 남음 |
| 초점 확대 | 중앙 MF 확대는 있음 | 선택한 피사체/탭 위치 확대가 필요. 중앙 확대만으로 화면 가장자리의 머리카락·눈·전경 상태를 확인하기 어려움 |
| 수평계 | Core Motion 기반 기울기 구현은 있으나 AI 구도+코치가 켜진 조건에 묶임 | `CameraModel.updateMotion()`. AI를 다시 켜지 않고 **독립 수평계**로 분리할 여지가 큼 |
| 심도 거리/렌즈 모델 | 절대 깊이 반경 식이 가상50mm/36mm 기준. 상대 깊이는 장면 span으로 정규화 | [SoftwareDepthPolicy](../ios/PhotoP/Processing/SoftwareDepthPolicy.swift). 실제 카메라 화각·크롭과 선택한 가상 프로필의 관계/장면 간 안정성 검증 필요 |
| 보케 품질 | Natural/Portrait/Classic·매트·전경 합성·타일 halo 있음. 전날 CoC/작은 전경 개선은 미커밋 | [37 기록](37-CAMERA-DEPTH-QUICK-CONTROLS.ko.md), [NaturalDepthEngine](../ios/PhotoP/Processing/NaturalDepthEngine.swift). 추가 렌즈 이름보다 근/중/원거리·경계·원본 보존 검증이 먼저 |
| 고해상도 출력 품질 | 해상도는 최대64MP 유지하지만12.6MP 초과에서 `qualityPairs`16→8 | [고해상도 처리](../ios/PhotoP/Processing/HighResolutionPhotoProcessor.swift). **해상도 유지와 동일 합성 품질은 다름**. 고품질 출력 선택/후처리 큐 후보 |
| 파생 출력/메타데이터 | 일반/고해상도 파생 경로가 JPEG 품질0.95 중심. RAW 현상 없음 | [SDRImage](../ios/PhotoP/Processing/SDRImage.swift), 고해상도 처리. 품질 우선 형식/ICC·EXIF와 AI 표기를 실제 경로별 구현해야 함 |
| 공유/위치 | 원본 보관/Photos 저장·공유는 있음. 위치 수집/공유본 GPS 제거 정책은 아직 구현 전 | [PhotoStore](../ios/PhotoP/Storage/PhotoStore.swift), [36 확정 정책](36-USER-DECISIONS-AND-BRANCH-CLEANUP.ko.md). 이미 정한 정책의 구현 과제이며 새 결정을 묻는 항목 아님 |
| 촬영 반응 | 촬영 뒤 합성을 기다리는 동안 같은 busy 상태를 사용 | `CameraModel.capture()`→`renderCaptureResults()`. 원본 저장 후 다음 촬영과 제한된 후처리를 분리할 여지(B07) |
| 하드웨어/진입점 | Camera Control·App Intents·잠금화면 캡처 확장 코드는 검색에서 확인되지 않음 | Camera Control은 기존 F3. 잠금화면 확장은 별도 앱 구성/권한/저장소 검증이 필요하며 단순 버튼 추가와 다름 |

## 6. 추가 개선 권장 목록

아래 U/D/Q 식별자는 이 보고서의 제안 ID이며 새 구현 완료/사용자 확정을 뜻하지 않는다. 난이도는 소스 구조에 근거한 상대 판단이며 일정 약속이 아니다.

| 우선 | ID | 권장 개선 | 사용자 효과 | 기존 과제·난이도 |
|---|---|---|---|---|
| P0 | Q0 | 전날 UI/CoC 변경의 iOS·기기 인수 | 레이아웃/실제 합성 실패를 먼저 제거 | V01~V07, 필수 검증 |
| P0 | Q1 | 품질 우선 출력·AI 메타데이터·공유/원본 위치 경로 완성 | 이미 확정한 저장/공유 동작과 실제 결과 일치 | F4/F12, 중~상 |
| P1 | U1 | **C1–C3 촬영 프리셋** | 인물·제품·야경 등 자주 쓰는 조합 즉시 복원 | F13, 중 |
| P1 | U2 | **간편 메뉴 편집과 사진/영상별 기억** | 자주 쓰는4~6개부터 접근, 긴 스크롤 감소 | F13 연계, 중 |
| P1 | U3 | **AI와 분리한 독립 수평계** | AI 추천을 끈 상태에서도 수평/수직 확인 | 기존 Core Motion 재사용, 하~중 |
| P1 | U4 | **선택 초점 위치 확대·AF/AE 상태 피드백** | 어디를 선명하게 남길지 빠르게 확인, 요청 위치/실제 잠금 혼동 감소 | C04/C05, 중 |
| P1 | D1 | **AF와 가상 초점면 대상 통합** | 가까운 전경과 먼 피사체를 바꿀 때 초점/심도가 따로 움직이는 문제 감소 | C04/C05/V02/V05, 상 |
| P1 | D2 | **심도·선명 영역·불확실 영역 보기** | 과도하게 흐려지는 곳과 깊이 오류를 촬영/편집에서 확인 | C01/C02, 중~상 |
| P1 | Q2 | **고품질 심도 출력과 촬영/후처리 분리** | 셔터 반응을 유지하면서 저장 결과의 샘플 품질 선택 | B07/B06/C02, 상 |
| P2 | D3 | **가림/움직임에 대한 초점 유지와 명시적 재선택** | 인물 앞을 다른 사람이 지나갈 때 초점 튐 감소 | C03/C04/B03, 상 |
| P2 | D4 | **깊이 보정 브러시·Undo/Redo** | 자동 깊이가 틀린 울타리·잔머리·유리 주변을 선택적으로 복구 | C01 확장, 상 |
| P2 | D5 | **가상 초점거리·렌즈 모델 정합** | 장면/화각별 보케 표현 일관성 향상 | C02/C09, 상 |
| P2 | U5 | **그레이 카드 WB·자주 쓰는 조명 프리셋** | 같은 장소 연속 촬영의 색 흔들림 감소 | 기존 WB 확장, 중 |
| P2 | U6 | **Camera Control·빠른 앱 진입** | 지원 iPhone의 하드웨어 조작/시작 시간 감소 | F3, 중; 잠금화면 확장은 별도 상 |
| P2 | U7 | **보관함 썸네일·작업 상태·용량/손상 안내** | 촬영 후 결과 탐색/복구 부담 감소 | C06/C07/B07, 중 |
| P3 | Q3 | RAW 현상·최소 처리 비교 경로 | 처리 선택권과 원본 재현상 제공 | 신규 RAW PoC, 상 |
| P3 | Q4 | 포커스 스태킹·인터벌/별궤적 | 접사·제품/장시간 촬영 확장 | F5/F9, 상 |

### 6.1 프리셋/간편 메뉴: 단순하게 유지할 조건

- C1–C3는 사용자가 이름을 붙이는 **촬영 설정 저장 공간**으로 제안한다. 룩 즐겨찾기와 구분하며 노출·WB·AF·f값·포맷·모니터/가이드 조합을 저장한다.
- 기기/렌즈가 달라져 지원하지 않는 값은 범위 재검증 후 명확히 알린다. 다른 렌즈의 MF 위치0.7을 같은 물리 거리로 복원하지 않는다.
- 기본 심도 화면은 계속 ‘켜기→f값→대상 터치’다. D2 깊이 보기·D4 브러시·D5 렌즈 세부는 고급 설정/촬영 후 편집에 둔다.
- 값 조절마다 완료 버튼을 누르게 만들지 않는다. 프리셋 덮어쓰기·현재 변경 유지/복귀는 명확하게 구분한다. 실패한 장치 설정을 성공한 프리셋으로 표시하지 않는다.
- 간편 메뉴는 고정된 추천 기본 구성을 제공하고, 사용자가 편집을 선택할 때만 항목을 바꾸게 한다. 기존 박스형 뷰파인더와1.5배 패널을 유지한다.

### 6.2 중·원거리 피사체와 근거리 전경 흐림

**더 큰 블러 반경만 적용하는 방식은 권장하지 않는다.** 근거리 물체의 경계·가림·깊이 신뢰도와 초점 대상부터 맞춰야 한다.

1. 광학 AF 요청과 소프트웨어 초점 선택에 하나의 대상/좌표 계약을 사용하고 AF 실패·렌즈 변경·미러·회전 때 오래된 초점면을 폐기한다.
2. 원경 초점 앞의 작은 전경, 전경 초점 뒤의 원경을 별도로 평가한다. 전경 흐림이 선명한 배경에 퍼지는 현상은 필요하지만 피사체 색 번짐/구멍은 줄여야 한다.
3. 깊이·매트의 경계와 시간 안정성으로 불확실 영역을 추정할 수 있다. 이 값을 보정되지 않은 ‘정확도95%’나 실제 센서 신뢰도처럼 표시하지 않는다. 불확실하면 흐림을 줄이거나 원본으로 복귀한다.
4. 인물 전체를 같은 깊이로 고정하지 않고 선택 피사체와 초점 주변의 경계를 보완한다. 머리카락·안경·가느다란 가지는 별도 인수 장면으로 둔다.
5. 12.6MP 초과 샘플 감소와 타일 경계/halo를 검증한 뒤 고품질 오프라인 옵션을 추가한다. 단순히 f범위를1.4~20 등으로 늘리는 것보다 효과가 크다.
6. 상대 깊이는 장면이 바뀌면 척도가 달라질 수 있다. 절대 깊이와 구분하고, 기존 가상50mm 식을 다른 화각/프로필로 넓히려면 레시피 버전·프리뷰/저장 일치를 함께 검증한다.

### 6.3 표시할 수 있는 거리와 표시하면 안 되는 거리

[Apple lensPosition](https://developer.apple.com/documentation/avfoundation/avcapturedevice/lensposition)은 장치 간 일관된 실제 초점 거리가 아니고, 끝값도 무한대라는 뜻이 아니라고 명시한다. [minimumFocusDistance](https://developer.apple.com/documentation/avfoundation/avcapturedevice/minimumfocusdistance)는 **최소 초점 가능 거리**이며 현재 피사체 거리가 아니다. [depthDataAccuracy](https://developer.apple.com/documentation/avfoundation/avdepthdata/depthdataaccuracy)는 깊이 보정/단위의 정확도 한계를 설명한다.

- 상대 깊이에는 가까움/멀어짐·초점면 대비 위치를 사용한다. 정규화 MF 값을 임의로 m로 바꾸지 않는다.
- 유효한 절대 깊이로 측정한 위치에만 추정 거리를 표시하고, 렌즈·기기·유효 범위/정확도 한계를 함께 검증한다.
- Canon의 앞/뒤 초점 방향 가이드나 Fujifilm의 광학 심도 막대를 똑같이 보이는 UI로 만드는 것과 실제 측정 기능 구현은 다르다.

### 6.4 저장/공유 품질

- 원본 내보내기는 재인코딩/축소 없이 원래 위치와 파일을 보존한다. 공유는 GPS/관련 위치가 제거된 별도 사본을 만든다. 원본 위치가 없으면 만들어 넣지 않는다.
- AI 파생물은 처리 종류·사용 모델/처리 버전 등 지원 가능한 메타데이터와 앱 결과 정보로 설명한다. 구도 분석/일반 LUT까지 AI 생성 사진으로 일괄 표시하지 않는다.
- JPEG/SDR HEIF 등은 동일 원본·크기·색공간에서 비교한다. 품질1.0이나 TIFF라는 형식 이름만으로 손실/압축 흔적이 사라지는 것은 아니다. 기존 JPEG0.95를 품질 우선 계약의 완성으로 간주하지 않는다.
- 후처리 작업 수·메모리·저장 공간을 제한하고, 원본 저장 완료와 파생 결과 처리 중/실패를 구분한다. 실패해도 다음 촬영과 원본 접근을 유지하는 방향이다.

## 7. 지금 도입하지 않거나 뒤로 둘 기능

| 기능 | 판단 이유 |
|---|---|
| HDR/Log/게인맵·C2PA | 사용자 제외 결정 유지. 경쟁 앱이 제공한다는 이유로 다시 도입하지 않음 |
| AI 구도 추천·미적 점수·자동 촬영 코치 | 현재 임시 중지 요청 유지. 독립 수평계/AF 개선과 혼동하지 않음 |
| 프리뷰 프레임으로 고화질 선행 촬영/RAW 버퍼 흉내 | 프리뷰 해상도·압축·색은 원본 사진과 다름. Nikon Pre-Release와 같은 품질/지연을 보장할 근거 없음 |
| 노출/가상 f값/디지털 줌으로 광학 ND·대형 센서·장초점 렌즈 대체 | 실제 광량·광학 시점·물리 조리개가 바뀌지 않음. 새로운 표시 이름만으로 해결할 수 없음 |
| 다중 카메라 원격 제어·클라우드 편집 협업·라이브 방송 | Blackmagic에는 있으나 PhotoP의 현재 사진/심도 문제와 거리가 크고 비용이 큼 |
| 다양한 스티커형 보케·3D 조명부터 확장 | 창작 기능 가치가 있으나 자동 경계/전경 품질·단순 조작을 먼저 완성하는 편이 적합 |
| 모든 환경의 강제 셔터 무음 | [37 공식 API 검토](37-CAMERA-DEPTH-QUICK-CONTROLS.ko.md)에 기록한 기기/지역 지원 제한이 있음. 저화질 영상 대체를 해결책으로 간주하지 않음 |

## 8. 권장 개발 순서와 인수 기준

| 단계 | 실행 후보 | 완료 판단 근거 |
|---|---|---|
| A | Q0: 현재 미커밋 UI/CoC 변경 검증 | 정확한 SHA의 iPhone/Simulator 빌드·단위/UI, 세로/가로·작은 화면·접근성 확인.37의 기존 portable134/Python31은 이전 작업 결과로만 인용 |
| B | Q1: 확정 출력/위치/AI 표기 계약 | 원본 byte/hash 유지, 공유 GPS 제거, 원본 GPS 보존, 권한 거부/무위치·포맷별 메타데이터·색/크기 회귀 |
| C | U1/U2/U3/U4: 프리셋·간편 메뉴·독립 수평계·대상 확대 | 같은 촬영 설정 재현에 필요한 조작 수 비교, 미지원 렌즈 복원/중단/회전·큰 글씨 검증. 새 메뉴가 뷰파인더를 침범하지 않음 |
| D | D1/D2/Q2: 초점면 일치·심도 표시·고품질 처리 | V03의100장 인수에 중/원거리 전경·가림·반사·작은 대상 포함,24/48MP 시간/peak memory·열·원본 불변·타일/프리뷰-출력 일치 |
| E | D3/D4/D5/U5/U6/U7 | 움직임/가림 재선택, 보정 Undo/Redo·저장 복구, WB 색 비교, 지원 하드웨어 조건 확인. [Camera Control 공식 API](https://developer.apple.com/documentation/avfoundation/avcapturecontrol)와 실제 기기 지원을 함께 확인 |
| F | Q3/Q4: RAW 현상·스태킹/인터벌 | 대표 장면별 기존 시스템 처리 대비 장단점·합성 실패·렌즈 호흡/고스트·발열/용량 검증 후 채택 여부 판단 |

가장 먼저 묶어 진행할 **기능 개발 후보는 C1–C3 + 간편 메뉴 + 독립 수평계 + 선택 위치 확대**다. 심도 차별화의 중심은 **대상 일치 + 경계/전경 + 고품질 출력**이다. 새 제품 정책 승인 없이 진행 가능한 기술 설계/PoC와, 실제 기기 인수에 필요한 촬영 자료를 구분한다.

## 9. 이번 작업의 변경·검증 상태

- 후속 사용자 제공 검증 환경(2026-11-19): **iPhone 15 Pro / iOS 27.2**. 우선 이 한 대의 렌즈/포맷 지원·세로/가로 배치·터치/잠금·근/중/원거리 심도·고해상도 출력·열/저장 중단을 확인한다. 기기 연결이나 촬영/SDK 검증을 수행한 것은 아니다.
- iPhone 15 Pro의 LiDAR·메인 카메라48MP 지원과 별개로, 깊이 입력/렌즈/촬영 모드마다 가능한 사진 해상도는 실제 capability 조회로 정한다. 이 기기의 광학 망원 기준은3배이며5배 모델로 취급하지 않는다. 물리 Camera Control 버튼은 없으므로 U6의 해당 버튼 인수는 제외하고 터치 UI를 기준으로 한다.
- 사용자가 제공한 iOS 27.2와 기존 CI의 SDK/Simulator 버전은 구분한다. 해당 OS·지원 API 분기의 검증과 설치 가능한 서명 빌드 준비가 남아 있으며, 단일 기기 결과를 최소/전체 지원 기기의 인수로 확대하지 않는다.
- 이번 변경은 이 보고서·출처 JSON·백로그/진입 링크·11월19일 개발 일지다. 이전 미커밋 앱/테스트 변경을 덮어쓰지 않았다.
- 앱 코드 구현·테스트 재실행·실기기 비교 촬영·성능 측정·커밋·push·main 머지는 하지 않았다. 소스/파일 보존과 문서 링크/형식 검증 결과는 [당일 일지](development-log/2026-11-19.md)에 기록한다.
- 후속 항목의 공식 과제 연결은 [32 백로그](32-NEXT-TASK-BACKLOG.ko.md), 현행 확정 정책은 [36 기록](36-USER-DECISIONS-AND-BRANCH-CLEANUP.ko.md), 전날 미커밋 구현은 [37 기록](37-CAMERA-DEPTH-QUICK-CONTROLS.ko.md)을 따른다.
