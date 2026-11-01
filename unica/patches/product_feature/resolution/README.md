# One UI 9 p3s dynamic resolution

This is a One UI 9 implementation, not the SDK36 resolution patch set. It keeps
`TARGET_COMMON_SUPPORT_DYN_RESOLUTION_CONTROL=true` and never imports or patches
SurfaceFlinger, bootanimation, libgui, libui or libandroid_runtime.

## Integrated selection

`unica/patches/product_feature/customize.sh` owns this code **instead of
the entire legacy resolution branch** for One UI 9/source-false → SDK35 p3s/
ESSI/target-true with an ultrasonic sensor. Other One UI 9 capability transitions
still fail before mutations; SDK36 keeps its original selection. The legacy
compositor/bootanimation imports and R8 patches cannot run after this branch.

The historical replay exercised the actual preflight and hardware dispatch
sections. Development fixtures are archived under
`out/oneui9-shell-migration-20261026/retired-source/`, not loaded by the build.

## Implemented route

* Framework enables `FW_SUPPORT_MULTI_RESOLUTION`,
  `FW_DYNAMIC_RESOLUTION_CONTROL` and `FW_RESOLUTION_VOTE_POLICY`. It keeps
  `FW_MULTI_RESOLUTION_POLICY`, density mapping, block-app resolution votes and
  Samsung's private shell-transition resolution handshake **off**. This selects
  one coherent forced-size policy, not competing forced-size/preferred-mode
  persistence mechanisms. The standard native resolution-mode path remains on.
* Settings restores the resolution preference, desktop restrictions, radio
  initialization, correctly calculated preview dimensions, and Global settings
  observers. Both existing confirmation listeners retain their One UI 9 ABI.
* `ResolutionPolicy` rejects invalid indices/external displays/missing physical
  HWC modes **before mutation**. It sends the actual advertised width/height and
  proportionally preserved density through the One UI 9
  `IWindowManager.setForcedDisplaySizeDensity(IIIIZI)` entry point. Remote errors
  propagate; there is no synthetic mode, private vendor transaction or fake
  native success return.
* Reset uses advertised FHD plus scaled initial density. Single-choice controls,
  routines apply/reverse, and backup/restore use the same route. Routines and
  restore return failure on rejected requests; acceptance is not panel completion.
* The retained One UI 9 services implementation turns the changed logical display
  width into `RefreshRateController.updateResolutionLocked` → `SizeVote` → normal
  desired display-mode specs → SurfaceFlinger → HIDL composer 2.4. No services
  R8 transplantation is needed.
* GameManager restores actual resolution-change notifications. SystemUI restores
  orientation-independent edge-mask scaling at the FHD-calibrated radius, reading
  capability centrally rather than replacing One UI 9 synthetic listener classes.
* Off-mode charging/error media restores the original explicit 25 QHD SPI files
  and `lcd_density.txt` from `b0qxxx`. One UI 9 LPM uses stored image dimensions and
  does not scale them to the panel; bootanimation separately scales QMG frames.
  Keep both One UI 9 binaries and all newer source-only media files.

## Evidence and validation

Authoritative inputs: pristine `out/fw/SM-S942B_INS` One UI 9 and
`out/fw/SM-G998B_AUT` SDK35. Java inspection used the explicitly permitted apktool/
smali fallback and the read-only fresh decode with recorded provenance in
`out/oneui9-audit-20261025/hardware/source-origins.json`. Historical review output
was not used as a shipping input. Native inspection used REA/Ghidra 12.1.4.

Useful REA Evidence IDs (complete records exported under the output below):

