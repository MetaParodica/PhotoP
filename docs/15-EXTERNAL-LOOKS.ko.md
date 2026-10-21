# 외부 룩 원본 전체 추가 · 2026-10-21

## 구현 기능

이번 조사에서 실제 바이트를 확보한 신규 LUT **25개 전부**를 `assets/company-luts`에 원본 그대로 포함한다. 기존 외부 slay 5개와 합쳐 외부 파일은 30개다. 새로운 25개는 크리에이티브 룩 22개·기술 변환 3개로 분류한다. PhotoP 자체 24개와 기존 slay 5개를 합치면 컬러 LUT 룩은 **51개**, 별도 기술 변환은 3개다. 단순 링크만 확인한 공식 다운로드 팩을 확보 수량으로 계산하지 않는다.

Fujifilm 계열 ACROS/ASTIA/Classic Chrome/Classic Negative/ETERNA/ETERNA BB/PRO Neg Std/PROVIA/REALA ACE/Velvia, Leica 계열 Classic/Natural, ARRI Classic709, RED 계열과 Nikon N-Log용 RED 변형, Cineon/Fuji 3513DI/Kodak 2383 파생, RocketStock Django 25와 Presetpro Cinematic을 포함한다. 공식 제조사 배포본과 동일하다고 주장하지 않는다.

## 참고 소스와 권리 기록

| 출처 | 고정 버전 | 확보 | 기록 |
| --- | --- | ---: | --- |
| [DeMeerleerGilles/Lumix-film-simulation](https://github.com/DeMeerleerGilles/Lumix-film-simulation/tree/18f4d9d606f9b4fc5cbe9d664ef0a6d3d0fdb1b5) | `18f4d9d606f9b4fc5cbe9d664ef0a6d3d0fdb1b5` | 23 | 비공식 V-Log 파생. 최상위 LICENSE 미확인. |
| [pmndrs/postprocessing](https://github.com/pmndrs/postprocessing/tree/9cf03cff26615636a564d8bfddf765edb8917441) | `9cf03cff26615636a564d8bfddf765edb8917441` | 2 | demo에 있는 RocketStock/Presetpro 원본. 저장소 MIT를 외부 LUT 허가로 간주하지 않음. |
| [colour-science/colour](https://github.com/colour-science/colour) | V-Log 수식 blob `446623e36ee4d755a53c817196fae8a6dfe30653`, V-Gamut blob `917a9ddc5c0a71f51c29892cbe46a96104020109` | 알고리즘 참고 | BSD-3-Clause. 공개된 변환 수학을 독립 구현. |

사용자의 지시에 따라 권리 확인 여부를 포함 조건으로 사용하지 않는다. 원본 헤더·출처·고정 revision·SHA256·Git blob SHA·입출력 프로파일·권리 미확인 상태를 manifest에 보존한다. 상업 사용/재배포 허가는 알 수 없어 `null`로 기록하며 승인된 값으로 바꾸지 않는다. 기존 Bool 기반 레시피에는 `false`(허가 확인 안 됨)와 `UNVERIFIED`/출처를 함께 넣는다. 이를 확인된 금지 조건이나 신규 허가로 해석하지 않는다.

## 기술적 접근

기존 엔진은 encoded-sRGB SDR이다. V-Log 입력 LUT를 sRGB 값에 직접 적용하지 않는다.

1. sRGB 디코딩 → 선형 sRGB.
2. D65 행렬로 V-Gamut 변환.
3. Panasonic V-Log 인코딩: `x < .01`이면 `5.6*x+.125`, 그 외 `.241514*log10(x+.00873)+.598206`.
4. 확보한 원본 LUT 샘플링.
5. 출력은 Rec.709/감마2.4·제로 블랙으로 **가정**하여 선형화 후 sRGB 인코딩.
6. 65³ SDR 파생 cube를 백그라운드 actor에서 생성하고 원본 해시+adapter 버전으로 디스크 캐시.
7. 기존 공통 CPU 참조/Metal 사진·라이브 렌더러 사용. 원본 LUT의 해시와 파생 렌더 LUT의 해시는 별도로 보존.

이미 톤 매핑된 SDR에서 장면 HDR, 제조사 센서 특성, 원본 Log 촬영 정보를 복원하지 않는다. 입력·출력 가정은 적용 전에 화면에 표시한다. 표시용 Django/Presetpro 파일은 원본 프로파일이 미기재되어 sRGB로 가정한다.

`FLog2C_to_WDR_VLog.cube`는 출력 변환을 확정하지 못했다. **원본을 포함하고 공유할 수 있지만 이미지에 적용하지 않는다.** 이는 색공간 호환성 제한이다. 나머지 기술 변환 2개는 SDR 가정을 확인한 뒤 적용할 수 있다.

## 생성·수정 파일

- `assets/company-luts/manifest.json`, `SOURCE-NOTICE.txt`, `raw/`의 원본 25개.
- `CompanyFilmLibrary.swift`, `SDRVendorAdapter.swift`: 입력 프로파일, 무결성, 컴파일 캐시.
- `FilmStylesView.swift`: 기업/미러 룩 검색·분류·선택·원본 공유.
- `ios/project.yml`: Debug/Release 모두 폴더 리소스로 포함.
- `check_company_luts.py`, Python/Swift 테스트: 원본·프로파일·미확인 권리 기록·캐시·프리셋.
- CI: 소스와 복사된 앱 리소스 모두 해시 검사. 기존 승인 LUT 검사와 별도로 외부 미확인 자료를 보고한다.

## 테스트와 다음 단계

로컬 Python 검사 17개와 실제 원본 25개 무결성 검사가 성공했다. Swift 테스트에는 V-Log 코드값, 전체 LUT/색상표, 파생 cube 오차, 65³ 캐시 재시작·손상 복구, Metal 일치, WDR 적용 제한 및 미확인 출처의 프리셋 복원을 추가했다. [실행39579967039](https://github.com/MetaParodica/PhotoP/actions/runs/39579967039)에서 SDK·Swift149·UI1·Python17·소스/실제 앱 LUT30개 검사·화면 캡처가 모두 성공했다. 공간 효과를 통합한 최종 실행39581407493도 SDK·Swift155·UI1·Python17·자산/캡처 성공이다. 실기기 성능·컬러 차트 촬영 검증은 미완료다.

다음 단계는 LUT로 표현할 수 없는 공간 기반 소프트 포커스·색수차·가로 빛 번짐을 공통 Metal 마감 패스에 추가하는 것이다.
