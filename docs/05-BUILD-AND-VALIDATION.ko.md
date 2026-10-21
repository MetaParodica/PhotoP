# F. 빌드·테스트·실기기 검증 절차

## 환경과 빌드

현재 작업 환경은 Linux이며 소스 편집과 Python 테스트를 수행할 수 있다. Xcode/Swift iOS SDK는 없어 iOS 빌드와 XCTest는 GitHub macOS CI에서 실행한다. 로컬에서 iOS 코드를 실행했다고 주장하지 않는다. GitHub macOS CI는 별도의 빌드·모델 테스트 증거이며 실기기 카메라 검증을 대체하지 않는다. 결과는 구현 보고서와 PR checks에서 확인한다.

Mac에는 iOS 17 이상 SDK를 제공하는 Xcode와 XcodeGen이 필요하다. 최신 Xcode의 Swift compiler에서 Swift 5 language mode를 쓴다. XcodeGen 버전은 초기 CI 설치 결과를 기준으로 기록하고, 반복 가능한 릴리스 파이프라인에서 고정한다.

```sh
git clone https://github.com/MetaParodica/PhotoP.git
cd PhotoP
git switch codex/ios-camera-foundation
brew install xcodegen
cd ios
xcodegen generate
xcodebuild -project PhotoP.xcodeproj -scheme PhotoP \
  -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO build
open PhotoP.xcodeproj
```

실제 설치는 Xcode에서 본인 Team, 고유 bundle ID, 실기기 destination을 선택하고 Run한다. 개발자 모드·신뢰 설정은 기기 지침을 따른다. 서명 인증서나 토큰을 저장소에 넣지 않는다. 비서명 build 성공과 설치·촬영 성공을 구별한다.

앱은 현재 portrait-only다. front preview는 mirror, 저장 사진은 non-mirror 정책이다. 사진과 grid의 aspect/letterboxing이 기기마다 맞는지 확인한다. iPhone 이외의 기기 지원은 아직 선언하지 않는다.

## 자동 검증

```sh
python3 -m unittest discover -s scripts -p 'test_*.py' -v
python3 scripts/check_lut_bundle.py
```

Python 7개 테스트는 정상 asset, 미등록 파일, 불명 재배포권, research-only 상용 포함, hash 변조, 경로 이탈, 입력 프로파일 누락을 검사한다. 빈 LUT manifest가 통과해도 LUT 엔진을 구현했다는 뜻은 아니다.

Phase 3 기준 Swift XCTest 90개는 수동 설정·콜백 집계·촬영 정책, 포맷/원본 보존, 터치/잠금 정책, .cube 파서·CPU 보간, Metal CPU/GPU 비교, SDR 방향/ICC/인코딩, 비파괴 export·recipe/hash·실패 정리와 파일/해상도 경계를 검사한다. live texture/사진/CPU 비교, YUV full/video range 색변환·방향·letterbox, in-flight 세대·늦은 알림, 정지 카메라 거부와 LUT 즐겨찾기의 재시작/중복/변조/프로파일/경로/저장 실패도 포함한다. Metal 비교와 통합 export는 Simulator GPU에서 skip 없이 통과했다. 단계별 revision과 CI 근거는 [검증 기록](08-STEP-VALIDATION.ko.md)을 따른다.

`.github/workflows/ios.yml`은 XcodeGen 생성 → unsigned iPhone SDK build → iPhone Simulator XCTest → Python 자산 검사 순서로 실행한다. Simulator의 성공은 실제 카메라 촬영 성공 기준으로 쓰지 않는다.

## 실기기 매트릭스

실제 확보 기기를 기록하고 기종을 추정하지 않는다. 최소 조합: ① 최소 OS의 지원 iPhone ② 최신 OS의 비Pro iPhone ③ 최신 OS의 RAW/ProRAW 지원 Pro iPhone. 카메라 수·렌즈·ProRAW 지원 여부를 API로 기록한다. 하나의 기기로 모든 모델을 검증했다고 처리하지 않는다.

