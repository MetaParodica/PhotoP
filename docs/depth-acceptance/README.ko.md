# 심도 인수 증거

이 폴더의 빈 manifest는 **인수 대기**를 뜻한다. CI의 `--validate-only`는 구조·hash 검사만 한다. 배포 품질 게이트는 아래 명령의 exit0일 때만 통과한다. exit2는 증거/목표 미달, exit1은 잘못된 입력이다.

```sh
python3 scripts/check_depth_acceptance.py /동의받은/평가폴더/manifest.json
```

실제 사진은 기본적으로 저장소에 넣지 않는다. 이 manifest를 별도 평가 폴더에 복사하고 상대 경로와 SHA256을 기록한다. symlink·상위 경로·hash 불일치는 거부한다. 사진/trace를 외부 서버로 전송하지 않는다.

`scenes`는100장 이상으로, 각 항목에 고유 `id`, `kind: "real-capture"`, `consented: true`, `categories`, `original`/`photop`/`competitor`/`review`를 넣는다. 마지막 네 항목은 `{ "path": "상대경로", "sha256": "64자리" }`이다. 범주는 backlight/night/hair/glasses/hands/pets/glass/plants/foreground/multiple-subjects/motion을 포함한다. 비교 보고서에는 동일 입력 비교와 앱별 촬영 비교를 구분하고 앱 버전·촬영 조건·동의를 기록한다.

`deviceRuns`는 최소 지원·중간급·LiDAR Pro 실기기 각각의 `tier: "minimum-supported" | "midrange" | "lidar-pro"`, `physicalDevice: true`, `model`, `os`, `trace`를 넣는다. trace는 위와 같은 path/hash이며 JSON 본문에 `durationSeconds`(최소600), `previewLatencyMilliseconds`(원시 지연 샘플300개 이상)를 담는다. p95는 이 원시 파일로부터 계산한다.150ms는 계획의 초기 목표이며 실측 결과를 뜻하지 않는다. 기기별 별도 보고서에 peak memory·프레임률·전력·열 상태·48MP 처리 시간·실패율을 포함한다. `thermalFallbackVerified`, `originalIntegrityVerified`, `cancelRecoveryVerified`는 각 시나리오를 실제 확인한 후에만 true로 기록한다.

`blindReviews`에는 독립 평가자3명 이상의 `reviewer` 익명ID, `blinded: true`, `sceneIDs`, 원본 `ballot` path/hash를 넣는다. 앱 이름을 가린 무작위 순서로 경계 누출·머리카락/얼굴 손상·가림/점광원·시간 잔상을 평가한다. 점수 하나로 업계 최고를 주장하지 않는다. `qualityApproval`과 `legalReview`는 검토 보고서 path/hash 및 `accepted: true`를 요구한다. 현재 모델/LUT 권리 기록이 최종 심도 제품 전체의 법적 검토를 대신하지 않는다.

게이트는 증거의 존재·무결성·선언된 인수 조건을 확인한다. 동의의 진위나 주관 화질을 자동 판정하지 않으며 사람의 검토 책임을 대체하지 않는다. iOS17~27 SDK/실기기 호환성은 별도 빌드/기기 매트릭스로 인수한다.

## 2026-11-20 영상 심도 확장

`python3 scripts/check_video_depth_evidence.py docs/depth-acceptance/video-manifest.json`은10종 실제 영상(정지/걷기/빠른 피사체/팬/전후 이동/전경 진입/가림 복귀/교차/역광 모발/야간 점광원)을 구분한다. 현재 실제 영상0건이므로 exit2 미인수다. 기존 사진100장 gate도 별도로 유지한다.

각 scenes 항목은 `id`, `kind: real-capture`, `consented`, `categories`, `humanAccepted`와 original/baseline/candidate/blindReview/measurements의 `{path,sha256}`를 포함한다. measurements JSON은 최소30개의 증가하는 `ptsSeconds`, `depthJitterBefore/After`(동일 scale 정렬/측정 ROI와 방식은 blindReview에 명시), `boundaryJitterPixels`, `targetLossFrames`, `fallbackFrames` 및 `ptsPreserved/audioPreserved/orientationPreserved/originalHashPreserved`를 포함한다. depth jitter는 등록된 동일 ROI의 값으로 비교하고 새로 드러난 영역을 별도로 표시한다. 사람 평가는 halo·경계/초점 이탈·잔상과 fallback 적절성을 확인한다. gate는 수치/증거의 무결성과 coverage를 확인할 뿐 미학적 품질을 판정하지 않는다. 합성 테스트를 real-capture로 바꾸거나 검증 자료를 임의 생성하지 않는다.
