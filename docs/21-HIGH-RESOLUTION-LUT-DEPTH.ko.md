# 고해상도 LUT·심도 처리 및 외부 LUT 사용 권한 반영

후속 LUT 적용 누락/즐겨찾기·편집 연결 수정과 커밋·main 반영 요청은 [22 문서](22-LUT-APPLICATION-AND-NEXT-STEPS.ko.md)를 우선한다. 아래 미커밋·미푸시 설명은 이 기능 구현 당시의 기록이다.

2026-10-23 KST. 기준 `main`의 `736cdcc`. 사용자 요청에 따라 고해상도 처리와 외부 LUT 사용 권한 확인만 반영했으며 이전 보고의 편집 대상/단체 비교/썸네일 문제는 이 작업에서 수정하지 않았다. 현재 변경은 미커밋·미푸시다.

## 고해상도 처리 범위

- 촬영 후 LUT·실제 깊이 기반 f값 결과와 LUT 사진 편집기 내보내기에 공통 `HighResolutionPhotoProcessor`를 연결했다.
- 최대 **64,000,000픽셀·긴 변 16,384px**. 5712×4284(24.5MP), 8064×6048(48.8MP)와 회전된 사진을 임의 축소하지 않는다. 출력 JPEG·레시피에 방향 적용 후의 실제 너비/높이를 기록한다.
- 센서 촬영 해상도와 실제 깊이 데이터 전달은 활성 렌즈/포맷의 지원 범위를 따른다. 모든 iPhone에서 48MP 깊이 사진을 촬영할 수 있다는 의미가 아니다. 사진 깊이 없이 f값 효과를 만들어 내지 않는다.
- RAW/DNG 현상, HDR/Log 처리를 추가하지 않는다. 원본 bytes·EXIF는 보존하고 별도 encoded sRGB SDR JPEG만 생성한다. 파생물에는 HDR gain map/원본 EXIF를 복사하지 않으며 기존 LUT 출처 캡션을 유지한다.
- 작은 프리뷰는 기존 1024px 제한을 유지한다. 카메라 LUT/카드 미리보기는 이전 사용자 요청대로 끈 상태이며 고해상도 지원을 이유로 다시 켜지 않았다.

## 처리 구조·메모리·타일 경계

1. ImageIO 메타데이터에서 크기/RAW 여부를 먼저 검사하고 Core Image에 EXIF 방향을 한 번만 적용한다. 64MP/긴 변 상한 밖은 명시적으로 거부한다.
2. 원본 전체 RGBA를 기존 Metal renderer에 넣지 않는다. 출력 영역은 최대 1024×1024 타일로 나눈다. Core Image가 필요한 색/심도 영역을 렌더하고 기존 `SDRImage.rasterize`의 상단 원점 메모리 계약을 사용한다.
3. 실제 깊이 지도를 AVDepthData로 읽고 방향·비율·유효 초점 깊이를 검증한다. 깊이 마스크를 사진 크기로 좌표 변환한 `CIMaskedVariableBlur` 이미지 그래프를 만들며, 전체 크기의 흐림 결과를 먼저 CPU RGBA로 복사하지 않는다.
4. LUT/입자/공간 효과는 겹침 영역(halo)을 포함한 타일에 적용하고 출력 중심 영역만 복사한다. halo는 소프트 포커스·bloom·halation의 샘플 반경, 색수차 최대 이동, 가로 streak의 8배 샘플 이동 중 최대값이다.
5. Swift/Metal 공통 인자에 **타일 원점과 전체 사진 크기**를 추가했다. 입자의 시드/주기, 비네팅 중심, 색수차/공간 효과 반경은 타일 크기가 아니라 전체 사진 좌표를 따른다. 기존 프리뷰/단일 패스는 기본 원점0/기존 크기를 사용한다.
6. 출력 RGBA는 임시 파일을 `mmap`하여 보관하고 ImageIO provider가 해당 매핑을 유지한 채 JPEG 파일로 인코딩한다. 48.8MP 사진의 RGBA 작업 파일은 약 186MiB이며, 이 크기의 입력/출력 Metal 버퍼를 두 벌 만들지 않는다. 최대 효과에서 48.8MP 타일의 입력은 최대1280×1280(약6.25MiB)이다.
7. 사전 여유 공간 검사(전체 RGBA 크기+64MiB), `F_PREALLOCATE` 실제 작업 파일 공간 예약, 동시 내보내기 거부, 타일 사이 취소 검사, 정상/실패/취소의 작업 파일 해제를 추가했다. 공간 예약 실패 시 매핑하지 않고 거부한다. 결과·레시피·LUT는 기존 `.pending-UUID` 폴더 안에서 준비한 뒤 최종 폴더로 이동한다. 이미 존재하는 출력 파일은 덮어쓰지 않는다. 매핑 파일은 provider가 잠시 유지되어도 폴더 이동 전에 unlink하며 열린 매핑의 수명은 provider가 보장한다.

이것은 작업 버퍼를 제한하는 구조이지 **전체 앱 RSS/인코더 메모리의 절대 상한 보장**이 아니다. ImageIO/HEIF 디코더·JPEG 인코더·Core Image 캐시·OS 매핑 페이지의 실제 메모리는 기기에서 측정해야 한다. JPEG의 실제 추가 디스크 사용량, 처리 중 공간 변동, 프로세스 강제 종료 시 남을 수 있는 임시 폴더도 별도 저장 공간 인수 항목이다. 기존 12.6MP `SDRImage`/직접 Metal 작업 제한은 작은 in-memory 작업 안전장치로 남긴다. 고해상도 내보내기는 새 파일 기반 경로를 사용한다.

