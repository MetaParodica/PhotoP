# Experimental photo selection

PhotoP includes the image encoder and initializer from **EdgeTAM**, converted to
Core ML by Jutsu Studio. This is a photo segmentation initializer, not the full
video tracker or an optical-alpha matting model. PhotoP's Swift adapter, opt-in
policy, saved recipe handling and rendering integration are implemented here.

- Original: <https://github.com/facebookresearch/EdgeTAM>, revision
  `7711e012a30a2402c4eaab637bdb00a521302c91`.
- Conversion: <https://github.com/jutsuhq/edgetam-coreml>, inspected revision
  `3c36c37f93a3106375aa33c14fd7ec426b9e1fa9`.
- Actual redistributed artifact: `v1.2/edgetam-coreml-v1.2.zip`, SHA-256
  `9c35c1b6667a0dd80b093bbc20747628f304133ad2a531de049307beb3ae1401`.
  The inspected source revision is recorded separately from the release artifact;
  it is not asserted to have generated the release byte for byte.
- `EdgeTAMVideoImageEncoder.mlpackage` and `EdgeTAMVideoInitializer.mlpackage`
  are renamed to `ExperimentalPhotoEncoder.mlpackage` and
  `ExperimentalPhotoInitializer.mlpackage`. Encoder and all weight bytes are unchanged.
  PhotoP exposes the initializer’s unchanged FP32 `input_93`/`hyper_in`
  tensors and reconstructs the same terminal exact GELU and linear mask product with native vForce/vDSP.
  The release returned zero masks on the tested Core ML CPU runtime. Original
  and derived specification hashes, reproducible script and method are recorded
  in the manifest; this is an output-graph adaptation, not retrained weights.
- The original Apache-2.0 LICENSE and NOTICE, with PhotoP's redistribution scope,
  are retained under
  [ExperimentalDepthLegal](../../assets/experimental-depth/ExperimentalDepthLegal/NOTICE).
  The six package-file hashes and rights-file hashes are in
  [manifest.json](../../assets/experimental-depth/ExperimentalDepthLegal/manifest.json).
  Xcode compiles the ML Program models for the iOS18+ app; native runtime checks
  are separate from source hash checks. No manufacturer endorsement is claimed.

No memory encoder, propagator or new streaming depth model is included in this
photo-selection resource group. MatAnyone2 is recorded separately under
`third-party/MatAnyone2Kit` and `assets/experimental-matte`. Existing Depth Anything V2/Vision features retain their
own implementation and records.

## Reference photograph for tests

`ios/PhotoPTests/Fixtures/experimental-astronaut.png` is the photograph of NASA
astronaut Eileen Collins distributed by scikit-image:

- [Pinned image](https://raw.githubusercontent.com/scikit-image/scikit-image/v0.19.0/skimage/data/astronaut.png).
- [Source description](https://github.com/scikit-image/scikit-image/blob/v0.19.0/skimage/data/_fetchers.py),
  `astronaut()`: NASA Great Images database, “No known copyright restrictions,
  released into the public domain”, original link <https://flic.kr/p/r9qvLn>.
- 791,555 bytes; SHA-256
  `88431cd9653ccd539741b555fb0a46b61558b301d4110412b5bc28b5e3ea6cb5`.
- Used for actual model I/O, selected-mask, serialization and original-preservation
  regression. No ground-truth alpha/depth is supplied; it is not a quality or
  device-performance benchmark and does not satisfy the 100-photo acceptance gate.
