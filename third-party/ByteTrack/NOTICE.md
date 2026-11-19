# ByteTrack score-fusion reference and Swift port

The reference function is copied from `FoundationVision/ByteTrack`,
`yolox/tracker/matching.py`, at the exact commit and line range recorded in
`docs/research/2026-11-19-video-depth-tracking-sources.json`.

Copyright (c) 2021 Yifu Zhang. MIT license; see LICENSE.

`reference_fuse_score.py` is an unexecuted research snapshot. PhotoP does not
import Python, NumPy, SciPy, lap or cython_bbox. The scalar expression
`1 - iou * confidence` is ported to the subject-association policy with bounds,
time/generation checks and loss handling implemented in PhotoP. This is not a
claim to ship the full ByteTrack tracker or detector. The MIT notice is retained
with the Swift port as well as this reference.