| ID | 절차 | 기대 결과 / 기록할 증거 |
| --- | --- | --- |
| CAM-01 | 최초 실행에서 카메라 허용·거부 각각 수행 | 허용 시 프리뷰; 거부 시 명확한 설명, shutter 비활성; Settings 허용 후 재시도 |
| CAM-02 | 후면 wide·ultrawide·tele와 전면 중 존재하는 것만 순환 | 물리 lensID·capabilities 갱신; 화면/저장 방향·mirror 정책 일치 |
| CAM-03 | 10장 연속 촬영·빠른 중복 탭 | 1회 in-flight, 선택한 HEIF/JPEG decode 가능, 원본 수·Photos 수 대조 |
| CAM-04 | ISO·셔터 최소/중간/최대에서 설정 완료 대기 후 촬영 | 요청값·장치 현재값·ImageIO EXIF ISO/ExposureTime 비교. custom/locked .speed와 AUTO .quality 확인; 양자화·settling·화질 차이 평가 |
| CAM-05 | AUTO EV -/0/+ 촬영 | 실제 밝기·bias metadata·노출 변화 확인. full manual에 EV가 적용된다고 표시하지 않음 |
| CAM-06 | 수동 focus / AUTO 복귀, WB warm/cool/Tint | 카메라 동작·초점/색 변화 확인; 미지원 controls 비활성. Kelvin 정확도는 광원 기준 별도 측정 |
| CAM-07 | 설정 변경 중·촬영 전/중 홈/잠금/전화·장치 오류 | pending 설정/사진은 성공 또는 명시 실패; 이전 콜백 무시·복귀 재시작·타임아웃 후 수동 재시도. 배경에서 readout timer 정지 |
| CAM-08 | Photos 접근 거부·다시 허용 | 앱 원본 URL 유지, ShareLink로 파일 보냄, 재시도 후 성공 표시 |
| CAM-09 | 저장 공간 부족 조건 | 원본/Photos 실패 원인 표시, 성공 거짓 표시 없음; 앱 원본 쓰기 실패 복구 정책 확인 |
| CAM-10 | 재시작·앱 제거에 대한 데이터 정책 검토 | 원본 디스크 보관 확인; 마지막 원본 UI 복원·전체 갤러리는 아직 미구현 |
| PERF-01 | 10분 프리뷰·렌즈/PRO 반복 변경 | FPS·CPU/GPU·resident memory·thermal state·배터리 구간 기록; 초기 목표 60FPS 달성 여부 확인 |
| UI-01 | 작은 화면·Dynamic Type·VoiceOver·다크 UI | shutter·설명·저장 재시도 접근 가능; 큰 글씨 clipping과 화면 overflow 수정 |

EXIF 추출은 Mac의 ImageIO 또는 승인된 도구를 사용한다. 원본 SHA-256은 앱 저장 파일과 내보낸 원본 사이에서 비교한다. Photos가 표시용 thumbnail/변환본을 제공한 경우 original resource와 구분한다. 사용자 사진이나 EXIF 위치를 CI 로그에 올리지 않는다.

## 현재값·완료 대기 추가 확인

화면의 현재값은 4Hz 장치 readout이며 최종 사진 EXIF가 아니다. 수동 WB의 Kelvin/Tint는 장치 게인으로부터 환산한 추정값이다. 초점 0~1은 실제 거리(m)가 아니다. AUTO 모드에서 설정 콜백이 도착한 뒤에도 AE/AF/AWB 수렴이 계속될 수 있다.

자동 테스트는 카메라 정책 로직과 GPU·ImageIO 처리/파일 저장을 검증한다. 실제 AVFoundation 콜백 발생·장치값 정확도·timeout 복구·발열·화면 배치는 실기기 검증이 필요하다.

## 후속 처리 품질 gate

