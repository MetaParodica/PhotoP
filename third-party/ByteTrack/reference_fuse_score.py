# Reference only; not imported, bundled or executed by PhotoP.
# Source: FoundationVision/ByteTrack, d1bf0191adff59bc8fcfeaa0b33d3d1642552a99, yolox/tracker/matching.py
# MIT; copyright 2021 Yifu Zhang. See LICENSE.

def fuse_score(cost_matrix, detections):
    if cost_matrix.size == 0:
        return cost_matrix
    iou_sim = 1 - cost_matrix
    det_scores = np.array([det.score for det in detections])
    det_scores = np.expand_dims(det_scores, axis=0).repeat(cost_matrix.shape[0], axis=0)
    fuse_sim = iou_sim * det_scores
    fuse_cost = 1 - fuse_sim
    return fuse_cost
