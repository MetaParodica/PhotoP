# Phase 4–6 구현 계약과 검증

이 문서는 초기 Phase4–6 revision의 기록이다. 후속 성능·해상도·1D/29종 룩 확장의 현재 범위는 [13](13-PERFORMANCE-CAPTURE-LOOKS.ko.md)을 따른다.

기준일: 2026-10-21 KST. 실제 iPhone 검증은 별도 대기하고 자동 검증 성공 후 다음 구현 단위로 진행한다. 아래 제한을 제품 표시에도 반영한다.

## Phase 4 장노출

- 실제 센서 노출은 기존 PRO의 activeFormat 셔터 범위를 따른다. 새 모드는 1~300초 동안 최대 2fps의 **처리된 SDR 프레임**을 누적하는 계산 합성이다. 센서를 300초 동안 연속 노출한다고 표시하지 않는다.
- native NV12 output, 검증된 입력 프로파일→Core Image sRGB→최대 긴 변 1280px RGBA. 고해상도 RAW 합성·연속 광자 적분은 미구현이다. 샘플 간 이동은 기록되지 않으므로 연속 라이트 트레일에 틈이 생길 수 있다.
- 평균은 sRGB 역전달 후 선형광에서 누적 평균을 계산해 다시 sRGB로 출력한다. Lighten은 더 밝은 선형 휘도의 RGB 픽셀 전체를 선택한다. 채널별 maximum projection과 다르다. 프레임 수에 비례해 RAM을 늘리지 않는다.
- 선택 정렬은 첫 프레임 기준 ±8 원본 픽셀의 정수 평행이동이다. 낮은 texture·모호한 match·큰 잔차는 거부한다. 회전/원근·rolling shutter·별 정렬·일반 handheld 안정화로 표시하지 않는다. 이동된 가장자리는 픽셀별 유효 횟수로 나누어 어두워지지 않게 한다. 노이즈 감소는 평균의 효과이며 sigma clipping·motion segmentation·median은 후속이다.
- 캡처/설정/LUT output과 동시에 실행하지 않는다. background·중단은 취소하며, 위험 발열은 실패·정리, serious thermal state는 샘플 간격을 늘린다. 발열을 측정했다는 뜻은 아니다.
- 손실 없는 sampled PNG를 디스크에 128MiB까지 보관한다. 예산 도달 시 유효 2장 이상이면 일찍 종료해 실제 elapsed·종료 원인을 recipe에 기록한다. 시작 시 최소 여유 공간을 검사하며 쓰기 실패는 pending job을 제거한다. 완료 bundle은 result.jpg·recipe.json·PNG frames다. 취소는 부분 파일을 제거한다. 강제 종료 직전 orphan 복구는 별도 품질 과제다.
- 재처리는 PNG/hash를 검사해 한 장씩 읽고, 새 blend/정렬로 새 bundle을 만든다. 기존 bundle은 보존한다. recipe·프레임 경로/크기·hash·취소를 검사한다. 현재 UI는 마지막 합성의 재처리를 제공하며 앱 재시작 후 합성 기록 browser는 후속이다.

### 실행 증거

