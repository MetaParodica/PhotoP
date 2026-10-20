# F. 빌드·테스트·실기기 검증 절차

## 환경과 빌드

이 작업 세션은 Linux이며 로컬 Swift·Xcode·iOS SDK가 없다. 따라서 로컬에서 iOS 코드를 실행했다고 주장하지 않는다. GitHub macOS CI는 별도의 빌드·모델 테스트 증거이며 실기기 카메라 검증을 대체하지 않는다. 결과는 구현 보고서와 PR checks에서 확인한다.

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

Swift XCTest 5개는 수동 범위·비유한값·경계값·미지원 controls·AUTO EV·WB/초점 범위를 검사한다. `.github/workflows/ios.yml`이 XcodeGen 생성 → unsigned device build → 사용 가능한 iPhone simulator의 모델 테스트 → 자산 검사 순서로 수행한다. Simulator 카메라 실행은 성공 기준으로 쓰지 않는다.

## 실기기 매트릭스

실제 확보 기기를 기록하고 기종을 추정하지 않는다. 최소 조합: ① 최소 OS의 지원 iPhone ② 최신 OS의 비Pro iPhone ③ 최신 OS의 RAW/ProRAW 지원 Pro iPhone. 카메라 수·렌즈·ProRAW 지원 여부를 API로 기록한다. 하나의 기기로 모든 모델을 검증했다고 처리하지 않는다.

| ID | 절차 | 기대 결과 / 기록할 증거 |
| --- | --- | --- |
| CAM-01 | 최초 실행에서 카메라 허용·거부 각각 수행 | 허용 시 프리뷰; 거부 시 명확한 설명, shutter 비활성; Settings 허용 후 재시도 |
| CAM-02 | 후면 wide·ultrawide·tele와 전면 중 존재하는 것만 순환 | 물리 lensID·capabilities 갱신; 화면/저장 방향·mirror 정책 일치 |
| CAM-03 | 10장 연속 촬영·빠른 중복 탭 | 1회 in-flight, JPEG decode 가능, 원본 수·Photos 수 대조 |
| CAM-04 | ISO·셔터 최소/중간/최대에서 정적 장면 촬영 | ImageIO EXIF ISO·ExposureTime·요청 설정 기록. 양자화·settling 차이를 설명하고 이상치 해결 |
| CAM-05 | AUTO EV -/0/+ 촬영 | 실제 밝기·bias metadata·노출 변화 확인. full manual에 EV가 적용된다고 표시하지 않음 |
| CAM-06 | 수동 focus / AUTO 복귀, WB warm/cool/Tint | 카메라 동작·초점/색 변화 확인; 미지원 controls 비활성. Kelvin 정확도는 광원 기준 별도 측정 |
| CAM-07 | 촬영 전·촬영 중 홈/잠금/전화 등 인터럽션 | 진행 사진은 성공 또는 명시 실패, hang 없음; 복귀 후 재시작·대기 중복 없음 |
| CAM-08 | Photos 접근 거부·다시 허용 | 앱 원본 URL 유지, ShareLink로 파일 보냄, 재시도 후 성공 표시 |
| CAM-09 | 저장 공간 부족 조건 | 원본/Photos 실패 원인 표시, 성공 거짓 표시 없음; 앱 원본 쓰기 실패 복구 정책 확인 |
| CAM-10 | 재시작·앱 제거에 대한 데이터 정책 검토 | 원본 디스크 보관 확인; 마지막 원본 UI 복원·전체 갤러리는 아직 미구현 |
| PERF-01 | 10분 프리뷰·렌즈/PRO 반복 변경 | FPS·CPU/GPU·resident memory·thermal state·배터리 구간 기록; 초기 목표 60FPS 달성 여부 확인 |
| UI-01 | 작은 화면·Dynamic Type·VoiceOver·다크 UI | shutter·설명·저장 재시도 접근 가능; 큰 글씨 clipping과 화면 overflow 수정 |

EXIF 추출은 Mac의 ImageIO 또는 승인된 도구를 사용한다. 원본 SHA-256은 앱 저장 파일과 내보낸 원본 사이에서 비교한다. Photos가 표시용 thumbnail/변환본을 제공한 경우 original resource와 구분한다. 사용자 사진이나 EXIF 위치를 CI 로그에 올리지 않는다.

## 후속 처리 품질 gate

- LUT: identity, domain, nonfinite·malformed·oversized import, 강도 0/1, CPU double vs GPU, profile mismatch, HDR→SDR, export ICC.
- 합성: 고정 noisy frame의 mean 수치·분산 감소, translation/rotation 정답, Lighten 색 선택 정책, valid-edge mask, ghost/과노출, cancel·disk·thermal.
- 가이드: off-device 전송 없음, 정규화 좌표→view mapping, 좌우 비대칭·mirror·회전, 저신뢰·다수 인물, stale 결과 폐기.
- 영상: frame timestamp/stride·writer backpressure, 오디오 sync, 최대 지속시간·발열·디스크, bake off 원본 보존·태그.

각 결과에는 commit, OS, 기종, lensID, active format, requested/applied settings, 사진 hash·metadata, FPS p50/p95·drop count, memory peak, thermal trace, 재현 절차를 남긴다. 미측정 값은 비워두고 '미검증'이라고 적는다.
