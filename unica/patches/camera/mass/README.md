# r9s mass Camera on One UI 9

This route selects the genuine `SM-G990E/THL` SDK36 `hal3_massPhone` Camera
before decoding it. It keeps the app's 18 bundled native libraries and matching
`camera-feature.xml` parser, not the r9q prebuilt or Camera 17's parser. Other
One UI 9 flavor transitions remain rejected until separately reviewed.

The One UI 9 system Simba, HEIF, image-codec APEX, libgui and SurfaceFlinger are
retained. `cohort.json` pins the reviewed inputs; changing a firmware requires
renewed compatibility review, not just replacing the hashes. Existing decoded
Camera directories are preserved and rejected rather than silently discarded.

## Compatibility evidence

Native analysis is static, using REA/Ghidra 12.1.4 plus independent ELF and
AArch64 disassembly comparisons. The retained investigation is in
`out/oneui9-four-ports-20261025/camera/`:

* `target-node-codec-constructor.json` shows the mass app's V1 node loading the
  real `Func_Init_SimbaEncoderNdk`, `Func_Init_SimbaEncoderHdrImageNdk` and
  `Func_Init_SimbaDecoderNdk` from `libsimba.media.samsung.so`.
  Evidence: `ev_76edd902dfb41cc8614297c74adbac302aa33f4f86407d3a6c4bb21771ddac3c`.
* `simba-source-init.json` confirms the One UI 9 V1 initializer constructs the
  real encoder, not a compatibility stub.
  Evidence: `ev_218f2f1b9f283238d40410ced7840d4bbeeb746c33a1baceb4d45721926eb79a`.
* `simba-vtables.json` compares SDK36/37 V1 encoder/HDR/decoder slots. Their
  sizes are respectively 56/80/40 bytes including Itanium headers, and their
  ordered callable signatures agree. Encoder roles 1/2/3 still select SQ JPEG,
  Quram JPEG and HEIF. `simba-*-layout.txt` retains the input/output accesses.
* `simba-source-convert.json` establishes the V1 frame layout: six 32-bit image
  fields at 0..20, rotation at 24, pixels/length at 32/40, EXIF at 48/56 and
  ICC at 64/72. SDK36 has the same accesses. User data remains pointer/length
  at 0/8; decoder input remains buffer/length/format/sample at 0/8/12/16.
  Evidence: `ev_528c65a4866f93784acb82b8c20dca298f0482dcf4803e8ed8175503ad65e4fc`.
* The target's missing system AIQ MPI30 and SNAP wrapper are imported with
  their original payloads. Existing platform imports supply MPI30, tuning,
  SwISP, LocalTM and target SNAP V3. The public-library registrations are
  restored without substituting an SDK36 Android platform library.

The V1 feature token must remain V1: this app actually contains its Java and
native nodes. Camera 17's V1-to-V2 rewrite and its classes2 processor patch
must not run here. The real timed-wait predicate fix is separately ported to
the mass app's classes3, preserving native release, busy timeout and errors.

## Validation boundary

The development tests are archived under
`out/oneui9-shell-migration-20261026/retired-source/`. A real-artifact replay rebuilt Camera and
SingleTakeService; the Camera native members, resource table and manifest
remain byte-identical to the selected target. ELF linkage inventories and
Java member analysis are separate from ART/linker and camera-HAL execution.

[`VALIDATION.md`](VALIDATION.md) checks the final selected-script Camera APK
(`9443866e…4869b12`), not only the original app: five actual DEX methods,
601 patched-class member uses, 92 types, and all 18 native members pass the
bounded static checks. All 16 mass-route host tests pass. The unchanged
baseline dependency issues and One UI 9's blacklisted `semIsDesktopMode()`
remain explicit runtime boundaries; signature existence is not an access grant.

On-device qualification is still required: all lenses, photo/JPEG/HEIF,
portrait/night/HDR, video resolutions and recording, repeated quick relaunch,
Single Take/SmartCrop, and absence of JNI/linker/processor errors. No physical
capture or device execution is claimed by these host checks.
