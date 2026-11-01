# One UI 9 Media Context Analyzer highlight GPU adaptation

The original Paradigm import supplied three a56x GPU/TFLite models plus SDK36
MCA libraries. The One UI 9 JNI has 21 entry points (SDK36 has six), so replacing
those libraries breaks the caller contract. Keeping only the One UI 9 donor also
loses the original adaptation: its Exynos selector chooses CoreType 1 and NNC
models compiled for s5e9965, regardless of the GPU floating feature.

This module changes five reviewed instructions in BZJA HighlightDetector::init:
the Exynos core becomes 3 (the original a56 GPU choice), and the model suffix
becomes `.tfl`. Detection and pose execution precision is restored from donor
ExeDataType3 to original ExeDataType0 (FP32); keyword already uses zero. It installs the complete original three-model TFLite cohort and
private Detection.tfl, Pose.tfl and Keyword.tfl symlinks. `.tfl` keeps the existing
four-byte string layout. SNAP receives model buffers and explicit model/backend
options; it does not need a `.tflite` filename to identify these buffers.

Existing aliases are accepted only when they already point to the reviewed model;
unknown aliases fail before model or native writes.

No algorithm, JNI entry point, vendor service, global hardware property, or
HumanPetTracker selector is replaced. The newer Locator/Reid auto-framing route
is separate and is not validated by this highlight adaptation. VideoScan's
MediaContextAnalyzerParameters defaults autoframing to false; native setMediaPipe
gates HighlightDetector and HumanPetTracker separately.

`contract.json` pins original/patched library hashes, the five instruction
offsets, model hashes/tensor interfaces, and retained JNI/video-highlight/
auto-reframing providers and the per-target SNAP provider retained by the camera
module. The importer verifies joined split files before
install, installed model bytes after install, and the resulting native hash.
Only One UI 9 o1s, t2s, p3s and r9s on Exynos2100 are accepted.

## Validation and boundary

The actual One UI 9 ARM64 HighlightDetector was executed under QEMU with each of
the four staged partition/APEX/property sets. It reads exynos2100, selects core3
and loads Detection.tfl. A test-only SNAP Init capture recorded options 1,0,9
and exact original model bytes (TFL3). Actual ModelDelegator executions captured
all three original model buffers, including the joined 66,269,012-byte pose
model. The capture intentionally returns unsupported; it never pretends that
inference succeeded. A separate run against the real SNAP library reached
CreateSnapSession and stopped because QEMU's host has no Android Binder driver.

Tensor names match the One UI 9 native request: detector images/output, pose
images/output_0_pose/output_1_feature, keyword inputs/output1/output2. One UI 9
retains YOLOv7 and RTMCC consumers and derives tensor dimensions/category counts
from ModelOperations. This establishes the model loading and tensor interface;
on-device inference, prediction quality, GPU driver behavior and thermal costs
still require a real phone. No successful phone inference is claimed.

Evidence from the 2026-11-01 comparison lives in
work/original-comparison-20261101/platform/mca, including per-device captures,
exact tensor tables and the real SNAP failure boundary.
