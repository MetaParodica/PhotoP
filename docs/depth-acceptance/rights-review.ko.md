# 배포 자산 권리·출처 점검

2026-11-16 KST. 소스 기준13567b2. 이 기록은 저장소 자산의 권리 근거·고지·무결성 확인이며 별도 법률 의견이나 제조사 인증이 아니다. 실제 사용자 사진/경쟁 결과의 촬영 동의는 평가 세트에 별도로 기록한다.

- 내장 모델은 Apple Core ML Depth Anything V2 **Small FP16** revision `cfef6f6f2a70783dedc0bfae40cecbc2052285d3`이다. upstream Small/Apple model card의 Apache-2.0 근거, 전문 LICENSE·NOTICE·모델3파일 hash를 `assets/depth-model/legal/manifest.json`에 고정했다. 비상업 제한이 있는 Base/Large/Giant 가중치를 포함하지 않았다. 새로운 외부 런타임/제3자 소스 코드를 복사하지 않았다.
- `python3 scripts/check_depth_model.py` 성공:3개 실제 모델 파일·고정 revision·Apache LICENSE hash·NOTICE 존재를 확인했다. legal manifest SHA256 `f19a678c9843c87f5d4a19c8fb93f87dd2f552ddc5d7ee2503d65b36e60c0173`, LICENSE `c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4`, NOTICE `ab64b65cf10d5b3b7b8b019d7dbc0286d372c0c067061d722d08d09eb0afd32d`.
- `python3 scripts/check_lut_bundle.py` 성공: 승인된5개 LUT 무결성 확인. manifest SHA256 `153c794026857f5dd32563f759ccd48cad1736e49ada14590a4252585b230658`.
- `python3 scripts/check_company_luts.py` 성공: 외부25개 파일 및 프로젝트 소유자가 이미 확인한 사용·상업 이용·재배포 권리 기록 유지. 사용자 확인을 독립 법률 감사로 바꾸어 주장하지 않는다. manifest SHA256 `7d539ac9f3ad54693de8f41dd89af2344c9d67043987dbba49ce7c8b86184f5f`.
- CI는 모델 컴파일 및 앱 내 legal/NOTICE.txt 포함을 추가 검사한다. 이 단계의 SDK 빌드 성공과 별개로 최종 번들 검사 결과를 Phase 기록에 남긴다. 새로운 모델/자산 revision을 넣으면 이 기록과 manifest 검사를 갱신한다.

현재 고정 자산의 기존 권리 근거를 다시 확인했으며 추가 사용자 승인 요청은 필요하지 않다. 전체 제품의 화질/성능 출시 인수는 실기기·사진 증거가 없어 아직 통과하지 않는다.