| Observation | Evidence |
| --- | --- |
| One UI 9 SurfaceFlinger has native resolution-change and HIDL config paths | `ev_25d9ff0786f291334e34fbc0f56b0316984a9ba102e3f277f185e2a5e2b36ee7` |
| One UI 9 HIDL `setActiveConfigWithConstraints` forwards to composer 2.4 | `ev_1e508cd33be456ad14f2e8a2f58c497acd71f0f02ec286152b40459b0e4d8303` |
| One UI 9 loads advertised HWC modes without a source-product FHD-only filter | `ev_383021e6e215f91357b9ee0cbcc901a9368e74d8a7b0c16e80873f212277c4a4` |
| p3s enumerates DPU configurations using real width/height/refresh/group data | `ev_3cf8cd6795306df2eadcffb2e4c441e957e1cda75b286a0c055140d465b1c7f8` |
| p3s returns config width/height to standard HWC attribute queries | `ev_af0a969c637dccf32f269edad6bab77366cced99fd625ce50b2076e062a7ef05` |
| p3s supports non-seamless cross-resolution-group config switches | `ev_2ba764be92891ace43c97c27531dccf8e75ff676d0fe259f9024405169bd2222` |

These are static observations, not execution. Ghidra pseudocode is inferred
decompiler text with incomplete indirect-call typing; its reported terminal
`__stack_chk_fail`/`__throw_bad_variant_access` paths and provider limitations are
retained in the bundles. The native session was closed after export.

The format-aware Android DT-table/FDT inspection established that all
**eight shipped p3s DTBO entries** expose 720×1600, 1080×2400 and
1440×3200, with 48/60/96/120-Hz entries. This establishes stored panel-mode tables,
not that a running kernel/HWC accepted a request.

Completed outputs:

`out/oneui9-four-ports-20261025/resolution/`

* `replay-verified.log`: actual child selection and real repository patch helpers
  on fresh, private sparse files; every selected patch applied.
* `verified/verification.json`: ABI/reference contracts; full assembly of
  framework classes6 (6,836 classes), GameManager (140), Settings classes1/3
  (12,973 / 7,600), and SystemUI classes2 (16,609); all passed.
* `verified/built/{framework.jar,gamemanager.jar,SecSettings.apk,SystemUI.apk}`:
  rebuilt archives containing those complete DEX files. All other entries were
  verified byte-identical to the firmware (except removed signing metadata).
* `verified/aligned/{SecSettings.apk,SystemUI.apk}`: both pass `zipalign -c -p 4`.
  These are **unsigned test archives**, not release-signed installation artifacts.
* `evidence/p3s-dtbo.json` and `evidence/native-with-load-modes.json`: complete
  DTBO findings and REA evidence. The directory uses approximately 0.5 GB, not
  repeated copies of the multi-GB smali trees.

Replay tools are retained in the development archive above. They are not
additional production build paths.

The bundled assembler has no API37 opcode table. Tests select API29 solely to
emit DEX **039**, then assert its magic matches every pristine One UI 9 input.
This does not change the firmware's API level or substitute framework classes.
Resources are retained encoded, not rebuilt by AAPT; no resource change is needed.

### Charging-media follow-up

The One UI 9 LPM `create_surface` allocates the decoded SPI's stored width/height,
and `drawBlit` copies rows without resampling. This is separate from the QMG
boot-animation scaling path. Relevant native Evidence:
`ev_f41051d6e7c1e84d38dac0da64111a422a13e539692a63116f82955c11c25b41`
and `ev_3d71d95bafc173ff6d6d3f58d6b07be35dc3c182afb7476412eaf5f7ad7149ad`.

The restored original assets use 880×268 charging cells (not 660×201) and
`640` density. Exact original payload choices, including the 480×480
`battery_temperature_limit.spi`, are preserved. Four private real-helper
resolution-route replays, media/metadata identities, native preservation,
repeat imports and rejection checks are recorded in
`out/oneui9-parity-review-20261027/resolution-media/`. Full SQH framing and native
evidence are in the adjacent `native/` directory. These are not pixel-decoding
or off-mode panel execution tests; verify actual charging appearance on hardware.

## Hardware-only validation still required

No phone, ART runtime or physical panel was used. Verify actual active HWC/SF
mode (not just `display_size_forced`) after HD/FHD/WQHD transitions, all supported
refresh rates, landscape, screen zoom/Easy Mode, AOD, reboot persistence, DeX,
routines/restore, and edge-lighting appearance. Check HWC errors and mode-change
callbacks. No matching-donor/build blocker was found; physical success and
glitch-free transitions are deliberately not claimed.
