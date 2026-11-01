# One UI 9 vision adaptation for the One UI 9.5 backport

The supplied Samsung base is One UI 9 / One UI 9.0. These changes support the
requested 9.5 backport; they do not turn it into a genuine 9.5 donor or establish
complete Galaxy AI feature parity.

## Exynos2100 ordinary upscale selection

The One UI 9 `MidasAIConfigs` loader reads `device_property=ro.soc.model` and
case-insensitively compares it with each `compatible_models[].models_list`.
`midasSR_devices` membership is not this selection. Without an explicit match,
ordinary upscale on `Exynos 2100` uses the final default profile, which names
V270 graphs absent from all five supplied firmware inputs.

`0001-Select-Exynos2100-MIDAS-LITE-profile.patch` adds only `Exynos 2100` to the
existing One UI 9 LSI GPU/SNAPLITE/QASYMM8 profile. Its scale-specific tensor names
match the three genuine target LITE V100 graphs:

| Scale | Input / output | Stored input / output shapes (NHWC) |
| --- | --- | --- |
| 2× | `x.1` / `451` | `1,256,256,12` / `1,1024,1024,3` |
| 3× | `x.1` / `456` | `1,256,256,12` / `1,1536,1536,3` |
| 4× | `x.1` / `451` | `1,256,256,3` / `1,1024,1024,3` |

The native upscale initializer reduces channels by four for 4×; do not change
the shared `nChannel=12` to three. The three payloads are imported explicitly
from the selected target with their original filenames and vendor-config
metadata. All other source JSON fields/profiles and the One UI 9 native libraries
are preserved. In particular, `upscale-pro` is a separate module: model IDs
12–14 select it, not ordinary `upscale`. No Pro-to-LITE substitution is made.

The root customization uses ordinary `git apply` after source import, with a
dry-run against the source config before mutation. Repeated runs re-import the
unmodified source config before applying the patch. Only the Exynos2100 route
requires the property match and all three target weights. Other platforms keep
the One UI 9 source config unchanged; that is not qualification of their models.

`midas.sha256` pins the reviewed source config and both native readers;
the staged readers must also match those genuine source bytes. `midas-lite.sha256`
pins the three target graphs, preventing a nonempty/wrong-role model or
same-filename incompatible revision from being accepted. Both checks run before
mutation and are scoped to Exynos2100. A new donor/graph cohort needs measured
requalification, not blind checksum regeneration or a version-label override.

## Descriptor/weight preflight

Before replacing the system SAIV tree, the root customization requires the
15 source descriptor/weight files used by the six imported vendor cohorts,
including both system SLENS descriptors. It also checks the four retained
target legacy SS/HS files. This closes the previous case where a missing
`doc_rectifier_cnn.info` was accepted because its directory still existed.

These are presence/nonempty checks for the reviewed cohort, not a general
descriptor parser, inference test or proof that S26 NPU models run on Exynos2100.

Private original-helper verification is retained at
`out/oneui95-close-gaps-20261027/integration/saiv/RESULT.json`: all four targets
passed first/repeat/conditional Exynos and generic One UI 9 staging, for 24 successful
invocations. All **600** failure invocations rejected before mutation, including
same-size corruption, wrong-role graphs, mismatched/older readers, missing
manifests and config drift outside the patch hunk. Ordinary patch/reverse checks,
source-profile preservation, genuine LITE/descriptor identity and exact
Android-metadata repeat stability passed. Other binary payloads were explicitly
sparse non-inference fixtures; this was not a full ROM replay or hardware test.

## Evidence and limits

REA/Ghidra static observations for the supplied One UI 9 DNNInterface library
(`ca5e808698c6cf5281055506708c7e1c426397a7ec211f52be384d32df62afed`):

* Config/property read: `ev_77f351bbb74426b2653ad66fc8d654750a4300871080ea55e8be6b9c6d9fb227`.
* Property/model matching: `ev_e8951af1c3fa06dc8e89fcdd3e18bb45fc9d51808c33d33912790e19cd9b3242`.
* Per-scale model/tensor/config copy: `ev_0c107ec87c637b69aa7afda0cdca382486d4ace9774c961880ac25ce8591667b`.
* Upscale initialization/indexing: `ev_4d09d084cff11f9a8ae9801d691499dea61e393ca01a77778956c86568308c06`.
* Module-name mapping: `ev_5c832f6d47809675c71e32cafecccc7d776881a97768c1cac75f694bb92967ba`.
* File/error handling before SNAP: `ev_4c6eeada55bed8df085ae847de0a8a2ee189444e00c9c787f5b0dddf28e5e025`.

Full records and snapshot: `out/oneui95-gap-fix-20261027/saiv/`. Pseudocode is
inferred decompiler output, not original source or observed execution. Graph
interfaces were separately read from the genuine target FlatBuffers; parsing
does not establish backend acceptance.

The earlier genuine-Bionic/QEMU probe's dependency-constructor crash is resolved
in the private probe by loading genuine `libandroid.so` before MIDAS, avoiding
a cold-load JSON symbol collision. No shipped library is patched or replaced.
Eight real parser controls now pass: stock/candidate selection, existing LSI and
default preservation, case folding, no implicit trimming, and real missing/
invalid-config errors. Exact fields and 219 constructor-provider identities,
plus three original APEX payload identities, are verified in
`out/oneui95-close-gaps-20261027/native/parser-verified/RESULT.json`.

The genuine One UI 9 CPU TFLite runtime also loads, allocates and invokes all three
original target LITE graphs with zero and nonzero-pattern inputs. All runtime
tensor contracts and finite/nonconstant pattern outputs pass; missing/truncated
models are rejected. See that directory's `tflite-01/`, `tflite-02/` and
`FINDINGS.md`. These are **raw CPU graph** tests, not MIDAS GPU/SNAP, image-quality,
Android namespace/SELinux, or phone qualification. Production remains GPU;
no backend downgrade or fake SNAP success is used.

The declared 1× LITE graph is absent from every supplied input. Keep that
missing filename rather than alias a differently shaped model. Pro/GenSR,
HDR, quality assessment, tagger/pet/SmartScan migration, EDEN/NPU execution and
complete remaster behavior remain separate unresolved obligations. Validate
actual model selection and outputs on hardware before claiming full support.
