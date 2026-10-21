# 현재 개발 단계 보고

기준: 2026-10-21 KST. `MetaParodica/PhotoP` main. 촬영 UI·외부 룩·공간 효과와 Phase 7 SDR 영상 1차 구현은 main에 병합되었다(`e87b484`). 이후 영상 오디오·손떨림 보정은 `claude/maintenance-guide` 브랜치에서 진행하며 [08 §31](08-STEP-VALIDATION.ko.md)에 기록한다. 초기 Phase1–6의 사진 기능을 바탕으로 UI·외부 룩·공간 효과를 확장했다. 실제 iPhone 품질 승인은 별도 대기다.

## 1. 구현 기능

- 제공된 보라색 카메라 이미지를 iPhone/App Store 아이콘에 적용.
- 촬영 화면의 아이콘을 누르면 ISO·셔터·EV·WB/Tint·초점의 선택 버튼/슬라이더가 펼쳐진다. 제스처 종료 시 기존 AVFoundation 서비스로 적용하며 실제 장치 지원 범위를 사용한다.
- 파일 포맷·지원 RAW/ProRAW·해상도 상한·브래킷·구도·노출 보조·룩 강도를 촬영 화면에서 조절한다. 파일 가져오기/전체 스타일 탐색·장노출 작업·사진 편집/기록은 별도 화면을 유지한다.
- 기존 외부 slay 5개에 이번 확보 25개 전부를 추가: 외부 원본 **30개**, 창작 외부 룩 **27개**·기술 변환 **3개**. 출력 미확인 WDR 1개는 포함하되 원본만 제공한다.
- 자체 컬러 LUT 24개+외부 창작 룩 27개=컬러 룩 51개. LUT와 별개인 Metal 공간 프리셋 8개를 더해 **59개 룩+기술 LUT 3개**를 제공한다.
- 소프트 포커스·색수차·가로 빛 번짐을 개별 조절하고 사진/라이브 공통 Metal 마감에 연결했다. 기존 그레인·fade/vignette/bloom/halation과 전체 프리셋·비파괴 레시피 복원을 유지한다.

## 2. 참고 소스와 라이선스

Apple HIG·공식 Design Resources·SwiftUI/SF Symbols를 검토했다. iOS26+ 지원 SDK에서는 native Liquid Glass, 이전 환경에서는 시스템 material을 사용한다. Figma/Sketch 목업 파일을 편집했다고 주장하지 않는다.

신규 LUT는 Lumix-film-simulation 고정 버전 23개와 postprocessing 데모의 RocketStock/Presetpro 2개다. 비공식 파생/미러 원본이며 제조사 공식 제공본으로 표시하지 않는다. 사용자 지시에 따라 미확인 권리를 포함 제한으로 사용하지 않되 license·상업 사용·재배포 허가는 unknown으로 기록한다. 기존 slay 5개의 CC BY4.0 허가를 신규 자료에 확대하지 않는다.

colour-science의 Panasonic V-Log/V-Gamut 변환 수학(BSD-3-Clause), GPUImage3 GaussianBlur(BSD-3-Clause), KinoStreak(MIT) 실제 소스를 비교한 뒤 독립 구현했다. 외부 UI/사진/Unity 프레임워크 코드는 복사하지 않았다. 구체적인 source/blob/판단은 [14](14-CAMERA-UI.ko.md)·[15](15-EXTERNAL-LOOKS.ko.md)·[16](16-SPATIAL-STYLES.ko.md)에 기록한다.

## 3. 기술적 접근

촬영 세션·GPU 처리·UI의 기존 책임을 유지한다. 설정 패널은 같은 CameraModel/서비스를 사용한다. 지원하지 않는 렌즈/RAW/포맷 조합이나 플래시·가짜 줌을 추가하지 않는다. 기본 격자와 선택된 구도 상태를 통일해 숨기기를 바로 사용할 수 있다.

V-Log 입력 LUT는 sRGB 값에 직접 적용하지 않는다. sRGB 디코딩→V-Gamut/V-Log→원본 LUT→Rec.709 gamma2.4 가정→sRGB의 **SDR 근사**를 65³ cube로 생성·검증·캐시한다. 원본과 렌더 LUT 해시를 구분한다. 장면 HDR이나 센서 특성을 복원하지 않는다.

