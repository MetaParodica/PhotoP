# Phase 3: RAW와 고급 촬영

기준일: 2026-10-21 KST. 구현 단위마다 자동 검증 성공 후 다음 단위로 진행한다. 실제 iPhone 검증은 별도 대기하며 성공으로 간주하지 않는다.

## 요구 기능과 판정

| 단위 | 구현 목표 | 자동 검증 | 실기기 대기 |
|---|---|---|---|
| RAW/DNG·ProRAW | 현재 output의 DNG pixel format 조회·분류, RAW 전용 요청, 원본 저장/공유 | 지원/실행 정책, container·delegate 구별·중복/누락, DNG bytes 보존 | 렌즈·기종별 실제 촬영, 외부 RAW 현상, EXIF 및 Photos |
| 노출·초점 모니터 | SDR preview RGB/휘도 histogram, Zebra, focus peaking | 합성 chart·edge 및 GPU/CPU 수치·overlay, 제한·프레임 수명 | 실제 색상/노출·초점·FPS·발열 |
| Exposure bracket | 장치 허용 범위의 서로 다른 노출 사진 저장 | 요청 범위·완료 수·순서·중복/누락·저장 실패 | 실제 bracket EXIF·복귀·중단·화질 |

## 공식 API 확인

- [Capturing photos in RAW and Apple ProRAW formats](https://developer.apple.com/documentation/avfoundation/capturing-photos-in-raw-and-apple-proraw-formats)
- [Capture and process ProRAW images, WWDC21](https://developer.apple.com/videos/play/wwdc2021/10160/)
- [isAppleProRAWEnabled](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/isappleprorawenabled)
- [isRawPhoto](https://developer.apple.com/documentation/avfoundation/avcapturephoto/israwphoto)
- [AVFileType.dng](https://developer.apple.com/documentation/avfoundation/avfiletype/dng)
- [maxBracketedCapturePhotoCount](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/maxbracketedcapturephotocount)
- [bracketSettings / sequenceCount](https://developer.apple.com/documentation/avfoundation/avcapturephoto/bracketsettings)

ProRAW는 configure 시 지원되는 경우 활성화한다. 변경된 렌즈마다 지원을 다시 확인하고 DNG에 대해 제공된 pixel format을 Bayer/ProRAW로 분류한다. 기종명·하드코딩한 pixel format으로 지원을 추정하지 않는다. ProRAW의 품질 우선 처리와 custom exposure의 speed 요구를 동시에 충족한다고 가정하지 않아 현재 ProRAW는 AUTO 노출로 제한한다. 이는 PhotoP 초기 구현 정책이며 모든 iOS API 조합의 불가능성을 주장하는 것이 아니다. Bayer RAW는 수동 노출을 허용한다. RAW와 live video output 동시 촬영은 검증 전 제한한다.

요청한 RAW만 전달받는다. delegate isRawPhoto와 TIFF/DNG container를 함께 확인하며 JPEG를 DNG로 대체 저장하지 않는다. 일반 사진은 기존 HEIF/JPEG codec 조회를 유지한다. RAW bytes는 재인코딩하지 않고 Documents/Originals와 Photos에 저장한다. DNG container 검증만으로 sensor 품질·ProRAW 계산 처리의 실현 여부를 검증했다고 주장하지 않는다. RAW 현상은 현재 SDR LUT 편집기와 별도 범위이며 DNG를 그 편집기에 전달하지 않는다.

## 추가 오픈소스 소스 검토

[IgnacioPro/iphone-raw](https://github.com/IgnacioPro/iphone-raw/tree/5603070b4ab0507c1a28ae20ad6bc3d6837d1b35), main revision `5603070b4ab0507c1a28ae20ad6bc3d6837d1b35`를 확인했다. 저장소 license metadata는 null이며 tree에서 LICENSE를 찾지 못했다. 라이선스 확인 필요로 유지하며 코드 복사·링크·배포 의존성 채택은 하지 않는다.

- `Sources/CameraKit/CaptureSessionService.swift`: RAW/ProRAW capability, payload, backend·serving 계약과 오류 모델 확인. `primaryData(for:)`는 요청 RAW가 없을 때 processed data로 fallback할 수 있어 PhotoP에서는 이 정책을 채택하지 않는다. PhotoP는 요청·isRawPhoto·파일 container 불일치를 오류로 처리한다.
- `Sources/CameraKit/LuminanceHistogram.swift`: bin count/sample count/시간 및 최대 bin 정규화를 표현하는 데이터 모델 확인. 이것만으로 실제 GPU 분석·성능을 검증했다고 간주하지 않는다.

앞서 검토한 MetalPetal·GPUImage3·BBMetalImage는 [09 문서](09-PHASE2-SOURCE-REVIEW.ko.md)에 기록했다. 이번 기능도 자체 native 처리 경로에 필요한 최소 코드를 독립 작성한다. 추가 라이브러리·LUT·모델 자산은 없다.

- [NextLevel](https://github.com/NextLevel/NextLevel/blob/2fa42500caf7edd7136d23b64d9ecb5684d93d07/Sources/NextLevel.swift), revision `2fa42500caf7edd7136d23b64d9ecb5684d93d07`: `capturePhoto()`의 codec 선택·quality prioritization·출력 delegate 연결 확인. 루트 MIT 원문 확인. 전체 프레임워크를 들여오면 기존 직렬 큐와 capture 상태 계층을 중복하므로 도입하지 않는다. RAW/브래킷이 이 경로에서 검증됐다고 확대 해석하지 않는다.
- [AVCamManual-Swift](https://github.com/ooper-shlab/AVCamManual-Swift/tree/685c940ad56ebe41702fdec293b4ad5b7c73d3eb), revision `685c940ad56ebe41702fdec293b4ad5b7c73d3eb`: CameraViewController의 `AVCapturePhotoBracketSettings` 구성과 별도 RAW/processed delegate, 렌즈 안정화 지원 검사 확인. `LICENSE.txt`는 2016 Apple sample code custom license이며 MIT로 분류하지 않는다. 오래된 sample-buffer API와 강제 `[0]` RAW 선택을 그대로 쓰지 않고 최신 AVCapturePhoto와 지원 목록 검증을 사용한다. 코드 복사 없이 API 사용 방식만 비교한다.


## RAW 단계에서 발견한 테스트 문제

합성 CFA DNG와 합성 linear DNG는 Simulator ImageIO에서 public.tiff·image count 0으로 인식되어, 최초 77개 테스트 중 2개가 실패했다. 동일 합성 데이터의 디렉터리는 생성 코드에서 검토했다. 특정 RAW decoder의 성공을 원본 보관 조건으로 삼지 않도록 DNG container 검사를 분리했다. 제한된 첫 TIFF IFD의 byte order·magic·offset·entry 수·중복 tag·DNGVersion·양수 치수를 검사하고 실제 RAW 여부는 AVCapturePhoto.isRawPhoto와 함께 확인한다. 전체 DNG conformance·센서 픽셀 현상 성공을 검증한 parser는 아니다. 합성 fixture는 sensor/ProRAW 샘플이라고 표시하지 않는다. 외부 RAW 편집기의 실제 촬영 DNG 검증은 계속 기기 대기다.


## 노출·초점 모니터 처리 계약

- 입력: 기존 live SDR 변환 후, creative LUT 전의 encoded sRGB texture. RGB와 휘도를 64 bins로 계산한다. 휘도는 명시한 (54R+183G+19B)/256 근사이며 센서 선형 광량이 아니다.
- Histogram: 긴 변 최대 256 표본 격자, 1개 in-flight, 초당 최대 4회. 1KiB counts만 GPU 완료 후 복사하고 이미지 픽셀 readback은 하지 않는다. zero-alpha 표본은 제외한다.
- Zebra: SDR 최대 RGB 채널이 사용자가 정한 50~100% 임계값 이상인 위치에 줄무늬 표시. RAW 센서 포화도 측정은 아니다.
- Peaking: 정규화 Sobel 명암 경계를 빨간색으로 표시하고 threshold를 조절한다. 경계 표시가 피사체 초점의 정답을 뜻하지 않는다.
- 출력: LUT 처리 화면 위에 보조 표시만 합성한다. 캡처 원본에는 굽지 않는다. 보조 texture는 재사용하며 기존 source/processed 포함 최대 3개 1024px texture를 사용한다. RAW·렌즈 전환·터치 AF/AE와의 동시 사용은 현재 제한한다.

## 노출 브래킷 처리 계약

`AVCapturePhotoBracketSettings`로 일반 HEIF/JPEG 3장을 요청한다. 현재 실제 장치 EV 중심값에 ±0.5/1/2 EV를 더한 모든 값이 장치 범위에 들어야 한다. 범위를 벗어난 값을 clamp해 같은 노출 3장으로 대체하지 않는다. 현재 output의 maxBracketedCapturePhotoCount를 조회하며, AUTO 노출·RAW 끔·live 끔에서만 실행한다. cross-bracket 렌즈 안정화는 지원 시에만 켠다. 브래킷은 speed 우선이며 단일 사진은 기존 품질 정책을 유지한다.

request ID·1-based sequence·요청 bias·실제 container·RAW flag·예상 총수·중복/누락을 검증한다. 처리 오류는 최종 didFinishCapture까지 보관해 캡처 중 새 요청을 받지 않는다. 최종 콜백 누락에 대비한 제한 시간은 현재 물리 노출시간과 프레임 수를 고려한다. timeout·중단 시 작업을 실패시키고 늦은 콜백은 ID로 거부한다. 실제 기기 콜백 순서·timeout 복구는 기기 대기다.

원본은 Documents/Originals에 각각 bytes 그대로 저장하고, BracketGroups의 JSON에 파일명·SHA256·요청 EV를 기록한다. 일반 파일 저장 오류는 이번에 생성한 원본만 정리한다. 사진 보관함은 모든 원본을 하나의 Photos 변경 작업으로 추가한다. Photos 저장 실패 시 앱 원본과 공유 경로를 보존하며 재시도도 묶음 전체에 적용한다. OS 강제 종료 직전 다중 파일 쓰기의 crash-atomic 복구/시작 시 orphan 스캔은 미구현이다. 파일 I/O 오류 시의 정리와 구별한다. 브래킷 HDR 합성·RAW 브래킷은 후속이다.

## 참고 규격 추가

- [Adobe DNG specification 1.7.1](https://helpx.adobe.com/content/dam/help/en/photoshop/pdf/DNG_Spec_1_7_1_0.pdf): TIFF 확장과 IFD0의 BYTE[4] DNGVersion tag 50706 확인. 코드·SDK 반입 없이 제한적 container 식별만 독립 구현.
- [Apple bracketed photo sequence](https://developer.apple.com/documentation/avfoundation/capturing-a-bracketed-photo-sequence): AUTO bias, HEVC 예시, lens stabilization, 여러 delegate 결과 처리 확인.


## 실행 결과

RAW [CI 39522296909](https://github.com/MetaParodica/PhotoP/actions/runs/39522296909) 78개 → 모니터 [CI 39522806940](https://github.com/MetaParodica/PhotoP/actions/runs/39522806940) 83개 → 브래킷 [CI 39538033899](https://github.com/MetaParodica/PhotoP/actions/runs/39538033899) 90개 Swift 테스트를 각각 통과했다. 각 run의 iPhone SDK build·Python 7개·권한 설명·LUT bundle 정책 검사도 성공했다. 실제 기기 검증은 미수행이다. 파일별 변경·실패/수정·제약·다음 단계는 07/08 문서에 기록했다.
