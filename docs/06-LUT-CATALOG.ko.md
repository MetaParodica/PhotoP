> 현재 정책 보충: 이후 사용자가 권리 확인과 무관하게 확보 LUT를 모두 포함하도록 지시했다. 따라서 아래의 초기 제외 정책은 기존 승인 컬렉션에 대한 기록으로 남기고, 신규 `company-luts` 25개는 미확인 상태를 명시하여 Debug/Release 모두 포함한다. 허가를 확인한 것으로 바꾸지 않는다. [실제 신규 원본·프로파일·해시](15-EXTERNAL-LOOKS.ko.md), [공간 효과 8종](16-SPATIAL-STYLES.ko.md)을 함께 참조한다.

# LUT·필름 라이브러리 조사와 포함 정책

기준: 2026-10-21 KST. 아래는 **출처를 찾은 카탈로그**이며 LUT 바이너리를 확보·검수·번들 완료했다는 뜻이 아니다. 기계 판독용 출처 목록은 `assets/lut-catalog.json`에 보존한다. 현재 외부 LUT 바이너리 번들은 **CC BY4.0 slay5개**이고, 런타임에 생성하는 자체 sRGB 스타일은24종이다. 100개 이상의 스타일은 후속 품질 목표다.

## 공식 공급사 우선 조사

