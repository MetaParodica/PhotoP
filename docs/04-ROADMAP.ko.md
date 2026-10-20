# D. 개발 로드맵과 완료 기준

일정은 팀 규모·실기기·라이선스 실사에 따라 결정한다. 기능 수를 기준으로 완료를 선언하지 않고 각 gate를 통과한다. 현재는 Phase 0 1차 조사와 Phase 1 기본 촬영·수동 제어 보완 단계다. 실제 iPhone 검증은 대기 중이다.

| Phase | 구현 범위 | 선행 조건 | 기술 위험 | 테스트 방법 | 완료 기준 |
| --- | --- | --- | --- | --- | --- |
| 0 기술 실사 | 26개 후보 1차 비교, license/asset 범위, iOS 17 제안, ADR, 기기 계획 | 저장소 접근·공식 API | README 오인·라이선스 누락·예제 OS 버전 차이 | 주요 소스 읽기, revision 고정, 최소 컴포넌트 빌드 | 후보별 불확실성과 도입/보류 근거 기록; 실사 미완료 부분을 분리. 전체 외부 의존 빌드는 아직 미완료 |
| 1 iOS 카메라 | preview, JPEG/HEIF, 전후·물리 렌즈, ISO/셔터/EV/WB/초점, grid·터치 AF, 권한/중단/원본 보관 | Phase 0, Mac/Xcode·실기기 | 세션 경쟁·수동 적용 비동기·포맷 전환·저장 실패 | 단위 검증+기기별 촬영·EXIF, 거부/중단/재시작·연속 조작 | 최소·최신 OS에서 설정 변경→촬영→파일/EXIF 확인, 반복 촬영과 복귀에 장애 없음. 초기 JPEG 코드만으로 Phase 1 전체 완료 아님 |
| 2 LUT·필터 | Metal preview/export, cube import, 3D·강도, favorites·기초 grain, 레시피 | 안정된 캡처·색 프로파일·권리 승인 자산 | 색공간 mismatch, 중복 tone mapping, GPU 복사·공백 frame | identity/domain/channel fixture, CPU/GPU 비교, 동일 입력 preview/export 비교, 성능 trace | 동일 입력 렌더 RGB 최대 오차 2/255 이하를 초기 SDR gate로 제안; identity path 기준 보존. 컬러 차트 색차·display 측정 기준 별도 확정 |
| 3 RAW·고급 촬영 | Bayer DNG, 지원 ProRAW, histogram·Zebra·peaking·브래킷 | capability negotiation·PhotoOutput 계약 | RAW/수동/해상도 조합 제한·원본 파괴 | 원본 hash, API 지지 조합별 촬영, 메타데이터·외부 RAW 현상 검증 | 미지원 조합 명시 거부, 원본 불변, 각 도구 fixture·실기기 통과 |
| 4 장노출 | mean/lighten, 정렬·NR, intermediate preview, cancel·결과/작업 저장 | 선형 색관리·bounded buffers·기기 budget | RAM/발열·떨림·rolling shutter·누락 프레임 | synthetic noise/translation/hotpixel, tripod+handheld, 1~300초 soak, disk/cancel | streaming 메모리 상한 유지; 정렬 잔차·합성 수치 기준 충족; 취소 후 원본/작업 일관성. 별 궤적·HDR·median은 추가 gate |
| 5 촬영 가이드 | 고급 격자, 인물/포즈·건물·풍경, 규칙→필요 시 AI | 좌표 계약·온디바이스 분석 | 좌우/회전 오차·낮은 조도·불안정 권고 | 비대칭 좌표 fixture, 4방향·전후면·crop·다중 인물, 사람 평가 | 정규화 좌표를 지정 오차(초기 2 display px) 내 매핑; stale 안내 숨김; AI off 시 캡처 독립 동작 |
| 6 필름 확장 | 공식 허가 LUT·open assets·자체 profiles, grain/halation 등 | Phase 2, 권리·품질 평가 샘플 | 유사 룩 중복·브랜드 오인·자산 재배포 | 피부/차트/야경/풍경/고채도/회색 ramp, LUT 전후 비교, 권리 manifest | 독립 스타일 100+를 장기 목표로 검수; 각 항목 출처·hash·profile·rights·credit 증거 필요. 현재 0개 |
| 7 전문 영상 | 지원 resolution/FPS/codec, manual·monitor LUT, Log, scopes/audio·stabilization | 사진/색관리 안정·동영상 스트림 협상 | writer backpressure·오디오 동기·발열·HDR 태그 | 긴 녹화·오디오 sync·실제 codec/profile metadata·프레임 카운트·외부 NLE | 지원 조합만 표시, 원본 비굽기 모드 보존; 안정화/FPS/셔터 제약 표시. 기본 카메라 cinematic depth mode와 혼동 금지 |
| 8 Android | Kotlin/Compose Camera2 adapter, 필요 시 CameraX, schema/fixture 공유 | iOS 계약 안정·대표 Android 기기 | hardware level·RAW/manual·stream combination 파편화 | capabilities/request/result 교차, Pixel/Galaxy 등 실제 확보 기기, 동일 LUT fixtures | 구현별 지원/거부 근거 기록, 사진 원본·색 계약 일치, unsupported UI 숨김/설명 |
| 9 품질·배포 | GPU·메모리·발열·배터리·접근성·개인정보·배포 설정 | 각 기능 gate 통과 | 장시간 불안정·회귀·번들 권리 누락 | Instruments, battery/thermal soak, VoiceOver·Dynamic Type·권한·디스크, release archive 검사 | crash/원본 유실 gate 통과, 기기별 성능 보고·미지원 목록·권리 고지·서명 archive 검증 |

## 첫 구현 작업 분해

| 작업 | 수정 단위 | 검증 기준 | 현재 |
| --- | --- | --- | --- |
| F1 프로젝트 생성 | project.yml, Info.plist, App | XcodeGen 생성·device SDK build | 코드·CI 구성 |
| F2 세션·권한 | CameraService | 메인 스레드 비블로킹; permission 거부/복귀 | 코드 작성·기기 미검증 |
| F3 프리뷰·렌즈 | CameraPreview, physical discovery | 전후면·실제 렌즈별 프리뷰와 저장 방향 | 코드 작성·기기 미검증 |
| F4 촬영·저장 | delegate, PhotoStore | 중복 continuation 없음; JPEG 원본 bytes 동일·Photos 거부 시 원본 유지 | 코드 작성·기기 미검증 |
| F5 PRO 입력 | models, validator, controls, completion gate, readout | 범위/지원·콜백 중복/순서/취소·노출 우선순위 테스트; EXIF 실제값 대조 | 완료 콜백·장치 readout 코드 추가, 기기 미검증 |
| F6 작업 내구성 | interruption/runtime error/background/settings timeout | 화면 복귀 후 재시작·pending capture/settings 명시 실패 | 설정 작업 ID·취소 회귀 테스트 추가, 실기기 fault test 대기 |
| F7 번들 권한 | manifest gate | 허가·hash·profile 누락/경로 이탈 차단 | 로컬 회귀 테스트 통과 |

다음 개발 gate는 실제 iPhone의 JPEG 촬영과 메타데이터 확인이다. 그 이전에는 LUT·AI를 화면에 완성된 도구처럼 표시하지 않는다.