## 외부 LUT 권한 상태

- 기존 외부 파일30개(별도 CC BY 4.0 팩5개+company 팩25개)는 이미 앱 번들에 포함되어 있다. 이번에는 **프로젝트 소유자가 외부 LUT 권리가 모두 사용 가능하다고 확인하고 즉시 포함을 요청한 사실**을 새 권한 근거로 반영했다.
- company25개 각각 `rightsStatus: user-confirmed`, `license: USER-CONFIRMED-PERMISSION`, `commercialUseAllowed: true`, `redistributionAllowed: true`로 기록했다. manifest 최상단에 확인자(`project-owner`), 확인일(`2026-10-23`), 확인 근거를 남겼다.
- 이것은 사용자의 확인 기록이지 PhotoP가 독립적으로 계약서를 감사했거나 특정 SPDX/CC 라이선스를 새로 부여했다는 의미가 아니다. 제조사 공식 인증·제휴를 뜻하지도 않는다. `official: false`를 유지한다.
- 원본25개의 bytes·SHA-256·Git blob·원본 copyright header·고정 출처 revision은 변경하지 않았다. 기존5개의 CC BY 4.0 라이선스/크레딧도 변경하지 않았다.
- Swift manifest 검증·Python 검사·UI·새 LUT provenance/프리셋/공유 캡션에 권한 확인 상태를 반영했다. 이전 사용자 편집/즐겨찾기/레시피 파일은 소급 변경하지 않는다. 변환 cube 캐시는 수치 데이터만 재사용하고 새 로드의 출처·권한은 현재 manifest에서 생성한다.
- **사용 권한과 색 프로파일은 별개다.** company25개 중24개는 현재 sRGB/SDR 해석 또는 기존 V-Log SDR 어댑터로 선택/적용할 수 있다. 출력 `wdr-unverified` 기술 LUT1개는 원본 파일·출처·공유만 유지한다. 권한 확인만으로 불명확한 WDR 출력을 sRGB로 잘못 선언하지 않는다.

## 변경 파일

- 신규: `Processing/HighResolutionPolicy.swift`, `Processing/HighResolutionPhotoProcessor.swift`.
- 연결: `CaptureResultProcessor.swift`(실제 깊이 추출/공통 이미지 그래프), `LUTPhotoEditor.swift`(파일 기반 고해상도 내보내기), Metal LUT 인자/커널, FilmFinish 인자/커널, 편집기/수동 제어 안내.
- 권한: company manifest/notice, `CompanyFilmLibrary.swift`, `FilmStylesView.swift`, Python 검사 및 테스트. 라이브 LUT 미리보기·원본·기존 촬영 제어를 바꾸지 않았다.
- 테스트: portable `HighResolutionPolicyTests.swift` 6개, iOS 전용 `HighResolutionProcessingTests.swift` 7개, 권한 레코드 iOS 테스트1개 및 기존 provenance 테스트 수정, Python 권한 검증2개 추가.
- 새 외부 의존성 없음. 기존 Apple Core Image/ImageIO/Metal 및 Darwin 파일 매핑을 사용한다.

## 실행한 검증과 미검증

- Swift 6.0.3/Linux portable XCTest **69개 통과**(기존63+고해상도 정책6). 24/48/64MP 계획, overflow·상한 거부, 홀수 크기 출력 전 영역 1회 포함, halo/경계·GPU 작업 크기 상한을 검사했다. 실제 JPEG/Metal 결과 검증은 아니다.
- Python **19개 통과**(기존17+권한2). 회사 LUT25개 모두 사용자 확인 레코드·해시·프로파일·파일 수 검사 통과, 별도5개 승인 팩 검사 통과. 허위 공식 표시·불완전 권한 기록·프로파일 덮어쓰기를 거부한다.
- Swift **131개 파일 구문 검사** 및 `git diff --check` 통과. Swift 구문 검사에 Metal 컴파일·iOS SDK 타입 검사·링크는 포함되지 않는다.
- iOS 전용7개는 24/48MP 출력 크기·원본 해시, 타일 상하/채널 좌표, 단일/타일 LUT+입자+모든 공간 효과의 바이트 일치, 합성 마스크의48MP 그래프 크기, 실제 깊이 부재 거부, 기존 파일 덮어쓰기 방지, 취소/임시 파일 정리를 검사하도록 작성했다. 권한 레코드 iOS 검사1개도 추가했다. **이 환경에는 Xcode/iOS SDK/Metal runtime/Simulator/iPhone이 없어 실행하지 못했다.** 합성 마스크 그래프 테스트는 실제 센서 깊이 전달 검증이 아니다.
- 새 CI 성공/실제24·48MP 처리 결과 이미지·속도·메모리·발열 측정값은 없다. 코드 통합과 iPhone 인수를 구분한다.

우선 인수: Mac에서 전체 SDK/앱 테스트와 기존 renderer/texture 동등성 회귀 실행 → iPhone24/48MP의 LUT/공간 효과 경계·ICC·EXIF 회전 확인 → 지원 렌즈 실제 깊이 전달/f값 결과 → 저전력/저장 공간 부족/배경 전환/강제 종료 복구 및 메모리·발열 계측 순서다.
