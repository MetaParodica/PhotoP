# 필름/LUT 출처와 품질 관리

확인일: 2026-10-21 KST. 제공 사실과 앱 재배포 권한, 입력/출력 프로파일을 각각 확인한다. 아래는 공식 웹페이지를 읽은 조사 결과이며 다운로드한 LUT 파일을 모두 검증한 목록이 아니다.

| 출처 | 실제 확인 | 입력·권리·채택 상태 |
|---|---|---|
| [ARRI Color FAQ](https://www.arri.com/en/learn/camera-systems/image-science/color-faq) / [Technical downloads](https://www.arri.com/en/learn/camera-systems/technical-downloads) | LogC3 Generator·LogC4 package와 look library 안내 | Log 입력 기술 LUT를 현재 sRGB creative slot에 직접 쓰지 않음. 파일별 권리/배포 승인 미확인, 미번들 |
| [Sony LUT Library](https://pro.sony/ue_US/technology/professional-video-lut-look-up-table) | Sony look profiles·s709·BURANO looks와 별도 third-party collection을 구분해서 제공 | Sony 제작과 제3자 제작을 구분. 무료 제공 문구가 app redistribution 승인을 뜻한다고 판단하지 않음. 파일별 profile/rights 추가 확인, 미번들 |
| [Fujifilm 3D-LUT](https://www.fujifilm-x.com/en-us/support/download/lut/) | 모델별 cube zip 안내, GFX ETERNA55 v1.10 (페이지 표기 2026-04-16) 등 | F-Log 계열/모델별 기술 문서 필요. 모든 사진 Film Simulation이 sRGB 무료 재배포 LUT로 공개되었다고 확대 해석하지 않음. 미번들 |
| [Panasonic V-Log conversion](https://av.jpn.support.panasonic.com/support/global/cs/dsc/download/lut/index.html) | VLog_to_V709_forV35_EN.zip 제공 안내 | V-Log 변환용. 현재 sRGB creative profile과 구분. app 재배포 승인 미확인, 미번들 |
| Kodak/Leica/Agfa/Ilford/Polaroid 및 기타 후보 | 초기 후보 조사표 유지 | 특정 유명 film의 공식 LUT/개별 재배포 권리는 추가 확인 필요. 비공식 에뮬레이션을 공식 자산으로 이름 붙이지 않음 |
| hald-clut·Natron clut·PoLUT 등 | 초기 조사 및 11 문서 참조 | 개별 asset 출처·license·copyright·상업 재배포 검토 전 commercial bundle 미채택 |

새 자체 프로파일은 측정한 필름/유제 모델이 아니라 PhotoP의 독립적인 창작 스타일이다. 저작자·source ID·revision·canonical cube SHA256·sRGB input/output·강도·credit·배포 구분을 기록한다. 미리보기는 합성 색상 chart이며 타사 사진을 쓰지 않는다.

자동 평가: cube parse·finite/range·gray ramp·각 프로파일 구별·단색 채널 일치·피부색 chart 수치·CPU/Metal 및 내보내기 재현. 시각 평가: 실제 피부·야경·풍경·high-chroma 사진의 색·톤·banding·halo를 실기기에서 검수한다. 수치 통과가 최종 미학적 품질 승인이나 Kodak/Fujifilm 등의 실측 재현을 뜻하지 않는다.


추가 채택: [slaycamera/luts 고정 revision](https://github.com/slaycamera/luts/tree/a1709044efe115640dde1dee17d4185fc059af0d)의 원본5개는 LUT 자체 CC BY4.0·credit/share 조건과 모든 RGB행/해시를 검토해 포함했다. 입력/출력 프로파일은 upstream 미기재이므로 PhotoP sRGB 가정을 명시하고 적용 확인을 요구한다. 이 승인 범위를 위의 다른 브랜드 자료로 확대하지 않는다. 자체 스타일은24종으로 확대했고 외부5개와 구분한다. 자산/권리/색상·JPEG attribution 검증은 [13](13-PERFORMANCE-CAPTURE-LOOKS.ko.md)을 따른다.
