# 차세대 심도 고도화 실행 계획 — 2026-11-20 KST

[감사42](42-COMPUTATIONAL-DEPTH-AUDIT.ko.md)와 [사용자 지시 원문](research/2026-11-20-depth-engine-directive.ko.md)을 따른다. 각 phase의 구현·실패·수정·검증은08 및 당일 일지에 누적한다.

1. **Phase0/1**: main SHA/CI·호출 경로·기준140 portable 확보. 기존 실제100장 acceptance gate는 그대로 유지. 합성 fixture는 실제 사진·기기 인수를 대체하지 않는다.
2. **Phase2**: 기존 signed layer/near coverage를 유지하면서 동일한 공간 가변 PSF를 CPU/Metal에서 검증한다. 선형·premultiplied 합성, 상수·점광원·halo·타일/원본 hash 회귀. 원형/다각형·주변부 변형은 실측 렌즈 복제가 아닌 독자 스타일.
3. **Phase3**: 기존 선택 매트의 확실한 전경/배경 seed를 보호하고 unknown 경계만 RGB 관측으로 보정한다. 얇은 구조/반투명 합성 fixture의 alpha/색 오차를 전후 비교한다. 외부 모델은 source/weights/변환 가능성 조사 후 실측 개선 없으면 앱에 추가하지 않는다.
4. **Phase4**: 기존 flow/affine 상태를 저장 영상에도 연결한다. 광도·대응·시간·가림 검증 실패 시 history 폐기, cut/취소 reset. VideoDepthAnything streaming 모델의 메모리/변환 제약과 실제 제품 채택을 구분한다.
5. **Phase5**: legacy3+독자6스타일, 원본 지도 보존 교정 stroke/undo/redo·진단 보기, 하위 recipe 복원, 영상 focus/f값 선택 보간. 추적 대상이 바뀌거나 실패한 경우 좌표를 섞지 않는다. 저장/취소·공유·64MP 회귀 확인.
6. **Phase6**: 전체 native/UI·portable/Python 및 기존 acceptance gate 실행. 실제100장·10종 영상·기기 trace·blind 비교가 없으면 최종 화질/실시간/ANE/열 인수는 미통과로 남긴다. 측정 없는 경쟁 우위·DSLR 동급 선언 금지.

## 조사와 외부 코드

DrBokeh-Src(24d96e4), BokehMe(8b3ed55), Bokehlicious(0d2c458), EfficientTAM(abcd061), VideoDepthAnything(4f5ae23), MatAnyone(e5ddc53), RVM(53d74c6)의 공식 소스를 고정하여 조사한다. 정확한 commit·URL·hash·복사 범위·조건은 연구 provenance에 기록한다. Dr. Bokeh의 실제 출판 정보와 BokehMe++ 존재/공개 구현은 공식 자료로 재확인하며 지시서 표기를 검증 없이 반복하지 않는다. 조사/다운로드는 앱 통합·CoreML 변환·실기기 실행과 다르다.

8bitSDR 영상은 유지한다. 10bitSDR은 출력 codec/pixel buffer/color metadata 검증이 필요한 별도 기술 검토이며 HDR/Log 도입하지 않는다. EfficientTAM은 실제 checkpoint/graph/상태 메모리 확인 전 채택하지 않는다. MatAnyone/RVM/SAM을 동시에 넣지 않는다. 기존 UI 후보 C1~3/수평계 등은 별도 백로그이고 심도 P0보다 우선하지 않는다.