| 브랜드 / 자료 | 공식 제공 확인 | 입출력·용도 | 앱 포함 판단 |
| --- | --- | --- | --- |
| ARRI LogC3/4 packages·Look Library | [공식 LUT 자료](https://www.arri.com/en/software/postproduction-software/legacy/lut-generator), [Looks](https://www.arri.com/en/learn/camera-systems/image-science/look-files) | 기술 변환과 log-to-log creative looks를 구분; C3/C4 호환 아님 | 다운로드 가능. 앱 재배포·상용 권한과 개별 파일 profile은 확인 필요 |
| Sony Look Profile | [공식 자료](https://www.sony.com/electronics/support/professional-cameras-digital-cinema-cameras/pmw-f55/software/00263050) | S-Gamut3.Cine/S-Log3 등 정확한 profile 필요 | 공식 제공과 재배포 허가는 별도; 보류 |
| Canon Log2/3 → CMT709 | [공식 백서](https://www.usa.canon.com/content/dam/canon-assets/white-papers/pro/Canon-709-CMT-709-WP.pdf) | Cinema Gamut·Log 버전·range 구분 | 공식 LUT 안내 확인; 정확한 패키지와 약관 후속 검토 |
| Panasonic V-Log | [공식 다운로드](https://av.jpn.support.panasonic.com/support/global/cs/dsc/download/lut/) | V-Log/V-Gamut→V709; .cube/.vlt 지원 구별 | 공식 제공 확인; 재배포 보류 |
| Nikon N-Log / RED creative | [공식 다운로드](https://downloadcenter.nikonimglib.com/en/download/sw/258.html) | N-Log→Rec.709 technical + RED 계열 creative | LUT 버전·기종·입력 profile 및 재배포권 후속 확인 |
| RED IPP2 | [공식 LUT Creator](https://docs.red.com/955-0004/REDCINE-XProOperationGuide/Content/6_ExportClips/IPP2_LUT_Creator.htm) | RWG/Log3G10·output tone map·display space 구분 | 도구의 export 가능과 결과 파일 재배포권을 분리해 확인 |
| DJI | [공식 LUT 센터](https://www.dji.com/lut) | 기종별 D-Log/D-Log M→709/HLG/sRGB | 공식 제공 확인; 기종·curve·asset 약관 후속 검토 |
| Fujifilm | [공식 F-Log 활용 설명](https://shopusa.fujifilm-x.com/discover/grading-fujifilm-f-log-footage-with-csts-and-luts/), [Film Simulation LUT 설명](https://shopusa.fujifilm-x.com/discover/what-are-fujifilm-gfx-eterna-55-s-3d-film-simulation-luts-/) | F-Log/F-Log2/F-Log2 C·각 gamut의 차이를 구분 | 공식 LUT가 전혀 없다고 판단하면 오류. 다만 모든 Film Simulation의 자유 재배포가 확인된 것은 아님 |
| Blackmagic Design | [공식 gallery](https://www.blackmagicdesign.com/products/blackmagicursacine/gallery/), [Camera 사양](https://www.blackmagicdesign.com/products/blackmagiccamera/techspecs/W-APP-02) | Gen 5 Film 등 입력과 creative looks 구분 | 제공 예·앱 내 LUT 확인; 추출·번들 재배포는 아직 허가 미확인 |
| Apple Log | [공식 색공간 enum](https://developer.apple.com/documentation/avfoundation/avcapturecolorspace), [공식 transfer 설명](https://developer.apple.com/documentation/corevideo/cvimagelogtransferfunction/applelog) | 지원 기기/포맷에서 캡처; Log profile white paper 확인 필요 | LUT 자체의 라이선스와 구현 수학 근거는 후속. 새 Log 버전은 별도 capability |
| Kodak | Portra 160/400/800, Gold 200, Ektar 100, Ultramax, Kodachrome, Ektachrome, Tri-X, 2383 목표 조사 | 영화 print stock과 카메라 negative·slide를 구분 | 브랜드 직접 공급·자유 재배포 LUT는 이번 조사에서 미확정. PoLUT·Hald·상용 preset은 비공식/별도 제작자 자료 |
| Leica | 공식 제공 범위 후속 확인 | L-Log technical vs 색감 에뮬레이션 구분 | Lumix-film-simulation을 Leica 공식 LUT로 표기 금지 |
| Agfa / Polaroid / Ilford | 공식 제공 범위 후속 확인 | Hald 등 third-party 필름 근사 스타일 | 공식성·재배포권을 추정하지 않음 |

Log curve 변환만으로 타사 센서의 분광 감도·노이즈·하이라이트·렌즈 반응을 복원할 수 없다. 따라서 브랜드 변환 LUT를 적용했다고 실제 카메라/필름을 물리적으로 동일하게 재현한다고 주장하지 않는다.

## 오픈·비공식 후보

| 자료 | 분류 | 권리 검토와 기술 주의 |
| --- | --- | --- |
| PoLUT | 비공식 필름 모델·cube 생성 | GPL 도구·스펙트럼/스캔 자료·출력 LUT 범위를 각각 확인. scene-to-display 역할에 주의 |
| cedeber/hald-clut | Hald 모음·변환 | 저장소 GPL 표기와 원자료 라이선스 범위 추적 |
| NatronGitHub/clut | Hald 자산 모음 | README CC-BY-SA-4.0; 원저작자·변환 이력·credit 보존 |
| graplo/obs-film-luts | Hald 파생 strip | README CC-BY-SA-4.0; strip 순서·색공간·출처 사슬 검증 |
| FilmFrame | MIT Android 코드·별도 LUT | 코드 MIT를 포함 LUT에 일괄 적용 금지; 특정 Fuji 입력 전제 분리 |
| Film-Simulator | MIT KMP 편집 앱 | 실제 LUT·FFmpeg 관련 바이너리·코덱의 개별 조건 확인 |
| Lumix-film-simulation | V-Log 출발 cross-brand 자료 | 최상위 license 미확정; 공식 LUT 파생 자료 여부·원자료 허가 확인 |
| darktable / RawTherapee | GPL RAW 편집 코드 | 프로그램 코드와 별도 film asset 컬렉션은 권리·용도를 독립 조사 |
| VSCO / RNI | 상용 경쟁 제품의 필름 색감·UX 참고 | 상용 앱에서 LUT/profile을 추출해 묶지 않는다. 사용자 소유 preset도 import 권한과 재배포권을 구분 |

## 사용자가 요청한 ‘모두 포함’의 구현 계약

수집한 모든 항목은 research catalog에 남기고 권리 상태 때문에 검색 목록에서 삭제하지 않는다. 파일의 저장소 업로드 자체가 재배포일 수 있으므로, 권한이 불명인 파일을 공개/공유 git 리포에 올린 뒤 상용 빌드에서만 빼는 방식은 기본으로 사용하지 않는다.

연구용 포함과 상용 포함을 분리한다. 연구용으로 사용·보관 가능한 원본은 개발자의 별도 private workspace에 둘 수 있고 앱 import 대상으로 사용할 수 있다. 재배포가 허용된 자료는 연구 패키지에 포함할 수 있다. 상용 앱에는 commercialUseAllowed와 redistributionAllowed가 모두 true이며 근거가 있는 자산만 복사한다. 두 권한은 각각 yes/no/unknown으로 기록한다.

현재 구현한 `assets/luts/manifest.json`과 검사 스크립트는 **상용 번들 허용 목록의 검증**이다. 연구 라이브러리 자동 다운로드·빌드별 자산 복사는 미구현이다. 사용자 cube/Hald import·favorites·전체 룩 preset·자체 스타일 UI는 구현했다. iOS target에는 검증한 slay5개 및 manifest/license 리소스를 포함한다. 자체 profile code와 좁은 데이터 사용 허가는 Film 폴더에서 관리한다. 현재 CI는 unsigned SDK app에 실제 복사된 manifest 및 LUT/license hash를 원본 허용 목록과 대조한다. 서명한 배포 archive의 최종 검사는 별도다.

## LUTProfile 메타데이터

필수: id, displayName, creator, sourceURL, officialStatus, licenseExpression/근거, commercialUseAllowed, redistributionAllowed, requiredCredit, sourceSHA256, inputProfile, outputProfile, role, domainMin/Max, latticeSize, intensityRange, previewReference, assetRevision, reviewedAt, bundledIn.

카탈로그에서 해시가 비어 있으면 미다운로드 또는 미검수다. unknown 값은 false와 구분하되 자동 상용 포함에는 사용할 수 없다. 즐겨찾기·사용자 import는 기기 로컬 데이터이며 자동 업로드하지 않는다.

## 확보·품질 로드맵

1. 공식 technical transforms의 profile·약관·hash를 먼저 검수한다.
2. 자체 sRGB 창작 스타일 8~12개로 렌더 계약을 검증한다. 상표 사용 없이 Warm Portrait, Soft Chrome 등 독자 이름으로 시작한다.
3. 허가 가능한 오픈 Hald/creative 후보를 검수해 25~40개 고유 스타일로 확장한다.
4. 피부·회색·고채도·야경·건축·풍경·HDR→SDR 평가를 통과한 독립 스타일을 100개 이상으로 확장한다. 같은 LUT의 강도만 바꿔 개수를 부풀리지 않는다.
5. Grain·halation·bloom·vignette·fade·CA는 LUT와 별도 노드로 제공한다. 처리 domain·seed·해상도 의존성을 recipe에 고정한다.

목표 카테고리는 Cinematic, Vintage, Negative, Slide, B&W, Portrait, Landscape, Travel, Street, Architecture, Urban Night, Retro, Analog, Moody, Pastel, Minimal, Warm, Cool, Dreamy, High Contrast, Matte, Documentary다. 특정 카테고리에 자산이 없으면 비어 있다고 표시한다.


Phase 6 공식 제공 사실·재배포 미확정 구분은 [12](12-FILM-SOURCES-AND-QUALITY.ko.md), 실제 source review와 구현은 [11](11-PHASE4-6-IMPLEMENTATION.ko.md)을 따른다. 사용자 import/preset은 앱 로컬 문서이며 자동 bundle 자산으로 승격하지 않는다.


## slay5개 실제 채택

[고정 원본](https://github.com/slaycamera/luts/tree/a1709044efe115640dde1dee17d4185fc059af0d)의 README·LICENSE 전문·생성기·5개 cube header/RGB행을 확인했다. CC BY4.0 LUT 자체 배포·credit 범위에서 원본을 변경 없이 포함한다. 원본 blob SHA/개별 SHA256·license hash·creator/credit/source는 assets/luts/manifest.json에 있다. 타사 UI/사진/생성기 코드는 포함하지 않는다. 공식 Log/필름 기술 변환으로 이름 붙이지 않는다.

Upstream transfer/gamut은 미기재이므로 sRGB는 PhotoP 가정이다. `profileBasis=assumed-sRGB`·`requiresSRGBConfirmation=true`, UI 확인·recipe에 표시한다. 실제 app bundle 검사·metadata/JPEG caption credit·favorites/preset 보존은 [13](13-PERFORMANCE-CAPTURE-LOOKS.ko.md)을 따른다. 나머지 외부 후보의 권리가 승인된 것으로 확대하지 않는다.

## 신규 확보 25개 전체 포함

개별 source/revision/SHA256/원본 경로는 `assets/company-luts/manifest.json` 및 `assets/lut-catalog.json`에 기록한다. Lumix 파생 23개·postprocessing 데모 미러 2개다. 공식 다운로드 링크만 확인한 브랜드 팩을 포함했다고 계산하지 않는다. 전체 외부 원본 30개 중 창작 룩 27개와 기술 변환 3개이며, WDR 1개는 출력 미확인으로 원본만 제공한다.
