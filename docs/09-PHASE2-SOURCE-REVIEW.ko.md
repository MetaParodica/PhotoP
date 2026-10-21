# Phase 2 실제 소스 검토 및 구현 결정

확인일: 2026-10-21. 초기 26개 후보 실사표는 [03 문서](03-OPEN-SOURCE-AUDIT.ko.md)에 유지한다. 이번 추가 실사는 Phase 2에 직접 관련되는 4개 프로젝트의 실제 구현 파일과 라이선스를 대상으로 한다. 전체 저장소·모든 의존성·모든 자산의 권리 검토를 완료했다는 뜻은 아니다.

| 프로젝트·고정 revision | 확인한 실제 기능·파일 | 언어·플랫폼·라이선스 | 유지보수 근거 | PhotoP 적용 판단·난이도·우선순위 |
|---|---|---|---|---|
| [MetalPetal](https://github.com/MetalPetal/MetalPetal/tree/f9b78897bd4214bb097f352a1bde0a4f4a1e2ddb) | `Frameworks/MetalPetal/Filters/MTIColorLookupFilter.m`: square/strip/3D LUT 구분, dimension 검증, intensity 전달, 재사용 pipeline kernel, 2D→3D 변환 | ObjC·Metal·Swift / Apple / 루트 MIT 원문 확인 | master HEAD commit 2023-02-21. 다른 branch/release의 최신 여부는 이번 범위 밖 | LUT 표현·검증과 GPU 실행 책임 분리 참고. 현재의 작은 native Metal 경로 유지; 프레임워크 미도입. 통합 중간, 참고 P1 |
| [GPUImage3](https://github.com/BradLarson/GPUImage3/tree/84466fc344e1220238c1c07e94e91207caaabe51) | `Sources/GPUImage/Operations/LookupFilter.metal`: 64단계 blue slice를 512px atlas에서 선택하고 보간; intensity 및 alpha 보존 | Swift·Metal / Apple / `License.txt` BSD-3-Clause 원문 확인 | main HEAD commit 2024-02-19. repo pushed_at 2024-07-25는 HEAD commit 날짜와 구별 | 고정 atlas 가정은 임의 크기 .cube에 부적합. 보간·강도·alpha 계약 비교에 사용. 자체 Float buffer trilinear 유지. 통합 중간, 참고 P1 |
| [BBMetalImage](https://github.com/Silence-GitHub/BBMetalImage/tree/4313f835dab00c225ede1111679c7bae2f0bb8a2) | `BBMetalImage/BBMetalImage/BBMetalLookupFilter.metal`: compute texture 경계 검사, 64단계 atlas, linear sampler, strength mix | Swift·Metal / iOS / 루트 MIT 원문 확인 | master HEAD commit 2021-10-25. repo pushed_at 2022-10-10과 구별 | 경계 검사·texture compute 구조 참고. 사진/live 경로 공통 함수와 alpha 검증을 독립 구현. 통합 낮음~중간, 참고 P1 |
| [darktable](https://github.com/darktable-org/darktable/blob/7e99c8c703329e35252a3bd54d7744f63969252b/src/iop/grain.c) | `src/iop/grain.c`: Lab 기반 simplex 다중 octave, 해상도 독립 좌표, 축소 필터링, midtone bias, 이전 recipe migration | C / desktop / 파일 헤더 GPL-3.0-or-later 확인 | master HEAD commit 2026-10-20 | 좌표·seed·중간톤 반응·recipe 호환성을 설계 검토 항목으로 채택. GPL 코드를 복사하거나 링크하지 않음. 물리 모델·simplex·LUT 구현 미채택. 직접 이식 높음, 설계 참고 P1 |

## 구현 선택

- **의존성 및 코드 복사:** 추가 runtime 의존성 0개, 외부 코드 복사 0개. PhotoP의 기존 임의 dimension 3D cube 파서·trilinear CPU/Metal 경로를 확장한다. 향후 MetalPetal 채택은 전체 그래프의 실제 이득을 측정한 뒤 별도로 결정한다.
- **기본 그레인:** 독립 작성한 정수 해시 기반 2D value noise를 사용한다. 단색 입자이며 LUT mix 이후 encoded sRGB에서 적용한다. 중간톤에서 강하고 검정·흰색에서 약해지는 유한 envelope, 0~100% 독립 강도, UInt32 seed를 제공한다. 특정 필름·은염 물성을 측정해 재현한 모델로 표시하지 않는다.
- **재현:** 이미지 긴 변을 512개 noise cell로 정규화한다. 같은 seed와 정규화 위치는 같은 noise를 만든다. 1024px 미리보기와 고해상도 export는 같은 연속 noise field를 서로 다른 픽셀 중심에서 샘플링한다. 축소 리샘플링·JPEG 손실 때문에 서로 다른 해상도의 byte 일치를 보장하지 않는다. 같은 해상도 buffer/texture는 채널당 1/255 허용 오차로 비교한다.
- **실시간 경로:** 매 프레임 texture 재사용과 1개 in-flight 정책 유지. 시간에 따라 seed를 변경하지 않아 깜박임을 피한다. 움직이는 실제 필름 영상 입자 모델은 이후 범위다.
- **레시피:** seed·강도·알고리즘 version을 명시해 다시 연 뒤 재처리한다. 기존 version 1은 grain 0으로 읽는다. 새로운 version이나 알 수 없는 색 프로파일은 임의로 추정하지 않는다.

## 자산·라이선스 경계

위 저장소의 샘플 LUT PNG, 필름 프로파일, 데모 사진은 가져오지 않았다. 소스코드의 MIT/BSD 표시만으로 별도 자산의 상업 배포 권한을 판단하지 않는다. darktable은 설계 비교에만 사용한다. 사용자 import LUT는 앱 내부 문서이며 배포 번들에 포함하지 않는다. 현재 번들 LUT는 0개다. 100개 이상의 스타일 라이브러리는 Phase 6 목표로 남아 있다.

## 검증 한계

위 표의 구현 주장은 링크한 revision의 코드·라이선스 원문을 직접 읽어 확인했다. 해당 외부 프로젝트를 iPhone에서 빌드하거나 성능 비교하지 않았다. PhotoP 자동 테스트와 기기 테스트는 [단계 검증 기록](08-STEP-VALIDATION.ko.md)에 별도로 남긴다. 전체 26개 후보의 심층 소스·전이 의존성·자산 라이선스 검토는 계속 필요하다.
