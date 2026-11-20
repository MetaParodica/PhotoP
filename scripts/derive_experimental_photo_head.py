"""Expose the pinned decoder's FP32 terminal mask head for native reconstruction.

Run with coremltools 9 and a pristine v1.2 initializer model.mlmodel as argv[1].
No weights, encoder, learned layers, prompts or quality heads are changed.
The terminal exact GELU and linear product are reconstructed natively.
"""
import hashlib
from pathlib import Path
import sys


def derive(source: Path, destination: Path):
    import coremltools as ct
    from coremltools.proto import FeatureTypes_pb2

    data = source.read_bytes()
    if hashlib.sha256(data).hexdigest() != "7d128934363e8f5771ff4ac1f90f2ea4fedc9b5e99c28e075199aee02381ef9c":
        raise ValueError("Expected pristine Jutsu v1.2 initializer specification")
    spec = ct.utils.load_spec(str(source))
    block = next(iter(spec.mlProgram.functions["main"].block_specializations.values()))
    shapes = {"input_93": [1, 32, 256, 256], "hyper_in": [1, 4, 32]}
    for name, shape in shapes.items():
        variable = next(output for operation in block.operations for output in operation.outputs if output.name == name)
        if [dim.constant.size for dim in variable.type.tensorType.dimensions] != shape:
            raise ValueError("Unexpected mask head shape: " + name)
    retained = [output for output in spec.description.output if output.name in {"best_iou", "object_score", "candidate_ious"}]
    del spec.description.output[:]
    spec.description.output.extend(retained)
    for name, shape in shapes.items():
        output = spec.description.output.add()
        output.name = name
        output.shortDescription = "Unchanged FP32 SAM2 preactivation/coefficients; native exact GELU and vDSP logits"
        output.type.multiArrayType.shape.extend(shape)
        output.type.multiArrayType.dataType = FeatureTypes_pb2.ArrayFeatureType.FLOAT32
    del block.outputs[:]
    block.outputs.extend(output.name for output in spec.description.output)
    spec.description.metadata.userDefined["PhotoP.maskHead"] = "v2: expose unchanged FP32 preactivation/coefficients; native exact GELU and linear product; weights unchanged"
    destination.write_bytes(spec.SerializeToString(deterministic=True))
    print(hashlib.sha256(destination.read_bytes()).hexdigest())


if __name__ == "__main__":
    derive(Path(sys.argv[1]), Path(sys.argv[2]))