- LUT: identity, domain, nonfinite·malformed·oversized import, 강도 0/1, CPU double vs GPU, profile mismatch, HDR→SDR, export ICC.
- 합성: 고정 noisy frame의 mean 수치·분산 감소, translation/rotation 정답, Lighten 색 선택 정책, valid-edge mask, ghost/과노출, cancel·disk·thermal.
- 가이드: off-device 전송 없음, 정규화 좌표→view mapping, 좌우 비대칭·mirror·회전, 저신뢰·다수 인물, stale 결과 폐기.
- 영상: frame timestamp/stride·writer backpressure, 오디오 sync, 최대 지속시간·발열·디스크, bake off 원본 보존·태그.

각 결과에는 commit, OS, 기종, lensID, active format, requested/applied settings, 사진 hash·metadata, FPS p50/p95·drop count, memory peak, thermal trace, 재현 절차를 남긴다. 미측정 값은 비워두고 '미검증'이라고 적는다.


## SDR LUT 사진 편집 기기 확인

- HEIF/JPEG·전후면·EXIF 1~8 방향에서 원본/편집본 방향과 크기를 대조한다.
- sRGB·Display P3 차트의 ICC→sRGB 변환을 확인한다. HDR 사진은 SDR base만 편집하고 gain map이 편집본에 붙지 않는지 확인한다.
- 사용자 .cube 가져오기 취소·손상·32MiB 초과·잘못된 domain을 검사한다. Log LUT를 sRGB로 오선언하면 색 결과는 보장되지 않는다.
- 강도 변경·원본 비교·LUT 교체 중 오래된 preview가 덮어쓰지 않는지 확인한다.
- 12.6MP 이하 원본과 12.6MP 초과 원본을 시험한다. 초과 시 저장 거부 안내, 원본 bytes 유지가 기준이다.
- export 결과의 orientation=1·sRGB profile·원본/사용 LUT SHA256·JPEG 공유를 확인한다. 디스크 부족 시 부분 export 폴더가 없어야 한다.
- 편집 진입/복귀·앱 background·재활성화 때 capture session이 편집 중 재시작하지 않는지 확인한다.
- 실시간 LUT·즐겨찾기의 자동 테스트 통과와 실제 카메라 검증을 구분한다. 레시피 재열기는 자동 테스트를 통과했으며 HDR/Log 처리는 미구현이다.


## 실시간 LUT·즐겨찾기 실기기 대기 목록

- LUT import/즐겨찾기 선택→첫 GPU 프레임→강도/원본 비교→해제→원본 촬영을 반복한다.
- 전후면 portrait/mirror, preview와 사진의 crop·화각·색상 차이를 측정한다. 현재 LUT on에서 렌즈 전환/터치 AF/AE를 제한하는 UI도 확인한다.
- background/인터럽션/설정 timeout 후 기다림 표시가 남지 않는지, GPU 작업/캡처 버퍼가 누적되지 않는지 확인한다.
- 장치가 지원하지 않는 video-output·photo-format 조합과 metadata 누락/HDR 프레임이 들어오면 LUT가 명시적으로 해제되는지 확인한다.
- 즐겨찾기를 양쪽 화면에서 저장/불러오고 앱 재시작 후 bytes·표시 이름·sRGB 선언을 확인한다.
- 이 목록은 개발을 막는 조건이 아니다. 각 단계의 자동 테스트가 통과하면 다음 기능을 구현하되, 실기기 검증 완료를 주장하지 않는다.


## 그레인·편집 기록 실기기 대기 목록

- LUT 강도 0/50/100%와 grain 0/50/100% 조합에서 색·입자·원본 비교를 확인한다.
- 동일 seed의 live 프레임에서 입자 깜박임, 1024px 미리보기와 고해상도 JPEG의 지각적 입자 크기를 비교한다. 서로 다른 해상도의 byte 일치를 주장하지 않는다.
- 앱 재시작→편집 기록→설정 복원→재저장 후 새 bundle과 원본 보존을 확인한다.
- 누락·변조된 원본/LUT와 지원하지 않는 recipe가 명시 오류로 끝나며 카메라 복귀를 막지 않는지 확인한다.
- 새 자동 테스트 8개: grain 검증·해상도 좌표 및 CPU/Metal·still/live·seed 재현성 2개, recipe 재열기/재저장·v1·변조·프로파일·경로·크기·누락·symlink·목록 6개.