공간 효과는 주변 픽셀과 위치를 사용하고 색상 LUT와 분리된다. 기존 한 마감 패스와 재사용 자원을 이용한다. 공간 프리셋의 identity cube는 레시피 컨테이너용 운반 데이터이며 실제 효과는 파라미터에 있다. 구형 레시피의 새 효과는 0으로 복원한다.

## 4. 생성·수정 파일

- UI: CameraView/CameraChrome/CameraQuickControls, FilmStylesView/FilmFinishControls, CameraInteractionTests, CameraChromeTests.
- 컬러·효과: CompanyFilmLibrary, SDRVendorAdapter, ProceduralLook, FilmFinish.swift/.metal, CompanyFilmLibraryTests/SpatialLookTests/FilmFinishTests.
- 자산: Assets.xcassets/AppIcon, app-icon-source.json, company-luts 원본 25개·manifest·notice, LUT 카탈로그, 화면 캡처.
- CI: iPhone SDK·Swift/UI tests·아이콘/양쪽 LUT 컬렉션 무결성·실제 앱 복사본 검사, simctl 캡처 전 부팅 확인, 결과 artifact.

## 5. 실행·테스트 결과

| 단위 | 코드 커밋/CI | 결과 |
| --- | --- | --- |
| 촬영 UI | `ea12093`, [39575774557 재시도](https://github.com/MetaParodica/PhotoP/actions/runs/39575774557) | SDK·Swift142·UI1·Python13 성공. 별도 캡처는 Shutdown 상태로 실패하여 수정. UI 테스트의 실제 화면은 회수. |
| 신규 LUT25·캡처 복구 | `7a15e0d`, [39579967039](https://github.com/MetaParodica/PhotoP/actions/runs/39579967039) | SDK·Swift149·UI1·Python17·source/app 자산30개 검사·기본/구도 화면 캡처 성공. |
| 공간 효과8·구도 상태 통일 | `6c569e0`, [39581407493](https://github.com/MetaParodica/PhotoP/actions/runs/39581407493) | SDK·Swift155·UI1·Python17·source/app 자산30개 검사·기본/구도 화면 캡처 성공. |

실행·검증은 GitHub macOS 및 Linux Python에서 수행했다. 캡처는 Debug 시뮬레이터에서 **실제 SwiftUI 앱을 실행한 화면**이며 합성 검토 배경임을 화면에 표시한다. 생성형 디자인 목업으로 테스트를 대체하지 않았다. 실제 카메라/실기기 촬영을 검증했다고 주장하지 않는다.

## 6. 확인된 제약

실측 iPhone FPS·지연·배터리·발열·RAM 개선량과 실제 피부/야경/고채도·banding/halo 평가는 미완료다. 캡처 환경은 Xcode16.4의 Simulator이며 iOS26 native Liquid Glass 분기는 이 환경에서 실행하지 않았다.

기존 SDR 편집 12.6MP·원본 보존, 샘플 장노출1280px/최대2fps·128MiB archive·±8px translation, 세로 구도/규칙·Vision의 기존 한계를 유지한다. 센서 연속 장노출·median/motion-aware/회전·원근 정렬·semantic building/소실점·RAW 현상/HDR grading·영상·Android는 구현 완료가 아니다. 100종 이상은 품질 확장 목표다.

## 7. 다음 단계

실제 지원 iPhone에서 카메라 제어·촬영 결과/EXIF·Photos·프리뷰/고해상도 출력의 색과 공간 효과·300초 안정성을 검증한다. 사용자의 지시에 따라 이 실기기 검증은 자동 테스트 통과 후의 다음 개발 단계를 막지 않는다. 영상은 다음 제품 단계이며 현재 구현으로 보고하지 않는다. 이전 성능/해상도/1D/29종 확장 이력은 [13](13-PERFORMANCE-CAPTURE-LOOKS.ko.md)과 [단계 로그](08-STEP-VALIDATION.ko.md)에 보존한다.
