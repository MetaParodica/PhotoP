# iOS18·저장 잠금·노출 융합·스코프 구현

기준 main `d977858`, 작업 `codex/ios18-bracket-scopes-20261118`. 2026-11-18 사용자 결정을 따른다.
검증 소스 **`cf9460505bd9211ba9afbfad974c6419fcc569db`**, 전체 [CI44235743796](https://github.com/MetaParodica/PhotoP/actions/runs/44235743796) **성공**.
HDR/게인맵·Log 영상·C2PA·AI 생성 결과 표기 변경은 포함하지 않는다.

## 현재 검증 결과

| 검사 | 확인 결과 |
| --- | --- |
| macos-15 / Simulator | iOS26.2. 최소18.0 검사 통과 |
| iPhone·Simulator | iOS SDK 빌드·테스트 빌드 성공 |
| iOS 앱 단위 | 353개 중352통과·1skip |
| LUT 전용 회귀 | 18개 통과(독일어 지역 설정) |
| UI 자동화 | 14개 통과, 실패/skip0 |
| 네이티브 단위 합계 | 371개 중370통과·1skip |
| 공통 로직 | portable129개. iOS 실행 결과와 별도 |
| Python·자산 | 31개 및 LUT·모델·실제 앱 번들 검사 통과 |
| 실제 iPhone | 촬영·화질·메모리·p95·열·영상 동시 출력 모두 미검증 |

T00·V07의 CI 완료 기준은 충족했다. F1·F2는 코드와 자동 회귀를 확인했으며 실제 장면/기기 인수 전 기능 전체 완료로 표기하지 않는다.

## T00·V07

T00 `4bc0a24` 전체 [CI44228552924](https://github.com/MetaParodica/PhotoP/actions/runs/44228552924)도 성공했다.
배포 타깃18.0과 문서를 갱신하고 셔터음의 OS18 분기2곳만 제거했다. 실제 장치의 지원 검사는 유지한다.
CI는 배포 타깃18.0과 가용 Simulator18.0 이상을 검사한다.

V07은 유효한 저장 사진 fixture와 실제 편집기의 저장/취소 경로를 사용한다.
저장 직전 barrier와 해제 버튼은 DEBUG Simulator 검토 모드에서만 존재한다.
저장 중 f값·전체 프로필 컨트롤·비교가 비활성인지 확인하고 물리 좌표 터치/드래그 뒤 값 불변을 검사한다.
실제 저장 완료·취소 뒤 다시 활성화되는 두 UI 테스트가 통과했다.
UIKit의 개별 세그먼트 enabled 플래그는 전체 컨트롤 상태와 달라, 전체 컨트롤과 실제 값 변화를 검사한다.
임시 로그 다운로드 진단 작업은 제거했고 일반 CI의 오류/집계 annotation은 유지했다.

## F1 — SDR 노출 융합

- 기존3장 브래킷을 보존한 뒤 별도 JPEG+레시피를 FusionResults UUID 번들에 원자적으로 게시한다.
- 최대192px SDR 휘도에서 초기 평행이동을 추정하고 log2 휘도 차이의 평균을 제거하여 노출 차이를 정규화한다.
- 원본 픽셀의 최대32×32 표본 격자에서 초기 이동 주변을 다시 탐색하여 정수 픽셀 단위로 보정한다. 대형 Float 이미지3장을 추가로 만들지 않고 Metal 입력 버퍼에서 읽는다.
- 초기/정밀 단계에서 모호한 후보(잔차 차이0.01 미만), 이동 탐색 경계, RMS0.18 초과, 차이0.45를 넘는 표본3.5% 초과, 유효 표본35% 미만·윤곽 부족을 거부한다.
- 허용치와 contrast0.3/saturation0.2/well-exposedness1.0 지수는 ExposureFusionPolicy/Weights 값 타입이며 레시피에 보존한다.
- Metal은 대비·채도·적정노출 가중치를3×3으로 평활화해 encoded-sRGB에서 합산한다. 전체 Laplacian pyramid Mertens 구현은 아니다.
- 같은 방향/크기의 JPEG·HEIC 최대12.6MP만 처리한다. 초과 입력을 자동 축소하지 않고 거부하며 원본3장을 보존한다.
- 겹치지 않는 테두리는 사용할 수 있는 프레임만 합산한다. 중간 프레임은 항상 존재한다.
- LUT는 융합 JPEG에 굽지 않는다. 기존 개별 원본의 룩 결과는 별도로 유지하고 UI에서 구분한다.
- 전후 원본3개의 SHA-256을 비교한다. 원본을 쓰지 않으며 초기/정밀 이동·원본 hash·EV·가중치·정책·SDR 계약을 기록한다.
- 실패 이유를 촬영 메시지와 리뷰에 표시한다. 원본·기존 개별 결과는 남긴다.

정책8개는 노출 정규화·이동·모호성·고스트·비정상 좌표·가중치/직렬화를 검사한다.
iOS 통합2개는 무이동/좌우 이동 GPU 합산, 별도 JPEG·레시피, 원본 bytes/hash 불변, 게인맵 없음, 거부·취소를 검사한다.
정렬·고스트 판정은 잠정 휴리스틱이다. 서브픽셀·회전·롤링셔터·작은 국소 움직임·포화 영역을 완전히 처리/검출한다고 주장하지 않는다.
실제 역광·손떨림·움직임 약30세트,12MP 메모리/지연·선명도 인수는 대기다.

## F2 — SDR 프리뷰 스코프

- Monitoring.metal/MetalPreviewMonitor를 확장했다. LUT 적용 전 SDR 입력의 휘도 파형·RGB 퍼레이드·Cb/Cr 벡터스코프와 False color다. 사진·영상 원본에 굽지 않는다.
- 파형/퍼레이드는64열×64밝기 구간, 벡터스코프는64×64다. 기존 최대256px 격자·4Hz 예산과 단일 in-flight 소유권을 재사용한다.
- GPU 완료 후 최대81KiB 집계만 복사한다. 전체 프리뷰 픽셀을 새로 읽지 않는다.
- False color는 매 프레임 원본 SDR encoded 휘도에7구간 팔레트를 적용하고 Zebra/피킹보다 우선한다.
- UI에 범례·**SDR 프리뷰 분석 · LUT 적용 전** 계약을 유지한다. 센서 RAW/HDR/Log·정확한 IRE 계측이라고 주장하지 않는다.
- 각 선택만으로 프리뷰 수요가 유지된다. 통계 예산과 매 프레임 False color를 분리하며 무표본·투명 픽셀을 가짜 통계로 채우지 않는다.
- OpenPocketCine은31 문서의 구조 조사만 참고했고 외부 소스는 복사하지 않았다. 새 라이브러리·모델·이미지·폰트·오디오·통신을 추가하지 않았다.

정책3개·iOS GPU3개·UI1개가 공간 열/채널·크로마·LUT 전 입력·False color·통계 예산·SDR 문구와4선택을 검사한다.
실제1024px 프리뷰 p95·peak memory·온도·색/가독성·영상 동시 출력 인수는 대기다.

## 단계별 CI 추적

| 소스 | 전체 CI | 확인 결과 |
| --- | --- | --- |
| T00 `4bc0a24` | 44228552924 | 성공 |
| V07 `f29653a` | 44228983998 | Simulator 테스트 빌드 실패 |
| 진단 `805ee0b` | 44229876030 | fixture 타입 검사 시간 초과; Simulator26.2 확인 |
| F1 `c150e81` | 44230231729 | iPhone 빌드 실패 |
| F2 `7f2e7f5` | 44230947442 | 휘도 생성식 타입 검사 시간 초과 |
| 식 분리 `f0ce456` | 44231101040 | 테스트 RGBA 배열 타입 추론 오류 |
| 요약 `067173e` | 44231466026 | 같은 테스트 배열 오류 |
| UInt8 수정 `e7fdda0` | 44232594256 | iOS 단위350통과/1skip·LUT18통과·UI12통과/2실패 |
| 원본 픽셀 보정 `eb5ea75` | 44235017518 | iOS 단위352통과/1skip·LUT18통과·UI12통과/2실패 |
| 잠금 검사 수정 `cf94605` | **44235743796** | **전체 성공; 단위352+18통과/1skip·UI14통과** |

전체 성공 후 main 반영 절차를 진행한다. 실기기 인수는 전 항목 미수행이다.
상세 실패·수정/진단 이력은08 문서46~53절에 보존한다. 원격 정리 후보3개는 삭제하지 않았다.

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

