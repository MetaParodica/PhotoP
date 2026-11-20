"""Run the pinned full EfficientTAM CPU path on three synthetic frames.

Use the isolated environment from scripts/probe_efficienttam_coreml.py.
This records interfaces and finite outputs, not tracking accuracy or phone speed.
"""
import argparse
import hashlib
import json
import pathlib
import subprocess
import sys
import time

SOURCE = "abcd061ebd3cc6e7527d152d75b890126aaa53f6"
WEIGHTS = "7d4d652a465f0081391050932f45d8a66768ccc99c8ea393ce8a5927e83f3b9b"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=pathlib.Path, required=True)
    parser.add_argument("--checkpoint", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    actual = subprocess.check_output(
        ["git", "-C", str(args.source), "rev-parse", "HEAD"], text=True
    ).strip()
    digest = hashlib.sha256(args.checkpoint.read_bytes()).hexdigest()
    if actual != SOURCE or digest != WEIGHTS:
        raise ValueError("Source or checkpoint differs from the pinned reference")
    sys.path.insert(0, str(args.source.resolve()))
    import torch
    from efficient_track_anything.build_efficienttam import build_efficienttam

    def shapes(value):
        if torch.is_tensor(value):
            return {"shape": list(value.shape), "dtype": str(value.dtype),
                    "bytes": value.numel() * value.element_size(),
                    "finite": bool(torch.isfinite(value).all())}
        if isinstance(value, dict):
            return {key: shapes(item) for key, item in value.items()}
        if isinstance(value, (tuple, list)):
            return [shapes(item) for item in value]
        return value

    torch.manual_seed(4)
    torch.set_num_threads(2)
    model = build_efficienttam(
        "configs/efficienttam/efficienttam_ti_512x512.yaml", str(args.checkpoint),
        device="cpu", hydra_overrides_extra=["++model.compile_image_encoder=false"]
    ).eval()
    report = {
        "scope": "Complete CPU reference; three synthetic frames, not quality/device validation",
        "sourceSHA": SOURCE, "checkpointSHA256": digest, "torch": torch.__version__,
        "coremlRuntimeExecuted": False, "deviceExecuted": False, "shippedInApp": False,
        "parametersByChild": {name: sum(p.numel() for p in module.parameters())
                              for name, module in model.named_children()},
        "frames": [], "moduleCalls": {},
    }
    for name in ["image_encoder", "sam_prompt_encoder", "sam_mask_decoder", "memory_encoder", "memory_attention"]:
        def capture(module, inputs, kwargs, output, name=name):
            report["moduleCalls"].setdefault(name, []).append(
                {"inputs": shapes(inputs), "kwargs": shapes(kwargs), "outputs": shapes(output)}
            )
        getattr(model, name).register_forward_hook(capture, with_kwargs=True)
    bank = {"cond_frame_outputs": {}, "non_cond_frame_outputs": {}}
    with torch.inference_mode():
        for index in range(3):
            frame = torch.rand(1, 3, 512, 512) * 0.1
            frame[:, :, 160:350, 150 + index * 8:330 + index * 8] = 0.8
            start = time.perf_counter()
            backbone = model.forward_image(frame)
            _, features, positions, sizes = model._prepare_backbone_features(backbone)
            points = {"point_coords": torch.tensor([[[256.0, 256.0]]]),
                      "point_labels": torch.tensor([[1]], dtype=torch.int64)} if index == 0 else None
            output = model.track_step(
                frame_idx=index, is_init_cond_frame=index == 0,
                current_vision_feats=features, current_vision_pos_embeds=positions,
                feat_sizes=sizes, point_inputs=points, mask_inputs=None,
                output_dict=bank, num_frames=3, run_mem_encoder=True,
            )
            bank["cond_frame_outputs" if index == 0 else "non_cond_frame_outputs"][index] = output
            report["frames"].append({"index": index,
                                     "cpuSecondsSinglePass": time.perf_counter() - start,
                                     "outputs": shapes(output)})
    assert len(report["moduleCalls"]["memory_attention"]) == 2
    assert len(report["moduleCalls"]["memory_encoder"]) == 3
    def assert_finite(value):
        if isinstance(value, dict):
            if "finite" in value:
                assert value["finite"], value
            for item in value.values():
                assert_finite(item)
        elif isinstance(value, list):
            for item in value:
                assert_finite(item)
    assert_finite(report)
    report["completeReferenceRan"] = True
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print("Full CPU reference: 3 finite frames; memory attention 2 calls, memory encoder 3 calls")


if __name__ == "__main__":
    main()
