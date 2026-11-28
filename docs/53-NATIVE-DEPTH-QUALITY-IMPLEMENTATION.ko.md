# 네이티브 심도 품질 2차 구현

2026-11-28 KST. [52 실행 계획](52-DEPTH-QUALITY-DEVELOPMENT-PLAN.ko.md)의 N0/N2 후속. 기준main7f0f6c0 및11/25 로컬N1을 보존해 `codex/native-depth-quality-20261128`에서 검증한다. 실제 기기 품질/열 인수와 아래 자동 검사를 구분한다.

## 구현

- **입력/정합:** NativePhotoDepthReader가 첨부 없음과 무효 심도를 구분하고 depth/disparity를 읽는다. DepthGeometry로8개 EXIF 방향·색상/깊이 해상도 대응을 검증하고 방향은 한 번 적용한다. 정규화된 회전·crop/미러 변환도 순수 정책으로 검사한다. 기존 AF/preview UI의 전체 변환을 교체하거나 이종 센서3D 재투영을 구현한 것은 아니다.
- **경계 정밀화:** native 사진에만 MPSImageGuidedFilter regression/reconstruction을 적용한다. 같은 사진의 LUT 이전 색상을 guidance로 사용하며 낮은 해상도 계수에서 최대1536px·2,097,152픽셀 이하의 지도를 만든다. 공개 MPS API 호출이며 외부 neural 모델/코드를 복사하지 않는다.
- **보수적 제약:** 동일 깊이의 상수 영역은 유지하고 추정 값은 국소 유효 관측 범위 안으로 제한한다. 원래 가장 가까운 셀이 결측이면 결측으로 남긴다. NaN/음수 추정은 원래 값으로 복귀하며, 단위나 원래 CoC 정규화 범위를 바꾸지 않는다. RGB가 같은 가림 경계·유리·머리카락의 정답을 이 필터만으로 해결한다고 보장하지 않는다.
- **동일색 경계 보호:** 강한 두 표면 사이에서 관측되지 않은 중간 깊이를 만드는 guided 평균을 native 값으로 되돌린다. MPS 회귀계수에 RGB 단서가 있는 영역은 guided 추정을 유지한다. 완만한 경사면 보간은 유지하며 이 규칙을 하드웨어 confidence/확률로 표현하지 않는다. 순수 회귀에서2/0.2 사이에1.1의 가상 면을 만들던 실패를 먼저 재현했고 별도GPU 동일색 사례를 추가했다.
- **초점:** 터치 주변의 다수 배경에 묻힌 얇은 물체라도 터치 깊이에 일치하는3개 이상 표본이 있으면 그 군집을 사용한다. 고립 spike는 초점을 고정하지 못하고 기존 중앙값으로 안전 복귀한다. 광학 AF/대상 identity의 전체 시간 안정화는 별도 후속이다.
- **저장/재편집:** refinement method·출력 지도 크기·원래 normalization bounds와geometry를 선택 metadata로 보존한다. 새 사진은 한 번 정밀화한 지도를 저장하고, 재편집은 모델/MPS를 다시 호출하지 않는다. 기존2/3/4 recipe의 선택 필드가 없는 경우도 유지한다. 기존 JPEG/원본을 덮어쓰지 않는다.
- **참조 렌더러:** 같은 색상·원래 disparity에 Apple 공개 depthBlurEffectFilter를 적용하는 adapter를 추가한다. 반환 필터의 aperture 지원과 미적용 focus를 명시하고, 미지원은nil로 보고한다. Apple Camera의 비공개 파이프라인이나 모든 조건의 동일 초점 비교로 표현하지 않는다. 기본 사용자 흐름을 바꾸는 대체 렌더러가 아니다.
- **편집 반응성:** 저장 지도보다 작은768px 편집 프리뷰용 grid를 교정마다 한 번 캐시한다. 최종 저장에는 원래 해상도의 정밀화 지도를 계속 사용한다. stencil 국소 범위도 native 셀마다 한 번 계산해 여러 파생 픽셀에서 재사용한다.
- **자원:** refinement와 bounded GPU readback은 촬영 후 executor 전용이다. live/영상 프레임마다 실행하지 않는다. 원래N1 preview 예산과 critical 중지를 유지하며, 실제 발열 감소는 아직 측정하지 않았다.

원래 intrinsics/전체 calibration은 원본 사진에 남는다. 요약은 원래 첨부 좌표를 설명하며 리사이즈된 지도 좌표의 intrinsics로 직접 사용하지 않는다. guided 결과는 센서 직접 측정치가 아니라 `mps-guided-native-v3`로 구별한 파생 깊이다. 기존v1/v2 파생 지도도 읽을 수 있다.

## 검증 결과

