# A. PhotoP 제품 기획서

작성 기준: 2026-10-21 KST. 제품 목표와 현재 구현을 분리한다. 본 문서는 첫 개발 기준이며 출시 품질 인증이 아니다.

## 제품 비전과 차별화

PhotoP는 iPhone의 촬영 제어, 원본 보존, 색감 설계, 합성 촬영, 구도 제안을 연결하는 전문 카메라다. Android는 별도의 네이티브 어댑터로 확장한다. iOS가 공통 플랫폼의 최저 기능에 묶이지 않도록 한다.

차별화의 핵심은 ① 렌즈·포맷·모드 조합별 지원 근거 표시 ② 프리뷰와 결과물이 공유하는 색관리 레시피 ③ 물리 셔터와 합성 시간을 구별하는 장노출 ④ 인물·건축·풍경별 제안형 가이드 ⑤ 원본+레시피+파생본 보관 ⑥ 출처·색공간·배포 권한을 추적하는 필터 카탈로그다. 이 항목은 검증할 제품 가설이며 현재 우월성이 입증된 기능은 아니다.

## 사용자 시나리오

| 사용자 | 상황과 조작 | 결과 / 성공 조건 |
| --- | --- | --- |
| 일반 사용자 | AUTO 진입 → 구도선 선택 → 촬영 | 원본 저장 성공을 명확히 알림; 저장 권한 거부 때도 원본 공유 가능 |
| 사진 애호가 | PRO → ISO·셔터를 함께 고정 → WB → 촬영 | 요청값과 실제 EXIF 비교; 렌즈 전환 때 범위 갱신 |
| 여행 촬영자 | FILM → 미리보기 → 강도 → 원본 동시 보관 | 같은 레시피로 원본을 다시 현상·내보내기 |
| 장노출 사용자 | 폭포/라이트트레일 → 총시간 → 삼각대 안내 → 촬영 | 센서 프레임 노출·실제 수집시간·채택/누락 프레임 수 표시 |
| 인물 촬영자 | 인물 수와 포즈 → 실루엣 → 헤드룸 제안 | 신뢰도 낮으면 제안 숨김; 강제 평가 없음 |
| 건축 촬영자 | 수직선·수평 확인 → 카메라 기울기 조절 | 검출선과 제안 표시; 원근 교정은 편집 단계에서 선택 |
| 영상 제작자 | 지원 포맷·FPS·Log → LUT 모니터링 → 녹화 | LUT 미적용 원본과 색공간 메타데이터 보존 |

## 기능 요구와 우선순위

P0는 최초 실기기 마일스톤, P1은 사진 기반 확장, P2는 고급 기능이다. 아래 요구는 모두 기기·구성 검증 조건을 따른다.

