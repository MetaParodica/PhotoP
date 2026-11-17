# PhotoP 최적화 구현·회귀 검증

2026-11-17. 기준 main `f6862b2`, 작업 브랜치 `codex/optimization-20261117`. [29 개선 보고서](29-OPTIMIZATION-AND-ADVANCEMENT-AUDIT.ko.md)의 우선 과제 중 검증 복구·반복 계산·LUT 캐시·저장 UI를 구현했다. 보고서 전체의 화질/AF 로드맵 완료나 실기기 성능 인수를 뜻하지 않는다.

## 1. 실패 원인 확인

main [CI44032147452](https://github.com/MetaParodica/PhotoP/actions/runs/44032147452)의 보존된 xcresult를 [읽기 전용 진단44039406450](https://github.com/MetaParodica/PhotoP/actions/runs/44039406450)에서 열었다. 실제 집계는344개 중342개 통과·1개 skip·1개 실패다. 실패는 `CompanyFilmLibraryTests/testCompiled65CubeCacheSurvivesRestartAndRejectsCorruption()`의 **“Test exceeded execution time allowance of 2 minutes”**다. 콘솔의 마지막 필름 테스트 이름만으로 메모리 부족/크래시를 확정하지 않는다.

단위 테스트와 대량 LUT 회귀를 별도 xcodebuild 실행으로 나눴다. 테스트당 기본120초/최대180초 제한은 유지했다. 단위 테스트가 실패해도 LUT/UI 검사와 가능한 자료 수집은 실행한다. 원시 로그와 summary를 남기고 Simulator 종료 후 닫힌 xcresult를 압축해 업로드한다. 이전 artifact의 세 결과 번들을 읽는 수동 `diagnostic_run`도 추가했다.

첫 분리 실행44041816799에서는 LUT 단계가08:07:56에 시간 초과로 끝난 뒤에도 해당 xcodebuild 로그가08:11까지 계속 기록됐고 UI 검사도 동시에 실행됐다. 결과에 나타난 `signal kill`을 메모리 부족으로 단정하지 않는다. 후속 진단44046104603에서도 이 실행/종료 흔적을 보존했다. `scripts/run_test_process.py`가 독립 프로세스 그룹을 만들어 기한·취소 때 자식까지 종료하며, 실패 후에는 선택한 Simulator만 재시작한다. 로그는 각 suite 직후에도 별도 artifact로 공개한다. 종료 코드/두 출력 스트림, 부모·자식 시간 제한, 취소 신호 전달을 실제 하위 프로세스로 검사했다.

## 2. 적용 내용

| 보고서 | 구현 | 검증·범위 |
|---|---|---|
| A01 | LUT 회귀 분리, 실패 후 UI 실행, 로그·summary·닫힌 결과 압축 보존 | 실제 main 결과에서 시간 초과 확인. 최신 전체 CI 결과는 아래에 기록 |
| A02 | Simulator의 특정 Flow 생성 실패만 skip. 다른 Vision 오류와 실기기 오류는 실패 | 실제 로그의 `com.apple.Vision Code=9`(`internalError`)·정확한 문구·Simulator 조건을 모두 확인. 다른 코드/실기기 거부 회귀. 실기기 방향 검증은 남음 |
| B01 일부 | 모델 프레임의 정규화 범위를 한 번 계산. 움직인 픽셀 무효화 때 기존 범위 유지. 동일 매트/출력 크기의 CI 이미지 하나 재사용 | 일부 전경 무효화로 남은 배경의 깊이가 재확대되지 않는 회귀 추가. 프리뷰 luma 생성은 기존 경로 |
| B04 | Core ML 입력 CVPixelBuffer 재사용, 매회 CI 캐시 비우기 제거. 터치 위치의 instance label로 매트 하나만 생성 | label8 초과·행 stride·상하 좌표·배경/잘못된 좌표 검사. 실제 다중 피사체 화질/할당량은 기기 계측 필요 |
| B04 | 실패하는 Flow에0.5~30초 지수 backoff, 성공/세대 전환 시 초기화 | 재시도 간격·상한·잘못된 시계값 공통 테스트. 기존 움직임/만료 안전 복귀 유지 |
| B05 | hash/버전 검증된 packed Float64 런타임 캐시. 기술 LUT와 sRGB 룩 모두 재사용. 원본과 SDR 파생 `.cube` 보존 | CPU 표의 비트·도메인·출처·채널 순서 유지. 구형 캐시 업그레이드, binary/cube 손상 복구, 악성 크기·NaN 거부. sRGB는 원본 `.cube`를 중복 저장하지 않음 |
| B05 | 파일용 비지역화 포맷 API, 청색 plane 단위 임시 객체 해제 | 기존7/8자리 텍스트·반올림 경계·음의0·hash 계약 유지. 실제 iPhone 생성 시간/메모리는 별도 측정 |
| B08 | 저장 중 f값·프로필·원본 비교 제어 잠금, 초점 탭 거부 유지 | 저장 snapshot과 화면 값 일치. 저장 취소 버튼은 활성. 전용 저장 중 UI 자동화는 추가 과제 |
| 계측 | LUT load·추론 대기/실행·Flow·매트·고해상도 export에 OSSignposter 구간 | Instruments 관측 지점이며 이미지/상시 사용자 로그를 기록하지 않음 |

원본 사진·외부 LUT 원본·권한 manifest는 변경하지 않았다. 바이너리는 손실 없는 디스크 캐시이며 GPU Float 표나 HDR/Log 파이프라인 변경이 아니다. iOS 최소17은 유지한다. SwiftPM 공통 테스트만 macOS13을 명시해 최신 Task API 사용 조건을 맞췄다.

## 3. CPU 마이크로벤치마크

`scripts/benchmark_processing.swift`는 변경 전의 행별 locale/전체 문자열 생성 및 프레임별 두 번 정렬과 현재 경로를 같은 프로세스에서 순차 비교한다. Swift6.0.3 `-O`, Debian13 x86_64,65³ LUT,160×120 깊이120프레임 조건이다. 텍스트 bytes와 복원된 LUT 표가 같지 않으면 실패한다. 깊이 checksum 차이는 새 프레임까지 정규화 범위를 고정하는 의도된 정책 차이다.

Linux CPU 비교이며 iPhone FPS·ANE·발열·전체 룩 선택 지연을 측정한 값이 아니다. 해시 검사·파일 IO·GPU 업로드는 parse/decode 측정 밖이다. 순차3회 결과의 중앙값은 다음과 같다.

| 구간 | 변경 전 | 현재 | 해석 |
|---|---:|---:|---|
| 65³ 텍스트 생성 | 22.822초 | 0.5267초 | 비지역화 포맷 사용. 세 번 모두 텍스트 bytes 동일 |
| 동일 LUT 표 읽기 | 텍스트2.349초 | binary0.001453초 | 파싱/디코딩만 비교. 세 번 모두 LUT 표 동일 |
| 깊이120프레임, 정규화 반복 | 0.1584초 | 0.004079초 | 프레임별 정렬 제거 효과. 전체 프리뷰 시간 아님 |

세 번의 범위는 생성(기존22.473~23.198초/현재0.523~0.527초), 텍스트 파싱2.324~2.364초, binary1.431~1.529ms, 깊이 정규화(기존150.191~158.959ms/현재3.669~4.288ms)였다. 모든 실행에서 텍스트 bytes와 런타임 표의 동등성 검사를 통과했다.

처음 시도한 locale 객체 한 번 생성+plane 분할만으로는 생성 시간이 개선되지 않았다(기존22.593초/변경22.984초). [Apple 고정 형식 문자열 문서](https://developer.apple.com/documentation/foundation/nsstring/init(format:arguments:))의 “without applying any localization … fixed-format representations” 지침을 직접 확인한 뒤 파일용 비지역화 포맷으로 바꿨다. 현재 수치는 이 두 번째 변경 `cbf0297`의 결과다.

```sh
swiftc -O -o /tmp/photop-processing-benchmark \
  ios/PhotoP/Processing/CubeLUT.swift \
  ios/PhotoP/Processing/LUTTextEncoder.swift \
  ios/PhotoP/Processing/LUTBinaryCodec.swift \
  ios/PhotoP/Processing/SoftwareDepthPolicy.swift \
  ios/PhotoP/Processing/HighResolutionPolicy.swift \
  scripts/benchmark_processing.swift
/tmp/photop-processing-benchmark 65
```

## 4. 검증 기록

- Linux Swift 공통 XCTest118개 통과. Python31개 통과, 모델3파일·기본 LUT5개·외부25개 무결성 통과.
- `304bc91`의 [전체 CI44042167759](https://github.com/MetaParodica/PhotoP/actions/runs/44042167759): iPhone/Simulator 빌드 통과, 단위336개 중335통과/1실패. 실제 Flow 오류 코드를 처음에 잘못 지정한 문제를 확인해 `35d2ad6`에서 수정했다. 분리한 LUT 회귀도 앞선 실행44041816799에서 단계 제한에 도달했다.
- `cbf0297`의 [전체 CI44044365082](https://github.com/MetaParodica/PhotoP/actions/runs/44044365082)는 알려진 Flow 분류 실패와 프로세스 중첩이 남아 후속 수정본으로 대체·중단했다. 성공으로 인용하지 않는다.
- `35d2ad6`의 [전체 CI44046582315](https://github.com/MetaParodica/PhotoP/actions/runs/44046582315)는 iPhone/Simulator 빌드·단위337개 중336통과/1skip/실패0. LUT/UI는 진행 중이다.
- `249e6c8`의 [전체 CI44046857607](https://github.com/MetaParodica/PhotoP/actions/runs/44046857607)는 sRGB 프리셋의 바이너리 캐시와 재시작/손상 복구 회귀까지 포함한 실행이다. iPhone/Simulator 빌드·단위337개 중336통과/1skip/실패0이며, 독일어 지역 설정 LUT17개와 UI11개는 진행 중이다.
- 앞선 CI에서 드러난 macOS 배포 버전과 Swift6.2 테스트 fixture 타입 추론 오류는 실제 로그를 확인해 수정했다. Linux 성공으로 Apple SDK 성공을 대체하지 않는다.

## 5. 남은 과제

실기기에서 Flow 방향/가림/전면·가로 좌표, 실제 instance mask 선택,10분 열/전력, 기기별 p50/p95와 peak memory,24/48MP 처리, 저장 중 취소와 원본 보존을 인수해야 한다. 저장 중 제어 잠금은 실제 편집 UI 자동화로도 보강해야 한다.

B02 우선순위/기한 추론 스케줄러, B03 열 제어, B06 GPU 타일 파이프라인, B07 촬영/후처리 큐, C01~C08 화질·눈 AF·보관함·구조 과제는 별도 개발 범위다. 기존 `docs/depth-acceptance`의 실제 평가 데이터는 비어 있으므로 업계 최고 수준·출시 품질·iOS27 실기기 검증 완료를 주장하지 않는다.