검증 앱 소스는 `139c5d1`, 수정한 CI 선택기는 `66bf20d`다. 두 커밋의 `ios`·`Package.swift`는 동일하다. 기능/CI를 포함한 `66bf20d`를 main에 정상 fast-forward push하고 원격 ref도 확인했다. 이 문서의 최종 정리는 앱·모델·테스트·CI를 변경하지 않는다.

| 환경·실행 | 실제 결과 |
|---|---|
| [Xcode26.3 전체46140950741](https://github.com/MetaParodica/PhotoP/actions/runs/46140950741), 앱139c5d1 | **success**. iPhone/Simulator 빌드·unit434개 중433통과/기존Flow1skip·LUT18·UI18 |
| [Xcode27.2 전체46142012643](https://github.com/MetaParodica/PhotoP/actions/runs/46142012643), CI66bf20d/앱139c5d1 | **success**. SDK/Simulator27.2·iPhone18Pro 선택을 로그로 확인. iPhone/Simulator 빌드·unit434개 중433통과/Flow1skip·LUT18·UI18 |

각 환경의 신규 GPU/HEIC/저장6개는 모두 실제 통과했다. unit/LUT/UI 원시 로그와 XCTest summary의 수치·전체 결론을 직접 대조했다. native 합계는 각452개 중451통과/기존Flow1skip이며 UI18개는 별도다. 실사 화질 인수 수치가 아니다.

- 직접 Linux 실행: Swift6.0.3 공통178개/0실패, Python41개/0실패(선택기7개 포함), Swift197파일 구문 검사·변경 형식 통과.
- 신규 순수14개: EXIF8방향/역변환·crop/미러·잘못된 geometry 거부·얇은 표면/고립 spike·상대 scale/offset·크기 상한·국소 anchor/원래 scale·결측/NaN/취소·구형 metadata·표시 지도 축소 시 범위 보존·색 단서/동일색 경계 보호.
- 신규 iOS6개: MPS 경계 이동/상수 anchor·세로 방향·저장/재열기/재편집·synthetic HEIC8방향·Apple 참조 지원 조건·동일색 앞뒤 표면의 가상 중간 면 방지.
- [검증 근거 JSON](research/2026-11-28-native-depth-quality-validation.json)에 소스 fingerprint·실행 SHA·중간 실패·CPU probe 범위를 보존했다. 상세 이력은 [08의70절](08-STEP-VALIDATION.ko.md#70-네이티브-심도-품질-구현반복-검증--2026-11-28)과 [당일 일지](development-log/2026-11-28.md)를 따른다.

## 실패와 수정

v2는 동일색 경계의 가상 중간 면을 막았지만, 실제 GPU의 강한색 경계2개에서 좋은 guided 추정까지 제거했다. MPS RGB 회귀계수의 구조적 단서를 사용하는v3로 수정했고 기존 `>0.7` 조건과 동일색 보호를 모두 유지해 재검증했다. 이 계수는 센서 confidence/확률이 아니다.

이전27.2 전체 실행은35분 job 상한으로 취소됐고, 종료 전 뷰파인더 배치·장노출 입력2케이스/3assertion 실패도 있었다. 기존 최대 버전 선택식은 표준27.2 대신 engineering27.2.19.4/iPhone Duo를 골랐다. SDK 일치 표준 Pro를 선택하도록 수정했으며, 표준27.2의 최종 전체 실행에서 해당 두 UI 케이스가 모두 통과했다. engineering Duo 호환 문제의 원인을 확정하거나 앱 UI를 수정했다고 표시하지 않는다.

## CPU 작업량 점검

실제 production 순수 제약 코드5파일을 Swift6.0.3 `-O`로 직접 컴파일해768×576→1536×1152 그리드로3회 실행했다. Linux x86_64에서0.1464/0.0750/0.0735초, 해당 probe 프로세스 peakRSS46,608KiB였다. **v2 CPU 단계만의 synthetic 결과**로 MPS·디코딩·export·v3 coefficient readback을 제외한다. iPhone 처리 시간·앱 메모리·발열 감소로 환산하지 않는다.

## 남은 범위

실제 iPhone15Pro/iOS27.2 화질·열·전력·AF, 동일 입력 PhotoP/Apple 실사 비교 및100장/10종 영상/3명 blind 인수는 미실행이다. N3 가시성 PSF·전체 고해상도 alpha ROI 저장·시간/identity 추적 통합·영상 native stream·실험실 모델의 반복 초기화 비용은 후속이다. 이 변경을 전체 계획 완료나 DSLR 동급 화질 인수로 표시하지 않는다.

전체27.2 회귀 재실행: `gh workflow run ios.yml --ref main -f xcode=27.2 -f test_scope=all`.