| 영역 | 명세 | 우선 / Phase | 현재 |
| --- | --- | --- | --- |
| 기본 사진 | 프리뷰·JPEG·전후면·물리 렌즈 선택·원본 파일·Photos | P0 / 1 | 코드 작성, 실기기 미검증 |
| 수동 노출 | 활성 포맷 ISO·노출시간 조회; AUTO와 ISO+셔터 동시 수동; AUTO EV | P0 / 1 | 기본 코드; 적용 완료/실제 측정값 표시 추가 필요 |
| 초점·WB | 수동 렌즈 위치, 자동 복귀; Kelvin/Tint→기기 게인 제한 | P0 / 1 | 기본 코드; 터치 AF·Lock·실측 판독 추가 필요 |
| 격자·수평 | 삼분할·수평계·각도·고급 격자 | P0~P1 / 1,5 | 삼분할만 작성 |
| 포맷 | HEIF/JPEG, Bayer RAW/DNG, ProRAW, 최대 지원 해상도 | P1 / 3 | JPEG·현재 포맷 최대 치수 요청만 작성 |
| 진단 | RGB/휘도 히스토그램, Zebra, 클리핑, 피킹·확대 | P1 / 3 | 미구현 |
| 보조 촬영 | AE/AF/WB Lock, 브래킷, 타이머, 버스트, 우선 노출 | P1 / 1~3 | 미구현 |
| LUT | 엄격한 cube 파서, 3D 샘플링, 프로파일, 강도·가져오기·검색·즐겨찾기 | P1 / 2 | 미구현; 번들 권한 검증만 작성 |
| 컬러 편집 | 노출·대비·명암·색온도·Tint·채도·Vibrance·Hue·HSL·커브·휠 | P1~P2 / 2,6 | 미구현 |
| 물성 효과 | Grain·Fade·Vignette·Bloom·Halation·Bleeding·CA·샤프닝·NR | P2 / 6 | 미구현 |
| 장노출 | Mean·Lighten 우선, 정렬·노이즈감소·중간보기·취소·재처리 | P1 / 4 | 미구현 |
| 추가 합성 | Median·HDR·동작 인식·고스트 제거·별 전용 정렬 | P2 / 4 이후 | 미구현 |
| AI 구도 | 인물·건물·풍경, 관절·실루엣, 선택적 평가 | P2 / 5 | 미구현 |
| 영상 | 지원 포맷/FPS/코덱, Log, LUT 프리뷰, scopes·오디오·안정화 | P2 / 7 | 미구현 |
| 편집·관리 | 버전 있는 레시피·원본 복원·프리셋·색관리 출력 | P1 / 2 이후 | 원본 보관만 작성 |
| Android | Camera2, Compose, 기기별 조합 확인 | P2 / 8 | 설계만 |

## 모드 정책

14개 목표 모드는 공통 엔진의 정책이다. AUTO/PRO/RAW는 노출·출력 선택, FILM은 컬러 레시피, PORTRAIT/ARCHITECTURE/LANDSCAPE는 가이드 정책을 더한다. LONG EXPOSURE/NIGHT/LIGHT TRAILS/STAR TRAILS/HDR은 프레임 수집·합성 정책이다. VIDEO/CINEMA는 스트림·코덱·색관리 정책이다. 초기 앱에는 PHOTO와 PRO 설정만 노출한다.

NIGHT는 Apple 기본 카메라 Night mode를 호출한다는 뜻이 아니다. 공개 API로 구현한 별도 합성 촬영이며 품질을 측정한다. PORTRAIT 가이드와 인물 심도 촬영도 별개 기능으로 표시한다.

## 경쟁 제품 기능 매트릭스

문헌 조사 기준, 앱 직접 조작·화질 비교는 미실시. `확인`은 연결된 공식 자료가 해당 기능을 명시함, `미확인`은 부재의 의미가 아니다. PhotoP 열은 목표이며 미완성이다. 버전과 구독·기기 조건을 후속 실사에서 고정한다.

