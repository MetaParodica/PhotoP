#!/usr/bin/env python3
"""Reproducible encoder-only conversion probe, never installs or ships a model.

Use an isolated environment with torch2.5.1+cpu, torchvision0.20.1+cpu,
coremltools8.3, hydra-core, iopath, timm1.0.12. Supply the pinned upstream checkout
and verified checkpoint. Linux conversion is not Core ML runtime/ANE validation.
"""
import argparse
import hashlib
import json
import pathlib
import subprocess
import sys
import time

SOURCE = "abcd061ebd3cc6e7527d152d75b890126aaa53f6"
CHECKPOINT = "7d4d652a465f0081391050932f45d8a66768ccc99c8ea393ce8a5927e83f3b9b"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=pathlib.Path, required=True)
    parser.add_argument("--checkpoint", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    report = {"sourceSHA": SOURCE, "checkpointSHA256": CHECKPOINT, "scope": "image-encoder-only-fixed-512",
              "coremlPackageWritten": False, "fullMaskTrackerConverted": False,
              "runtimeParityVerified": False, "aneVerified": False, "shippedInApp": False, "torchCompileDisabledForExport": True}
    try:
        actual = subprocess.check_output(["git", "-C", str(args.source), "rev-parse", "HEAD"], text=True).strip()
        if actual != SOURCE or hashlib.sha256(args.checkpoint.read_bytes()).hexdigest() != CHECKPOINT:
            raise ValueError("Upstream checkout or checkpoint does not match pinned source")
        sys.path.insert(0, str(args.source.resolve()))
        import torch
        import coremltools as ct
        from efficient_track_anything.build_efficienttam import build_efficienttam
        torch.set_num_threads(2)
        torch.manual_seed(0)
        model = build_efficienttam("configs/efficienttam/efficienttam_ti_512x512.yaml", str(args.checkpoint), device="cpu",
                                   hydra_overrides_extra=["++model.compile_image_encoder=false"])
        report["totalParameters"] = sum(p.numel() for p in model.parameters())
        report["encoderParameters"] = sum(p.numel() for p in model.image_encoder.parameters())

        class Encoder(torch.nn.Module):
            def __init__(self, encoder):
                super().__init__()
                self.encoder = encoder

            def forward(self, image):
                value = self.encoder(image)
                return tuple(value["backbone_fpn"] + value["vision_pos_enc"])

        wrapper = Encoder(model.image_encoder).eval()
        example = torch.rand(1, 3, 512, 512)  # graph fixture, not quality evidence
        with torch.no_grad():
            start = time.perf_counter()
            outputs = wrapper(example)
            report["cpuFixtureSeconds"] = time.perf_counter() - start
            report["outputShapes"] = [list(t.shape) for t in outputs]
            # Fixed 512 export: bake the SAME upstream bicubic positional
            # embedding once, instead of changing interpolation to bilinear.
            from efficient_track_anything.modeling.backbones.utils import get_abs_pos
            trunk = model.image_encoder.trunk
            baked = get_abs_pos(trunk.pos_embed, trunk.pretrain_use_cls_token, (32, 32)).reshape(1, 1024, -1)
            trunk.pos_embed = torch.nn.Parameter(baked.detach())
            trunk.pretrain_use_cls_token = False
            baked_outputs = wrapper(example)
            report["bakedPositionCPUError"] = max((a-b).abs().max().item() for a,b in zip(outputs,baked_outputs))
            if report["bakedPositionCPUError"] > 1e-5:
                raise ValueError("Baking positional embedding changed CPU encoder output")
            report["positionEmbeddingBakedForFixed512"] = True
            traced = torch.jit.trace(wrapper, example, check_trace=False)
        converted = ct.convert(traced, inputs=[ct.TensorType(name="normalized_rgb", shape=example.shape)],
                               convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18,
                               compute_precision=ct.precision.FLOAT16, skip_model_load=True)
        destination = args.output / "EfficientTAMTinyEncoder512.mlpackage"
        converted.save(str(destination))
        files = [{"path": str(f.relative_to(destination)), "bytes": f.stat().st_size,
                  "sha256": hashlib.sha256(f.read_bytes()).hexdigest()}
                 for f in sorted(destination.rglob("*")) if f.is_file()]
        report.update(coremlPackageWritten=True, convertedBytes=sum(f["bytes"] for f in files), files=files)
    except Exception as error:
        report["error"] = f"{type(error).__name__}: {error}"
    (args.output / "probe.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if report["coremlPackageWritten"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
