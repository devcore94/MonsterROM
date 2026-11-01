# Real humanseg CPU preview — explicit experiment, not a live extension

Enable UN1CA_QPR2_SUBJECT_CPU_PREVIEW=true only for the pinned One UI 9 cohort.
The loose CameraExtensionsProxy test APK includes this preview. The normal
live extension dispatch stays unchanged and reports subject segmentation
unavailable when no real SessionProcessor is present.

The real Samsung CPU humanseg model is used, not synthetic/fallback output:
12-27_PhotoEditor_StyleTransfer_v3.0_Segmentation.tflite (9,920,528 bytes).
The donor's segmentation.info identifies a CPU TFLite humanseg model.
Input is uint8 RGB [1,513,513,3], scale 1/128, zero point 128. Output is float32
binary-class logits [1,513,513,2]. Class argmax yields a binary mask; logits are
not misrepresented as calibrated alpha/confidence. The model is a Samsung
fallback candidate, not an original missing QPR2 segmentation engine.

App-local original Samsung TFLite C runtime 2.16.1 plus a small source-built C
bridge. No system/vendor native providers, GPU driver, Bionic or ART replaced.
One synchronous CPU call owns its input/model copies until interpreter teardown.
No persistent native handles, asynchronous leases, NPU/ENN/NCP29 or GPU jobs.
Wrong lengths, model/runtime/tensor contracts and incomplete/nonfinite results
reject without fabricating a mask. The Java asset is SHA-256 checked.

Preview entry: Samsung Settings > Advanced features > Labs, when the companion
Settings patch is installed with the same signer and DUMP permission. The new
activity requires android.permission.DUMP, has no intent filters and runs in
its own :unica_subject_preview process. It reads only an explicitly chosen
document-picker content URI. Incoming intent extras are not treated as images.
No broad storage/camera permission, file save, recording or background capture.
ImageDecoder supplies bounded software sRGB input with encoded orientation;
CPU inference stays off the UI thread. Stale/destroyed UI results are discarded.

The mask is represented as bounded non-overlapping row-run rectangles in a Path,
preserving raster holes/islands. This is not a smoothed vector contour. There is
an explicit complexity cap. Human-photo accuracy, physical image decoding,
UI behavior and complete Camera2 active-array/result integration are unproven.
Synthetic tests can produce false positives; no accuracy claim is made.

Original model/runtime come from the user's local Samsung donor and are not
re-licensed as new AOSP assets. Public C ABI reference:
https://github.com/tensorflow/tensorflow/blob/v2.16.1/tensorflow/lite/core/c/c_api.h

## Reviewed APK metadata refresh

`apks.json` retains original CameraExtensionsProxy identity
`02b170921cd511e4dbb69c642db9af1e70548867a293861808ed0b7e46eca414`
and admits only reviewed identity
`f658331d1bb03f1f8cb8b375ef61b3639e84c1ac03b2693c45fb78330729c9ff`.
Complete DEX, manifest, resources and member inventory are byte-identical;
only Samsung buildinfo/JAR signing members differ. Real API37 v3 verification
passes for both with the same Samsung certificate SHA-256
`34df0e7a9f1cf1892e45c056b4973cd81ccf148a4050d11aea4ac5a65f900a42`.
This is code identity evidence, not new inference, image, UI or hardware testing.

The model, runtime, bridge, payload manifest and ordinary patch are unchanged.
Preflight requires the complete three-payload contract, exact payload inventory
and single patch; it rejects missing, duplicate, unsafe or existing destinations
before copying. After decode, a real patch dry run precedes all payload copies.
Decode/copy/patch failures propagate explicitly under conditional sourcing.
SDK36 and a disabled preview do not read these inputs or mutate the APK.

Evidence: `out/full-rom-rebuild-20261029/subject-preview-review/`; REA archive
identity `ev_3c7fa677782fa1f7ee1dca372820cba250d339b28faf09c5f9492d0a896c9e31`.
Archive inventory does not verify APK signing blocks; real apksig verification
was separate. Android/JADX remains unavailable; no new REA decompilation or
device execution is claimed. Complete DEX byte comparison retains code identity.