## Phase 3 자동 검증과 실기기 대기

자동 검증은 RAW 5개, 모니터 5개, 브래킷 7개를 추가해 총 90개다. 제한적 DNG directory 식별과 bytes 보존, advertised RAW 분류·실행 정책, histogram CPU/GPU bins·표본 상한, LUT 전 입력 분석, Zebra·피킹·alpha, 브래킷 범위·불가 조합·순서·중복·누락·파일 보존·요청 EV manifest·저장 실패 정리를 검사한다.

- 각 물리 렌즈에서 실제 지원 RAW/ProRAW 목록, AUTO/수동·AE Lock·live 전환과 UI 제한을 확인한다.
- 실제 DNG 원본 SHA256·EXIF·Photos resource를 대조하고 외부 RAW 편집기에서 현상한다. 합성 fixture가 decode되지 않은 사실과 실제 기기 검증을 구분한다.
- 프로파일·회전·전면 mirror가 적용된 preview에서 histogram·Zebra·피킹 위치를 확인한다. 센서 클리핑과 SDR 클리핑의 차이를 확인한다.
- ±0.5/1/2 EV bracket의 파일 수·요청값·실제 EXIF 노출/ISO, OIS 지원, 단일 촬영 복귀, Photos 거부 후 3장 재시도를 확인한다.
- 브래킷 중 background/인터럽션·처리 오류·timeout을 확인한다. 앱 강제 종료/전원 단절 중 다중 파일 쓰기 복구는 아직 미구현이며 별도 gate다.
- LUT+monitor 10분 사용의 실제 FPS·drop·GPU/CPU·메모리·발열을 기록한다. 현재 결과에는 실측 성능 수치가 없다.


## Phase 4–6 추가 기기 확인 (모두 대기)

| ID | 확인 | 성공 기준/증거 |
|---|---|---|
| LONG-01 | tripod·물/차량·1/30/300초, mean/lighten/정렬 | 실제 샘플 간격·elapsed·원본 방향·평균/빛 보존; 샘플 틈 명시 |
| LONG-02 | cancel/background/serious/critical/disk budget | 단일 종료·pending 정리·발열 throttle·종료 이유·기존 결과 보존 |
| LONG-03 | Instruments 300초·재처리 | peak RAM bounded, disk<=128MiB frames, 원본 PNG 재현·Photos/공유·취소 |
| GUIDE-01 | 전후면·letterbox·다수 사람·가이드 off·장면 변경 | 원점/mirror 일치·stale 숨김·guide 비굽기·원본 촬영 독립 |
| GUIDE-02 | 실제 자세/피부/의상·건물·수평선·저조도 | 검출 정확도·confidence·latency·배터리; rectangle=building 오인 금지 |
| FILM-01 | 12종 실제 피부/풍경/야경·고채도·회색 ramp | 톤·색차·banding·halo·미리보기/내보내기 차이; 수치 통과와 미학 승인 구별 |
| FILM-02 | 전체 룩 저장·앱 재시작·live/사진 복원·Hald | 강도/seed/finish 유지·sRGB 확인·원본 불변·불명 profile 거부 |

자동 gate: 선형광/Lighten·translation·archive·cancel/hash, 좌표/포즈/규칙/lifecycle, 공유 Metal finish·v1/v2/v3 recipe, 12종 cube/hash/gray ramp/검색·전체 preset 재시작/변조·Hald channel order를 검사한다. 실행별 수와 CI는 08·11 문서에 기록한다. Simulator GPU 계산 검증은 실제 사진·디스플레이·카메라 성능 승인으로 대체하지 않는다.

최신 코드 `ca05d5c`: [CI 39542442343](https://github.com/MetaParodica/PhotoP/actions/runs/39542442343), unsigned iPhone SDK build·Swift120·Python7 성공, skip0.