| 제품 | 수동 사진 / RAW | 실시간 색감·LUT | 장노출 | 구도 / 전문 영상 | 검증 근거 |
| --- | --- | --- | --- | --- | --- |
| Halide | 수동 제어 확인; RAW 워크플로 확인 | Looks 확인; 범용 cube import 미확인 | 미확인 | 격자·피킹 확인; 영상 미확인 | [제작사](https://halide.cam/) |
| ProCamera | 수동·RAW·ProRAW 확인 | 편집 필터 확인; live LUT 미확인 | LowLight 기능과 장노출 구별 필요 | 브래킷 확인; 구도 AI 미확인 | [제작사](https://procamera-app.com/en/exposure-bracketing/) |
| Lightroom Camera | DNG·전문 카메라 확인 | 프로파일 편집 확인; live LUT 미확인 | 미확인 | 편집 워크플로 확인 | [Adobe](https://helpx.adobe.com/ro/lightroom-cc/using/capture-photos-mobile-ios.html) |
| Blackmagic Camera | 영상 수동 확인; RAW 사진 미확인 | LUT import·monitor/bake 선택 확인 | 미확인 | 피킹·Zebra·False Color·히스토그램 확인 | [사양](https://www.blackmagicdesign.com/products/blackmagiccamera/techspecs/W-APP-02) |
| Kino | 영상 앱; 수동 사진 미확인 | Instant Grade·원본 Log 선택 확인 | 미확인 | 영상 워크플로 확인 | [제작사](https://www.lux.camera/introducing-kino-pro-video-camera/) |
| Moment Pro Camera | 이번 조사에서 항목별 공식 확인 미완료 | 미확인 | 미확인 | 미확인 | 후속 확인 |
| Slow Shutter Cam | 수동 ISO 확인; RAW 미확인 | 미확인 | Motion Blur·Light Trail·Low Light 확인 | 타이머·intervalometer 확인 | [제작사 등록 설명](https://apps.apple.com/us/app/slow-shutter-cam/id357404131) |
| ReeXpose | 수동·Bayer DNG 확인 | 미확인 | Motion Blur·Light Trails 확인 | 히스토그램·피킹 확인 | [제작사](https://reeflexstore.com/en-gb/pages/reexpose) |
| VSCO / VSCO Capture | Capture의 사진 수동 제어 확인; RAW 미확인 | Capture live presets·강도 확인 | 미확인 | 영상 live presets; 영상 수동은 제한 명시 | [제작사](https://www.vsco.co/capture) |
| RNI Films | 제작사 기준 사진 편집 앱 | 필름 분류·grain·전후 비교 확인; live LUT 미확인 | 미확인 | 촬영 가이드 미확인 | [제작사](https://mobile.reallyniceimages.com/) |
| NOMO CAM | 세부 수동/RAW 미확인 | 클래식 카메라 에뮬레이션 확인 | 미확인 | 아날로그 조작 UX 확인 | [App Store 소개](https://apps.apple.com/us/story/id1464763919) |
| Dazz Cam (id1422471180) | 세부 수동/RAW 미확인 | 렌더링 profiles·grain 관련 변경 이력 확인 | 미확인 | 구도 AI 미확인 | [제작사 등록 설명](https://apps.apple.com/us/app/dazz-cam-vintage-camera/id1422471180) |
| Fujifilm Film Simulation | 전용 하드웨어 체계; 앱과 직접 동등 비교 불가 | 공식 Log용 LUT 일부 확인 | 카메라별 확인 필요 | Log 프로파일별 호환성 필수 | [공식 설명](https://shopusa.fujifilm-x.com/discover/what-are-fujifilm-gfx-eterna-55-s-3d-film-simulation-luts-/) |
| PhotoP 목표 | 기기별 제어·RAW | 관리형 LUT·비파괴 레시피 | 물리/합성 분리 | 온디바이스 장면 가이드·후속 영상 | 본 PRD; 검증 전 |

경쟁 기능의 단순 합계로 최고 품질을 주장하지 않는다. 동일 기기·렌즈·조도·장면·색관리 조건으로 촬영 결과와 성능을 비교해야 한다.

## UX와 측정 지표

다크 테마·큰 뷰파인더·하단 셔터·접이식 PRO·필터 썸네일을 기본으로 한다. 고급 도구는 사용자가 활성화한다. 색만으로 상태를 전달하지 않고 VoiceOver·Dynamic Type·최소 터치 영역을 검증한다. ISO·셔터 눈금은 로그 스케일을 쓴다.

성능 목표: 프리뷰 60 FPS, 효과+AI 30 FPS 이상. 목표 포맷에서 p95 프레임 처리시간과 드롭률을 함께 기록한다. 장노출의 메모리는 촬영시간 증가와 무관하게 상한을 유지해야 한다. 모든 수치는 장치별 측정 전 가설이다.

초기 제외: 클라우드 계정·SNS·서버 이미지 업로드·구독 결제·자체 ML 학습·Android UI의 선행 구현. 100개 이상 스타일은 품질과 권리를 통과한 독립 스타일 기준의 후속 목표이며 현재 수량은 0이다.
