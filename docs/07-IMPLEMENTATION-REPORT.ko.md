# 현재 개발 단계 보고

기준: 2026-10-21 KST. MetaParodica/PhotoP, `codex/ios-camera-foundation`, [Draft PR#1](https://github.com/MetaParodica/PhotoP/pull/1). 초기 Phase1–6 이후 성능·사진 해상도 요청·룩 지원 확장을 구현하고 단위별 자동 gate를 통과했다. 실제 iPhone 품질 승인은 미완료다.

## 1. 구현 기능

기존 native 카메라/수동 제어·RAW/ProRAW·노출 분석/브래킷·SDR Metal LUT/비파괴 편집·장노출·구도 가이드를 유지한다. 이번 변경은 다음과 같다.

- 중립 preview의 불필요한 LUT compute/graded texture 제거, immutable Metal PSO 재사용, thermal/저전력 처리량·분석 빈도 조절.
- 활성 포맷의 실제 지원 목록에서 사진별 해상도 상한 선택, 일반 저장 파일의 실제 픽셀 크기 표시.
- 단독1D cube의 채널별 직접 보간, 기존3D cube/Hald와 편집·실시간 미리보기·preset/favorites 연결.
- 자체24종·외부 slay5종 총29 룩, 검색/분류/색상표, 최대32개 LUT 순차 가져오기와 부분 성공/실패 보고.
- 외부 LUT/license 원본·SHA256·creator/credit/source/profile assumption 보존, favorite/preset/recipe/JPEG caption attribution 유지, 실제 app bundle 검증.

## 2. 참고 소스와 라이선스

[13 문서](13-PERFORMANCE-CAPTURE-LOOKS.ko.md)에 실제 읽은 파일·고정 revision·판단을 기록했다. MetalPetal MTIContext의 cache 구조(MIT), OpenColorIO IridasCube parser(BSD-3-Clause)를 참고해 독립 구현했다. slaycamera/luts의 LUT 자체 CC BY4.0·README·LICENSE 전문·생성기·5개 원본 cube/RGB행을 확인했다. 해당 LUT5개와 license만 포함하고 타사 UI/사진/생성기 코드는 복사하지 않았다.

기존 Starlapse/PoseGuide/hald-clut 검토는 [11](11-PHASE4-6-IMPLEMENTATION.ko.md), 공식 브랜드 LUT 제공 사실과 미확정 재배포권은 [12](12-FILM-SOURCES-AND-QUALITY.ko.md)에 유지한다. slay5개 허가를 다른 자료에 확대하지 않는다. 자체 profile-data 허가는 Film/STYLE-PERMISSION.txt 범위다.

## 3. 기술적 접근

고빈도 mutable 프레임은 한 작업씩 처리하고 immutable PSO만 공유한다. 중립 출력은 색변환된 source를 직접 사용한다. 열 상태의 처리 budget은 센서/촬영 설정을 바꾸지 않는다. 사진 해상도는 activeFormat/output의 실제 값 중 per-request로 선택하고 실제 결과 metadata와 구분한다. 1D는 낮은3D 표로 굽지 않고 채널별 curve를 직접 보간한다. LUT batch는 한 파일씩 저장해 전체 파일을 동시에 RAM에 유지하지 않는다.

외부 룩은 입력 profile이 미기재이므로 PhotoP의 sRGB SDR 가정 확인 후 적용한다. 원본 LUT byte/hash·license와 metadata/JPEG attribution을 함께 유지한다. 기존 uncredited favorite에 동일 LUT의 검증된 출처를 다시 저장하면 metadata만 보강한다.

## 4. 생성·수정 파일

- 신규: MetalPipelineCache.swift, PreviewBudget.swift, PhotoResolution.swift, BundledFilmLibrary.swift, LUTBatchImporter.swift, PreviewBudgetTests/PhotoResolutionTests/OneDLUTTests/BundledFilmLibraryTests/LUTBatchImporterTests.
- 수정: CameraService/CameraModel/CameraTypes/CapturedPhoto/ManualControls; CubeLUT/MetalLUTResources/LUT.metal; FilmStyleLibrary/STYLE-PERMISSION/FilmFinish; live/still renderers·preview processor/analyzer; LUTLibrary/LUTPhotoEditor/SDRImage·스타일/편집/미리보기/즐겨찾기 UI; 기존 관련 tests.
- 자산·CI: LUT5개·license·manifest, lut-catalog, project.yml, ios.yml, 자산 검사 script/tests. 문서04/05/06/07/08/11/12/13·README 갱신.

## 5. 실행·테스트 결과

| 단위 | revision | CI | 결과 |
|---|---|---|---|
| preview 최적화 |6d7d2eae672735dff4122bc5e4372010672066b1|[39544188467](https://github.com/MetaParodica/PhotoP/actions/runs/39544188467)|SDK·Swift124·Python7 성공|
| 해상도 요청 |6977d87b5a7275211ff76ebf1a11c70429d97d37|[39544511878](https://github.com/MetaParodica/PhotoP/actions/runs/39544511878)|SDK·Swift128·Python7 성공|
| 1D cube |f274a26e2936951299d5ef89380982fc046d6569|[39544857433](https://github.com/MetaParodica/PhotoP/actions/runs/39544857433)|SDK·Swift132·Python7 성공|
|29종/권리/batch/credit·정밀도 수정|3abee4006a3298a49eb63dde8dae710a37c747c9|[39550566621](https://github.com/MetaParodica/PhotoP/actions/runs/39550566621)|SDK·Swift139·Python11·source/app bundle5개 hash 성공, skip0|

첫 룩 통합에서 Neon Rose의17³ 보간이 기존0.015 오차 gate를 넘었다. 입력(0.9,0.8,0.1)의 청색 오차0.01604를 재현했고 허용 오차를 유지한 채 해당 스타일만33³로 높여 회귀 테스트를 추가했다. 나머지 스타일과 기존12종 기본 표는 유지한다. 수정 후 전체가 통과했다. unsigned SDK/XCTest는 GitHub macOS에서, 로컬 Python11은 Linux에서 실행했다. 실제 기기에서 실행했다고 주장하지 않는다. AppIntents/portrait의 기존 경고는 유지된다.

## 6. 확인된 제약

실측 FPS/지연/배터리/발열/RAM 개선량은 없다. 처리 budget 감소를 실제 speed-up으로 표시하지 않는다. 해상도 요청은 최대 상한이며 실제 결과는 더 작을 수 있고, RAW/브래킷의 임의 크기 선택은 제공하지 않는다. SDR 편집은12.6MP·sRGB JPEG로 제한하고 원본은 보존한다.

29종은 브랜드 필름/유제 측정 재현이 아니다. 외부5개는 sRGB 해석을 가정하며 Log/HDR에 직접 적용하지 않는다. 실제 피부/야경/고채도·banding/halo 미학 평가는 미완료다. 100종·mixed shaper·고급OCIO config·RAW 현상/HDR grading·고해상도 편집·가로 UI·영상/Android는 후속이다.

기존 장노출은1280px·최대2fps 처리 SDR 샘플·128MiB frame archive·±8px 정수 translation이다. 회전/원근·일반 handheld 보장·median/motion-aware·재시작 archive browser·crash orphan recovery는 미구현이다. 구도 Vision 정확도/실제 지연·semantic building/소실점·자동 perspective correction과 실제 촬영/EXIF/Photos·장시간 품질 승인은 별도 대기다.

## 7. 다음 단계

실기기에서 처리량·색/화질·고해상도 delivery를 측정하고 실제 이득이 확인되는 항목을 우선 개선한다. 제품 로드맵의 다음 기능 단계는 Phase7 영상이며 이번 요청에서 영상/Android를 구현했다고 표시하지 않는다. 최신 전체 테스트·소스/권리·제약은13 문서와 PR checks를 따른다.
