# iOS18·저장 잠금·노출 융합·스코프 구현

기준 main `d977858`, 작업 `codex/ios18-bracket-scopes-20261118`. 2026-11-18 사용자 결정을 따른다.
HDR/게인맵·Log 영상·C2PA·AI 생성 표기 변경은 포함하지 않는다.

## T00·V07

T00 `4bc0a24`: 최소18.0, 셔터음 지원 검사는 유지하고 OS18 분기만 제거했다.
전체 [CI44228552924](https://github.com/MetaParodica/PhotoP/actions/runs/44228552924)는 성공했다. macos-15의 후속 실행에서 Simulator26.2를 확인했다. V07 `f29653a` 전체 CI44228983998은 Simulator 빌드 exit65로 실패했다.
`805ee0b`에서 UI 테스트 UIKit 의존과 빌드 오류 annotation을 추가했고 전체 CI44229876030을 시작했다.
V07은 유효한 저장 사진 fixture와 실제 편집기의 저장/취소 경로를 사용한다.
저장 직전 barrier와 해제 버튼은 DEBUG Simulator 검토 모드에서만 존재한다.
전체 CI 성공과 실기기 저장 안정성은 구분한다.

## F1 — SDR 노출 융합

- 기존3장 브래킷 보존 후 별도 JPEG+레시피를 FusionResults UUID 번들에 원자적으로 게시한다.
- 정렬은 최대192px SDR 휘도의 평행이동 탐색이다. log2 휘도 차이의 평균을 제거하여 노출 차이를 보정한다.
- 탐색6px 경계, 서로 다른 정렬 후보의 잔차 차이0.01 미만(반복 무늬·모호한 정렬), RMS 잔차0.18 초과, 차이0.45를 넘는 표본3.5% 초과, 유효 표본35% 미만·윤곽 부족을 거부한다.
- 허용치와 contrast0.3/saturation0.2/well-exposedness1.0 지수는 ExposureFusionPolicy/Weights 값 타입이다.
- Metal은 대비·채도·적정노출 가중치를3×3으로 평활화해 encoded-sRGB에서 합산한다. 전체 Laplacian pyramid Mertens 구현은 아니다.
- 같은 방향/크기의 JPEG·HEIC 최대12.6MP만 처리한다. 더 큰 입력은 자동 축소하지 않고 거부하며 원본3장을 보존한다.
- 정렬 후 겹치지 않는 테두리는 사용할 수 있는 원본만 합산한다. 중간 프레임은 항상 존재한다.
- LUT는 융합 JPEG에 굽지 않는다. 기존 개별 원본의 룩 결과는 별도로 유지한다. UI에서 융합·룩 결과를 구분한다.
- 처리 전후 원본3개 SHA-256을 비교하며 원본 파일을 쓰지 않는다. 레시피에 원본 hash·EV·정렬·가중치·SDR 계약을 남긴다.
- 실패 이유를 촬영 메시지와 리뷰에 표시한다. 실패 시에도 원본·기존 개별 결과는 남긴다.

Linux 정책5개를 포함한 portable123개 통과는 iOS/Metal 성공이 아니다.
새 iOS 통합2개는 GPU 합산·별도 JPEG·원본 bytes/hash·게인맵 없음·거부/취소를 확인하도록 작성했다.
전체 CI와 실제 역광·손떨림·회전·국소 움직임 약30세트,12MP 메모리/지연 측정은 대기다.
현재 정렬·고스트 판단은 휴리스틱이다.192px 분석은 초기 이동만 추정한다. 원본 픽셀의 최대32×32 표본 격자에서 초기 이동 주변을 다시 탐색하여 정수 픽셀 단위로 보정하고 잔차/고스트/후보 분리도를 재검사한다. 서브픽셀·회전 정렬과 실제 미세 손떨림 선명도 인수는 미완료다. 회전·롤링셔터·작은 국소 움직임·포화 영역을 완전히 검출한다고 주장하지 않는다.
새 외부 코드·이미지·모델·라이브러리를 가져오지 않았다.

## F2 — SDR 프리뷰 스코프

- Monitoring.metal/MetalPreviewMonitor를 확장했다. LUT 적용 전 원본 SDR 프리뷰의 휘도 파형·RGB 퍼레이드·Cb/Cr 벡터스코프와 False color다. 사진·영상 원본에 표시를 굽지 않는다.
- 파형/퍼레이드는64열×64밝기 구간, 벡터스코프는64×64 Cb/Cr다. 기존 최대256px 격자·4Hz 예산과 단일 in-flight 소유권을 재사용한다. GPU 완료 후 최대81KiB 집계값만 복사하고 전체 프리뷰 픽셀을 새로 읽지 않는다.
- False color는 매 프레임 원본 SDR encoded 휘도에7구간 팔레트를 적용하고 Zebra/피킹보다 우선한다. UI에 구간 범례·SDR 프리뷰 분석·LUT 적용 전 계약을 표시한다. 센서 RAW/HDR/Log·정확한 IRE 계측이라고 주장하지 않는다.
- 각 선택만으로 프리뷰 수요가 유지된다. 통계는 예산 주기에만 생성하고 False color는 계속 표시하며, 무표본·투명 픽셀을 가짜 통계로 채우지 않는다.
- 외부 소스는 읽거나 복사하지 않았다.31 문서의 OpenPocketCine 구조 조사만 참고하고 자체 구현했다.
- Linux portable126개(새 스코프 정책3개 포함), Python31개와 모델/LUT 자산 검사를 확인한다. 추가 iOS GPU3개는 공간 열/채널·중립/원색 크로마·LUT 전 입력·False color·투명 픽셀/통계 예산을 검사한다. UI1개는 SDR 문구와4선택을 확인하고 Simulator에서 가짜 통계/카메라를 만들지 않는다.
- 새 전체 CI·실제1024px 프리뷰 p95·peak memory·온도·색/가독성·영상 동시 출력은 대기다.

## 단계별 CI 추적

| 소스 | 전체 CI | 확인 결과 |
| --- | --- | --- |
| T00 `4bc0a24` | 44228552924 | 성공; iOS18 설정의 전체 CI 완료 기준 충족 |
| V07 `f29653a` | 44228983998 | Simulator build-for-testing 실패 |
| 진단 `805ee0b` | 44229876030 | fixture 타입 검사 시간 초과; Simulator26.2 확인 |
| F1 `c150e81` | 44230231729 | iPhone 빌드 실패 |
| F2 `7f2e7f5` | 44230947442 | F1 휘도 생성식 타입 검사 시간 초과 |
| 타입 검사 수정 `f0ce456` | 44231101040 | Simulator 테스트 RGBA 배열 타입 추론 오류 |
| 요약·상태 정리 `067173e` | 44231466026 | Simulator 테스트의 RGBA 배열 타입 추론 오류 |

전체 CI 성공 전 V07/F1/F2를 완료 처리하거나 main에 반영하지 않는다. 실기기 인수는 전 항목 미수행이다.
F12는 이번 우선순위 뒤의 선택 과제다. 공식 Apple API 문서 접근이 현재 proxy403이라 구현 전 API 확인을 수행하지 못했으며 구현을 보류한다. 위치 기본 활성화·거부 시 위치 없이 촬영 결정은 유지한다.

- 후속 검토에서 반복 무늬/완만한 경사가 낮은 잔차만으로 잘못 정렬되지 않도록 후보 간 분리도 정책과 회귀1개를 추가했다. 정책 전체도 융합 레시피에 보존한다. GPU fixture는 명확한2D 윤곽을 가진 합성 입력으로 바꿨다. 최신 Linux portable127개 통과이며 실제 촬영 인수와 다르다.

- `8b3cb40` 전체 CI44232322926은 진행 중이다. CI44231466026에서 확인한 False color 테스트의 혼합 배열 타입을 UInt8로 명시했다.

## F12 사전 확인 목록 — 구현 보류

공식 문서 본문을 확인하지 못했으므로 아래는 **확인할 API 후보**이며 채택/지원 판정이 아니다.

| 경로 | 공식 문서에서 확인할 후보 | 원본 불변 조건 |
| --- | --- | --- |
| 권한·상태 | CLLocationManager의 사용 중 권한 요청/상태·정확도·위치 유효기간 | 최초 촬영 전 요청, 거부/오류는 위치 없이 촬영, 기본 켜기/설정 끄기 |
| JPEG·HEIC | AVCapturePhotoSettings.metadata의 GPS 메타데이터 지원 | capturePhoto 요청 전에 촬영 시점 위치 전달; 저장 후 ImageIO 재인코딩 금지 |
| DNG | 동일 metadata의 RAW/ProRAW 지원과 fileDataRepresentation 생성 계약 | DNG 생성 단계 지원을 확인하기 전 태깅 지원을 표시하지 않음 |
| 영상 | AVCaptureMovieFileOutput.metadata/AVMetadataItem의 ISO6709 위치 | startRecording 전에 설정; 종료 후 AVAssetExportSession 등으로 원본 재작성 금지 |
| Photos | PHAssetChangeRequest/PHAssetCreationRequest.location와 addResource | 생성 트랜잭션에서 자산 위치 설정; 앱 원본 bytes 재작성 금지 |

관련 구현은 CameraService의 AVCapturePhotoCaptureDelegate/AVCaptureFileOutputRecordingDelegate와 PhotoStore이며, LONG·ARKit 경로의 생성 시점/지원 범위도 별도로 확인해야 한다. 후보 이름만으로 사진·DNG·영상 모두 GPS 태깅된다고 표시하지 않는다. 첫 촬영 대기/취소·권한 거부·오래된 위치·카메라 queue로의 Sendable 스냅샷 전달과 Photos 경로의 검증이 필요하다. 현재 위치 권한 요청·새 데이터 수집은 추가하지 않았다.

- 원본 픽셀 정밀 보정 정책2개를 포함한 Linux portable129개가 통과했다. 대형 Float 이미지3장을 추가로 만들지 않고 이미 확보한 Metal 입력 버퍼에서 읽는다. 레시피는 초기/원본 픽셀 정렬 결과를 모두 보존한다. GPU 통합은 무이동과 좌우 이동 fixture를 모두 검사한다. 이 보완의 새 iOS CI는 별도로 확인한다.

- `e7fdda0` 전체 CI44232594256은 iOS 단위350통과/1skip·LUT18통과·UI12통과/2실패다. 실패는 저장 잠금 UI 검사이며 원인 식별용 assertion 메시지와 로그 annotation을 추가했다. 전체 성공이나 main 반영으로 처리하지 않는다.