| 단위 | revision | CI | 결과 |
|---|---|---|---|
| 선형 평균/Lighten·정렬 | b03dc5b1110f49709ba84ea1e871f506f73de7dd | [39539398038](https://github.com/MetaParodica/PhotoP/actions/runs/39539398038) | SDK build·Swift 96·Python 7 성공 |
| 촬영/취소/archive/재처리 | 29ce647a03492e69b454fb9544fecb8812504463 | [39539994340](https://github.com/MetaParodica/PhotoP/actions/runs/39539994340) | SDK build·Swift 101·Python 7 성공 |

독립 fixture로 선형광 평균(흑백 평균 약188), RGB 전체 선택, 고정 RAM 배열, 알려진 translation/valid edge, 모호한 정렬 거부, PNG 재처리 JPEG 재현, 변조 거부·pending 정리·중복 취소/완료를 검사했다. 실제 camera frame 수·화각·방향·수동 노출 유지·배터리·발열·peak memory·300초 soak는 미검증이다.

## Phase 5 촬영 구도

- 독립 수동 구도: 삼분할·황금비·중앙 대칭·대각선·황금 삼각형·황금 나선·수평선 비율·네거티브 스페이스·전경/중경/후경 기준.
- 독립 작성 도식 포즈: 전신·반신·클로즈업·2인·단체·앉기·걷기·측면·배경 활용. 노란 목표 도식과 청록 Vision 검출을 구별한다. 실제 인체 비율 모델이나 전문 포즈의 정답으로 표시하지 않는다.
- Apple Vision: 일반 attention saliency, 인물 body-pose joints, 건축 rectangle edges, 풍경 horizon angle. 건축물 의미 분류·소실점·거리 추정·자동 perspective correction·산/하늘 분할은 미구현이다. 단순 rectangle을 건물로 단정하지 않는다.
- confidence 필터, 최대4관측, 1개 작업·최대2Hz, 모드/세대 변경 시 이전 결과 거부. 1.5초 지난 결과 숨김. 이미지 서버 전송 없음.
- 입력은 이미 portrait 회전·전면 mirror를 적용한 CVPixelBuffer다. Vision bottom-left 좌표를 현재 live image의 aspect-fit rect로 변환하고 mirror를 두 번 적용하지 않는다. 현재 iPhone portrait만 지원한다. 가로 UI는 미지원이며 좌표 helper의 종횡비 수학만 자동 검증한다.
- AI는 강제 점수나 촬영 제한이 없는 제안이다. 광학/센서 수준 자동 수평 보정은 제공하지 않는다. AI output과 원본 촬영은 별도이며 guide는 원본에 굽지 않는다.

### 실행 증거

[CI 39540573331](https://github.com/MetaParodica/PhotoP/actions/runs/39540573331): Swift106·Python7·SDK 성공. CVPixelBuffer queue 캡처 경고를 발견하고 immutable retained frame 소유권을 명시했다. 수정 revision `995dac8e854f80ad55722bd38c583529ceeda730`, [CI 39540831878](https://github.com/MetaParodica/PhotoP/actions/runs/39540831878) 성공, 새 concurrency 경고 없음. 원점/mirror·letterbox/종횡비·stale/future·포즈 좌표/인원·인물 여백 규칙·lifecycle 거부를 검사했다. Vision 모델의 실제 검출 정확도·다양한 피부/자세/건물·지연은 미검증이다.

## 오픈소스 실제 코드 검토

| 프로젝트·revision | 읽은 파일·관찰 | 라이선스·선택 |
|---|---|---|
| [Starlapse](https://github.com/fortunto2/starlapse/tree/53ff9060eee59b1f06d4ec9a707e4eb4c91d4c00) | StackKit/StackCombiner.swift: online mean/variance·NaN valid edge·lighten, ColorDecode.swift: transfer curve 구분 | LICENSE MIT 원문 확인. 선형광·유효 weight·bounded state 원칙 비교. 자체 RGB combiner와 제한적 translation을 독립 작성. 코드 복사·패키지 의존 없음 |
| [PoseGuide](https://github.com/mergeos-bounties/PoseGuide/tree/acd3e075240330d8ab6bbb3615a7a848b3b88072) | data/poses/README.md: normalized skeleton·camera cue, synthetic scaffold임을 명시 | repo MIT metadata, pose README 확인. 실제 사람으로 검증된 자료로 간주하지 않고 자체 도식 작성. 자산 복사 없음 |
| [hald-clut](https://github.com/cedeber/hald-clut/tree/3b3180f82d4dcea1e6e8c5648473539a910d7f49) | README와 tree: RawTherapee/PictureFX/Fuji/Apple/Pixelmator 출처 혼합 | repo GPL-3.0 metadata가 개별 상표/asset 권리 전부를 보증하지 않음. 개별 권리 검토 전 bundle 미채택. LUT 파일 다운로드/복사 없음 |

공식 API: [Vision body pose](https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images), [rectangle](https://developer.apple.com/documentation/vision/vndetectrectanglesrequest), [horizon](https://developer.apple.com/documentation/vision/vndetecthorizonrequest), [saliency](https://developer.apple.com/documentation/vision/vngenerateattentionbasedsaliencyimagerequest). 모델 가중치를 별도로 재배포하지 않는다.

## Phase 6 제한 개발 범위·자동 검증 완료

자체 sRGB 프로파일·분류/검색·미리보기·프리셋과 독립 필름 마감 효과를 추가했다. 공식 기술 LUT와 비공식 film emulation을 혼동하지 않는다. 외부 LUT의 권리가 불명확하면 commercial bundle에 넣지 않는다. 100개는 품질 평가를 거쳐 확장하는 목표이며 이번 확보 수량으로 표시하지 않는다.

### 구현 계약

- `FilmFinish.swift/.metal`: fade·vignette·bloom·red halation 각각 0~100%, LUT/입자와 독립. 사진 buffer/live texture가 같은 GPU 함수와 normalized tap radius를 쓴다. alpha 보존·전체 zero bypass. 광학/유제 측정 모델이 아닌 SDR 창작 효과다. 서로 다른 해상도의 공간 샘플·JPEG는 실제 사진으로 별도 비교한다.
- 레시피 v3에 finish·선택 provenance. v1은 grain/finish 없음, v2는 grain과 neutral finish, v3는 grain/finish 필수. 재열기에서 범위·hash·프로파일을 확인한다.
- 자체 **12종**: Amber Portrait, Quiet Documentary, Copper Night, Pastel Day, Forest Slide, Silver Mono, Graphite, Soft Neutral, Golden Travel, Cool Architecture, Dream Warm, Deep Cinema. 독립 파라미터 수식→17³ red-fastest cube를 런타임 생성한다. 실측 필름·타사 공식 LUT라고 표시하지 않는다.
- 검색·카테고리·합성 chart preview. 자체 author/source ID/license/credit/sRGB input/output/hash/intensity 범위와 재배포 허가를 기록한다. 권리는 `Film/STYLE-PERMISSION.txt`의 자체 profile data 범위에만 적용한다. 외부 LUT·repo 전체에 새 허가를 적용하지 않는다.
- 전체 룩 preset은 cube+JSON을 UUID folder에 원자적으로 저장한다. 강도·grain amount/seed·finish·출처를 함께 복원하고 hash/profile/version/path를 검사한다. 동일 cube의 다른 설정은 별도 preset이다. 기존 LUT favorites는 LUT만 저장한다. 사용자 가져오기/프리셋은 로컬 문서이며 배포 자산으로 자동 포함되지 않는다.
- Hald: PNG 8MiB, 단일 정사각형 side=level³, level2...8, dimension=level², 8bit RGB/sRGB·orientation1·불투명만 지원. ICC가 다른 gamut/Log/HDR를 추측 변환하지 않는다. ImageIO raster→red-fastest cube, 원본 PNG SHA256를 cube comment에 남긴다. 외부 가져오기에는 sRGB 입출력 확인이 필요하다.
- 외부 LUT 바이너리 번들 **0개**, 자체 스타일 **12종**. 공식 제공 사실과 app redistribution은 구분하며 상세는 12 문서다. 100+개 검수·컬러 블리딩·실측 film base/halation·전체 색보정 항목은 미완료다.

마감 효과 revision `589961ae989e83861bb0e7e397663f02003bb832`, [CI 39541479961](https://github.com/MetaParodica/PhotoP/actions/runs/39541479961): unsigned SDK build·Swift112·Python7 성공. 첫 테스트의 복잡한 배열 fixture가 compiler time limit에 걸려 명시적인 loop로 수정했다. 새 concurrency 경고는 없고 AppIntents/portrait orientation의 기존 경고만 남는다.

스타일/preset/Hald revision `ca05d5cdc9b50108f7f5095d5ebdbaadbd4b1a25`, [CI 39542442343](https://github.com/MetaParodica/PhotoP/actions/runs/39542442343): unsigned iPhone SDK build·Swift120·Python7 성공, skip0. 자체12종 생성 재현·unique hash·gray monotonicity·chart 수치/mono·검색·전체 룩 재시작/변조/잘못된설정·version/path·Hald identity/swapped order·rotation/alpha/bounds를 검증했다. 수치 검증은 실제 필름 재현/미학 품질 승인과 구분한다.
