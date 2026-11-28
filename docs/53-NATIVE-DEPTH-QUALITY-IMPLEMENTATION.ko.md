# 네이티브 심도 품질 2차 구현

2026-11-28 KST. [52 실행 계획](52-DEPTH-QUALITY-DEVELOPMENT-PLAN.ko.md)의 N0/N2 후속. 기준main7f0f6c0 및11/25 로컬N1을 보존해 `codex/native-depth-quality-20261128`에서 검증한다. 실제 기기 품질/열 인수와 아래 자동 검사를 구분한다.

## 구현

- **입력/정합:** NativePhotoDepthReader가 첨부 없음과 무효 심도를 구분하고 depth/disparity를 읽는다. DepthGeometry로8개 EXIF 방향·색상/깊이 해상도 대응을 검증하고 방향은 한 번 적용한다. 정규화된 회전·crop/미러 변환도 순수 정책으로 검사한다. 기존 AF/preview UI의 전체 변환을 교체하거나 이종 센서3D 재투영을 구현한 것은 아니다.
- **경계 정밀화:** native 사진에만 MPSImageGuidedFilter regression/reconstruction을 적용한다. 같은 사진의 LUT 이전 색상을 guidance로 사용하며 낮은 해상도 계수에서 최대1536px·2,097,152픽셀 이하의 지도를 만든다. 공개 MPS API 호출이며 외부 neural 모델/코드를 복사하지 않는다.
- **보수적 제약:** 동일 깊이의 상수 영역은 유지하고 추정 값은 국소 유효 관측 범위 안으로 제한한다. 원래 가장 가까운 셀이 결측이면 결측으로 남긴다. NaN/음수 추정은 원래 값으로 복귀하며, 단위나 원래 CoC 정규화 범위를 바꾸지 않는다. RGB가 같은 가림 경계·유리·머리카락의 정답을 이 필터만으로 해결한다고 보장하지 않는다.
- **초점:** 터치 주변의 다수 배경에 묻힌 얇은 물체라도 터치 깊이에 일치하는3개 이상 표본이 있으면 그 군집을 사용한다. 고립 spike는 초점을 고정하지 못하고 기존 중앙값으로 안전 복귀한다. 광학 AF/대상 identity의 전체 시간 안정화는 별도 후속이다.
- **저장/재편집:** refinement method·출력 지도 크기·원래 normalization bounds와geometry를 선택 metadata로 보존한다. 새 사진은 한 번 정밀화한 지도를 저장하고, 재편집은 모델/MPS를 다시 호출하지 않는다. 기존2/3/4 recipe의 선택 필드가 없는 경우도 유지한다. 기존 JPEG/원본을 덮어쓰지 않는다.
- **참조 렌더러:** 같은 색상·원래 disparity에 Apple 공개 depthBlurEffectFilter를 적용하는 adapter를 추가한다. 반환 필터의 aperture 지원과 미적용 focus를 명시하고, 미지원은nil로 보고한다. Apple Camera의 비공개 파이프라인이나 모든 조건의 동일 초점 비교로 표현하지 않는다. 기본 사용자 흐름을 바꾸는 대체 렌더러가 아니다.
- **자원:** refinement와 bounded GPU readback은 촬영 후 executor 전용이다. live/영상 프레임마다 실행하지 않는다. 원래N1 preview 예산과 critical 중지를 유지하며, 실제 발열 감소는 아직 측정하지 않았다.

원래 intrinsics/전체 calibration은 원본 사진에 남는다. 요약은 원래 첨부 좌표를 설명하며 리사이즈된 지도 좌표의 intrinsics로 직접 사용하지 않는다. guided 결과는 센서 직접 측정치가 아니라 `mps-guided-native-v1`로 구별한 파생 깊이다.

## 검증 진행

- Linux Swift6.0.3 공통173개 통과, Swift197파일 구문 검사·변경 형식 통과. 이번에 실제 실행했으며11/25의164개를 재인용한 수치가 아니다.
- 신규 순수9개: EXIF8방향/역변환·crop/미러·잘못된 geometry 거부·얇은 표면/고립 spike·상대 scale/offset·메모리 크기·국소 anchor/원래 scale·결측/NaN/취소·구형 metadata.
- 신규 iOS5개: MPS 경계 이동/상수 anchor·세로 방향·저장/재열기/재편집·synthetic HEIC8방향·Apple 참조 지원 조건. iPhone/Simulator·Metal 실행은 CI로 검증 중이며 결과 확정 전 성공으로 세지 않는다.
- CI에Xcode27.2를 실제`xcode-27` runner로 연결하고 심도 집중 선택에 새 테스트를 추가했다. 공식 image 확인과 실제 빌드 결과는 구분한다.

실제 iPhone15Pro/iOS27.2 화질·열·전체100장/10종 영상/3명 blind 인수는 미실행이다. N3 가시성 PSF·전체 고해상도alpha ROI 저장·시간/identity 추적 통합·영상 native stream은 아직 남아 있다. 이 변경을 전체 계획 완료나 DSLR 동급 화질 인수로 표시하지 않는다.
