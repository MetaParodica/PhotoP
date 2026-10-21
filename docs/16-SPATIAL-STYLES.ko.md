# LUT 이외의 공간 스타일

## 구현 기능과 선택한 접근

LUT는 픽셀의 색을 변환하지만 주변 픽셀·화면 위치를 함께 읽는 효과를 표현할 수 없다. 기존 공통 Metal 필름 마감 패스에 아래 세 효과를 추가한다. 모두 0~100%로 독립 조절하고, 완전히 끄면 추가 샘플링을 생략한다.

| 효과 | 처리 | 제한 |
| --- | --- | --- |
| 소프트 포커스 | 중심+8개 이웃의 직선 RGB 평균과 원본 혼합 | 9탭 창작 디퓨전이며 Gaussian/피부 보정/초점 복원이 아님 |
| 색수차 | 화면 중심에서 방사 방향으로 R/B를 반대로 이동, G 유지 | 정규화된 위치 기반 효과. 실제 렌즈의 파장별 측정 모델이 아님 |
| 가로 빛 번짐 | 하이라이트를 8개 가로 오프셋에서 가중 누적 | 짧은 가로 광원 확산. 다단 피라미드 기반의 긴 광학 플레어나 회절 재현이 아님 |

기존 fade/vignette/bloom/halation·grain과 조합한다. 버퍼와 텍스처 경로는 동일한 파라미터·최종 계산 함수를 사용한다. 알파를 보존하고 경계는 clamp한다. 효과 반경은 이미지 긴 변을 기준으로 정규화하되 작은 해상도에서는 픽셀 반올림 차이가 생길 수 있다. 연산은 현재 SDR 색상 엔진 안의 창작 효과이며 물리적 광학/장면 선형 에너지 보존 모델이 아니다.

추가 CPU 픽셀 readback이나 외부 프레임워크 의존성을 만들지 않는다. 활성화한 효과만 이웃 샘플링을 수행한다. PSO와 기존 중간 텍스처 재사용 구조는 유지한다. 효과를 모두 켠 상태의 실제 iPhone FPS·발열·배터리는 아직 측정하지 않았다.

## 참고 소스와 라이선스

- [GPUImage3 GaussianBlur](https://github.com/BradLarson/GPUImage3/blob/main/Sources/GPUImage/Operations/GaussianBlur.swift), 코드 blob `e1e66a6ed97d71a7b7cb1a1438e0fc691d1e1712`, 라이선스 blob `3cedcf288327c1e89355f35e72d85c1aa94a03fe`: BSD-3-Clause. MPS Gaussian 경로와 clamp 처리를 조사했다. PhotoP는 버퍼/텍스처 공통 마감을 유지하기 위해 작은 독립 평균 필터를 선택했다.
- [KinoStreak](https://github.com/keijiro/KinoStreak), `Streak.cginc` blob `2077df1600c0ceff954d1fb70c75211e60817153`, 라이선스 blob `19c77b87fe737b08f1729eb524c2a65d2454c3ba`: MIT. 하이라이트 분리·가로 다운샘플·업샘플·합성을 조사했다. Unity 코드/자산을 복사하거나 프레임워크를 통합하지 않았다. PhotoP는 범위를 줄인 독립 8탭 효과를 구현했다.

## 새 프리셋 8종

Soft Lens, Night Streak, Vintage Optics, Dream Glass, Mist Light, Glow Portrait, Film Projector, Clear Star.

모두 PhotoP 자체 공간 프리셋이다. 색 변환 LUT 강도는 0이고, 내부 identity cube는 기존 가져오기·레시피 컨테이너를 재사용하기 위한 운반 데이터다. 실제 스타일은 Metal 마감·그레인 파라미터로 생성한다. LUT 전용 즐겨찾기는 공간 효과를 저장하지 않으므로 **전체 룩 프리셋**으로 저장하도록 안내한다. 공간 효과에 정적인 색상표를 LUT 미리보기처럼 붙이지 않는다.

자체 컬러 LUT 24개 + 공간 프리셋 8개 + 외부 크리에이티브 룩 27개 = **59개 룩**, 별도 기술 LUT 3개다. 확보한 외부 원본 파일은 기존 5개+신규 25개=30개다. 100개 이상은 여전히 개발 목표다.

## 파일·검증·다음 단계

- `FilmFinish.swift`, `FilmFinish.metal`: 세 효과, 48-byte Swift/Metal 파라미터, 구형 v3 마감 JSON의 새 필드 중립값 복원.
- `ProceduralLook.swift`: 독립된 8개 파라미터 프리셋.
- `FilmFinishControls.swift`, `FilmStylesView.swift`: 개별 슬라이더와 비 LUT 스타일 선택.
- `FilmFinishTests`: 257px 이미지에서 사진 버퍼/라이브 텍스처 출력 1 code value 이내 비교에 새 효과 포함.
- `SpatialLookTests`: 구형 레시피 호환, 각 효과의 공간 방향·채널·알파, 강도 0의 정확한 원본, 프리셋 재시작 및 편집 원본 보존·효과 복원.
- 촬영 화면의 기존 기본 격자를 구도 선택값 삼분할과 통일했다. UI 테스트가 삼분할→숨기기→삼분할을 실제 메뉴로 조작한다.

[최종 실행39581407493](https://github.com/MetaParodica/PhotoP/actions/runs/39581407493), 코드 `6c569e0ec22f0521899bfd6cb0a9aca7d296024e`: iPhone SDK·Swift155·UI1·Python17·소스/복사 앱 LUT30개 무결성·기본/구도 캡처가 모두 성공했다. Swift 테스트 skip0이며 사진/텍스처 경로는 모든 마감 효과를 켠 257px 이미지에서 1 code value 허용 오차를 통과했다. 다음 단계는 실제 iPhone의 프리뷰/편집 고해상도 비교, 장시간 성능 및 광원 장면별 품질 검증이다. 이번 변경으로 미지원 Log/HDR 촬영이나 실제 광학 기능을 제공한다고 표시하지 않는다.
