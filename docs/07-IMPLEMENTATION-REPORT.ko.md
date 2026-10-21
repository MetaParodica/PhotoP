# 현재 개발 단계 보고

기준: 2026-10-21 KST. MetaParodica/PhotoP, `codex/ios-camera-foundation`, [Draft PR #1](https://github.com/MetaParodica/PhotoP/pull/1). 사용자 지시대로 실제 iPhone 검증은 별도 대기하고, 자동 테스트 성공 후 Phase 4→5→6으로 진행했다. 아래 제한된 개발 범위의 자동 검증을 완료했다. 상용 품질 승인·모든 PRD 기능 완료를 뜻하지 않는다.

## 1. 구현 기능

- 기존 Phase 1–3: native preview/수동 제어/원본 보존, SDR Metal LUT·grain·레시피, 동적 Bayer/ProRAW, histogram·Zebra·peaking, native 3장 bracket 유지.
- Phase 4: 1~300초 계산 장노출, 선형광 온라인 평균·RGB Lighten, 선택 translation 정렬, 중간 결과·취소·열 상태 대응, bounded lossless PNG archive와 새 bundle 재처리, JPEG·Photos·공유.
- Phase 5: 고급 격자·9종 자체 도식 포즈, optional on-device Vision saliency/body-pose/rectangle/horizon, confidence·stale·generation·aspect-fit 좌표 처리와 제안.
- Phase 6: 자체 sRGB 스타일 12종, 검색/분류/색상표, 전체 룩 preset의 영속 저장·복원·삭제, 제한된 Hald PNG import, 독립 fade/vignette/bloom/red halation, v1/v2/v3 recipe 호환·출처/hash 보존.

## 2. 참고 소스와 라이선스

[11 문서](11-PHASE4-6-IMPLEMENTATION.ko.md)에 Starlapse의 실제 mean/valid-edge/transfer 코드(MIT), PoseGuide의 synthetic normalized scaffolds(repo MIT metadata), hald-clut의 혼합 출처와 GPL metadata를 고정 revision으로 기록했다. 구현은 독립 작성했으며 소스·포즈 자산·외부 LUT 바이너리를 복사하지 않았다. Apple AVFoundation·Metal·Vision·ImageIO 공식 API를 사용한다.

[12 문서](12-FILM-SOURCES-AND-QUALITY.ko.md)는 ARRI/Sony/Fujifilm/Panasonic의 공식 제공 사실과 app redistribution 미확정을 구분한다. 외부 LUT 번들은 0개다. 자체 12종의 profile data 사용 허가는 `ios/PhotoP/Film/STYLE-PERMISSION.txt` 범위로 한정한다.

## 3. 기술적 접근

캡처 직렬 queue와 GPU/분석/file 작업을 분리한다. 장노출은 고해상도 N프레임을 RAM에 보관하지 않고 온라인 누적하며 제한적 alignment의 실패를 명시한다. lossless sampled frames를 디스크에서 순차 재처리한다. Vision은 이미 회전/미러링된 입력을 한 작업씩 분석하고 오래된 결과를 버린다. 색감은 기존 Metal 공통 함수를 재사용하고 마감 pass를 추가한다. full-look preset과 LUT-only favorites를 별도 저장한다. 사용자 파일과 배포 자산의 권리를 혼동하지 않는다.

## 4. 생성·수정 파일

- 신규: `LongExposure/{LongExposureStack,LongExposureCapture,LongExposureArchive}.swift`, `Composition/{CompositionGuide,CompositionAnalyzer}.swift`, `Film/{FilmFinish.swift,FilmFinish.metal,FilmStyleLibrary.swift,STYLE-PERMISSION.txt}`, `Processing/HaldLUT.swift`, `Storage/FilterPresetLibrary.swift`.
- 신규 UI: `LongExposureView.swift`, `CompositionControls.swift`, `FilmFinishControls.swift`, `FilmStylesView.swift`.
- 수정: CameraService/CameraModel/CameraView, SDRImage, MetalLUTRenderer/MetalLUTTextureRenderer, LiveLUTPreview/LivePreviewImageProcessor, LUTPhotoEditor/ImportedLUT, SavedEditStore, LUTEditorView/LiveLUTControls.
- 테스트: LongExposureStackTests, LongExposureArchiveTests, CompositionGuideTests, FilmFinishTests, FilmStyleLibraryTests와 기존 LUTPhotoEditorTests 호환 검증. 문서 04/05/06/07/08/11/12와 README 갱신.

## 5. 실행·테스트 결과

| 단위 | revision | CI | 결과 |
|---|---|---|---|
| 장노출 core | b03dc5b1110f49709ba84ea1e871f506f73de7dd | [39539398038](https://github.com/MetaParodica/PhotoP/actions/runs/39539398038) | SDK·Swift96·Python7 성공 |
| 캡처/archive/재처리 | 29ce647a03492e69b454fb9544fecb8812504463 | [39539994340](https://github.com/MetaParodica/PhotoP/actions/runs/39539994340) | SDK·Swift101·Python7 성공 |
| 구도·Vision | 995dac8e854f80ad55722bd38c583529ceeda730 | [39540831878](https://github.com/MetaParodica/PhotoP/actions/runs/39540831878) | SDK·Swift106·Python7 성공 |
| 마감·레시피 | 589961ae989e83861bb0e7e397663f02003bb832 | [39541479961](https://github.com/MetaParodica/PhotoP/actions/runs/39541479961) | SDK·Swift112·Python7 성공 |
| 스타일·preset·Hald | ca05d5cdc9b50108f7f5095d5ebdbaadbd4b1a25 | [39542442343](https://github.com/MetaParodica/PhotoP/actions/runs/39542442343) | SDK·Swift120·Python7 성공, skip 없음 |

Linux에서 소스 편집·Python7을 실행했다. unsigned iPhone SDK build와 XCTest는 GitHub macOS-15 runner에서 수행했다. 실제 iPhone 촬영은 수행하지 않았다. 구도 단계의 CVPixelBuffer concurrency 경고와 마감 테스트 fixture의 compiler time limit을 수정하고 다시 통과했다. 기존 AppIntents·portrait orientation 경고 외 새 경고는 없다.

## 6. 확인된 제약·미완료

장노출은 **1280px·최대2fps 처리 SDR 샘플**이며 센서 연속 적분/고해상도 RAW 합성이 아니다. 프레임 간 라이트 트레일 누락 가능, alignment는 ±8px 정수 translation만 지원한다. disk archive 128MiB에 도달하면 일찍 종료하며 실제 시간/이유를 기록한다. 회전/원근·일반 handheld 보장·median/motion-aware·앱 재시작 archive browser·crash orphan recovery는 미구현이다.

구도는 portrait-only, 목표 도식과 검출을 구분하며 rectangle을 건축물로 단정하지 않는다. 실제 검출 정확도·latency·다양한 인물/장면 품질은 미검증이다. 소실점·semantic scene segmentation·자동 perspective correction은 미구현이다.

자체 스타일 **12종**은 브랜드 실측 재현이 아니다. 100+ 검수 스타일과 외부 LUT 재배포 승인, 실제 사진의 미학·banding/halo 검수는 미완료다. 컬러 블리딩·물리 film-base 모델·전체 고급 grading 항목도 후속이다. 사진 편집은 SDR sRGB·12.6MP JPEG 한도, 미리보기는1024px다. Hald는 level2~8의 불투명 8bit RGB sRGB PNG로 제한한다.

RAW 현상·RAW bracket·HDR fusion·전체 갤러리·영상·Android는 미구현이다. 기존 ProRAW AUTO·RAW/live off 등의 실행 제한을 유지한다. 실제 EXIF·Photos·색상·FPS·메모리·배터리·발열·300초 안정성·접근성은 별도 기기 승인 대기다.

## 7. 다음 단계

다음 제품 개발은 Phase 7 전문 영상이다. 착수 시 supported resolution/FPS/codec 및 audio 권한·writer backpressure·원본 비굽기 color metadata 계약을 먼저 정의한다. 이번 요청 범위는 Phase 6까지이며 실기기 검증 항목은 05 문서에 유지한다.
