# Native optical usage bridge: implemented, device qualification pending

## Implemented allocation path

The original metadata-only mapping was unproven. This port does **not** assume
metadata `0x1e=4` sets a legacy usage bit. It explicitly requests that bit from
the real, freshly constructed BLAST consumer before allocation:

```text
One UI 9 optical mask window
  package=com.samsung.android.biometrics.app.setting, type=0xa3b, surfaceType=4
  -> new BLAST queue, before update()/createSurfaceWithHandle()
  -> ConsumerBase::setConsumerUsageBits(0x900 | 0x400000000)
  -> BufferQueueCore consumer usage -> dequeueBuffer() usage OR
  -> One UI 9 GraphicBuffer / HIDL4 allocator (one reserved-bit compatibility edit)
  -> r9s mapper descriptor -> allocator -> native handle consumer usage at +0x40
  -> r9s HWC optical-mask window state 0x20000
```

`consumer_usage.c` exports one JNI method and imports only the actual
`ConsumerBase::setConsumerUsageBits(unsigned long)`. It rejects null/uninitialized
queues, a queue already bound to a SurfaceControl, and unexpected initial usage.
It retains no native pointers and never edits allocated handles. The locked
consumer operation's real status is returned unchanged. Java throws a
`ServiceSpecificException` with that status before exposing a producer on error;
load/link failures are not swallowed. Non-mask windows never load this bridge.

The module-root `customize.sh` pins the platform/vendor files and target HIDL4 VINTF
manifest before staging. The shared selector validates this cohort before any
product-feature mutations. The source `ViewRootImpl.updateBlastSurfaceIfNeeded`
method is also pinned before insertion. Unknown cohorts remain rejected.

SurfaceFlinger, libgui, libandroid_runtime and vendor libraries remain unchanged.
The One UI 9 **libui is retained with one measured instruction changed**; it is not
byte-identical and must not be described as such. No SDK36 compositor/runtime
is imported. There are no authentication, permission, SELinux or HAL-result
bypasses. Static implementation is complete for this cohort; physical HBM,
composition/allocator behavior and authentication remain unobserved.

## Why the one-bit libui edit is required

One UI 9 `validateBufferDescriptorInfo` rejects usage bits selected by
`0xffff00280000` for HIDL. That includes r9s's legacy bit 34; a consumer-only
bridge would therefore fail real allocation. At ELF/file offset `0x446a8`,
`movk x8,#0xffff,lsl#32` (`0xf2dfffe8`) becomes
`movk x8,#0xfffb,lsl#32` (`0xf2dfff68`). The rejection mask becomes
`0xfffb00280000`: **only bit 34 changes**. Every other reserved bit, size/format
check, error path and the separate AIDL rejection mask remain unchanged.

The full input SHA256 is
`466dffbd2087a5a0c18b84717437e7204128af9343a9ec42657ba9839a309d0f`;
the exact resulting SHA256 is
`979a5ed04506a6be231ebbe6c5546670739f8dcc89c571c759ad8d600e42c461`.
The builder verifies both and never writes its input firmware/work files.

## Shipped-artifact evidence for the explicit path

Full REA envelopes are under
`out/oneui9-four-ports-20261025/optical/native-parent/`. Ghidra addresses for
these bindings equal ELF addresses plus `0x100000`; pseudocode is inferred,
not original source or observed execution.

| Observation | Evidence |
| --- | --- |
| BLAST initializes its consumer at `+0xc48`, default usage `+0xa8=0x900`; producer is created separately | `ev_4fc47e6312c5a093872f4bc98447ce1bbcf6b5e344e5c8ee7e6642953fdca937` |
| ConsumerBase locks, forwards to the actual consumer, preserves status including abandoned `-19` | `ev_4b084e6cad210f69a559a564a371df547609a2ad99f70cde2900f85afef22801` |
| Consumer usage is stored in core `+0x48`; dequeue ORs the full 64-bit usage into GraphicBuffer construction | `ev_777e7cf0e0d8cb1ea04a9eac08925004c378ffe038b868a5d470ac9be5fb2fdf` |
| One UI 9 GraphicBuffer/allocateHelper retain bit 34 (`usage & 0xffffffffffffdbff`) | `ev_a87af9fbe13495e969e450ec1269e9b0e8e9705034251f323684ca7f32b14072` |
| One UI 9 Gralloc4 allocates using the full 64-bit descriptor usage | `ev_50108e69e7182a1d97d21804b1bac4220435087599cefa210b87275ed4d671b8` |
| Exact One UI 9 reserved-usage rejection masks and real errors | `ev_df5c413a12d038e8469de1596059745564753a76b6ad825e744fc12932fedec8` |
| r9s mapper serializes full usage at descriptor byte 20 without truncation | `ev_303adf0fd32f3f00c46986e7eda47f8ddf103afc540ae31f6c633dd958711e57` |
| r9s allocator decodes usage into both descriptor `+0x10/+0x18`, invokes real allocation | `ev_9ba1053bb7368a005b9cbaa1ecda6c976feed2113d729444a5b0f040f9a14598` |
| Real ION allocator copies descriptor consumer usage to native handle `+0x40` | `ev_21cbcd2040cb91ee9dd2b465477c2c8363fd3cf4e30fe62cc60bf2b334749f67` |
| Format/size derivation preserves bit 34; its optional usage edits are ORs | `ev_d9cc5241835f7e77150a3260c4b3da4352aaa9735fe1a0c0c7e100f0f1b9b4b7` |
| HWC metadata constructor/getter preserve native handle consumer usage `+0x40` | `ev_fc3dc1ae59dad8fd9b19e1257f92d7679d02550b9b5ec580dc4cf7f1a149b90b` |
| Actual HWC bit-34 predicate selects optical state `0x20000` and retains errors | `ev_c3764a49d2e18c90685abcbdc8e69027904655d7bfda2c66d439f98dc4e0dc89` |

Eight host contract/build tests exercise the **compiled bridge**, true status
transport, no object/handle writes, invalid/live-queue rejection, exact one-bit
validation change, cohort rejection and actual ARM64 linking. These use test
doubles for the consumer and do not execute Android/ION/HWC. The final selected
replay also rebuilds the real framework DEX with the added JNI declaration and
resolves all introduced Java references against shipped One UI 9 definitions.

## Observed producer protocol

The shipped One UI 9 BiometricSetting class
`com/samsung/android/biometrics/app/setting/fingerprint/UdfpsMaskWindow` sets:

- Window type `0xa3b`, title `FP Maskview`, `surfaceType=4`.
- Samsung extension flags `0x40000`, `0x20000`, `0x8`.
- `turnOnHBM()` makes the real mask visible; that alone does not prove panel HBM.

Shipped `ViewRootImpl` writes `LayoutParams.surfaceType` to SurfaceControl
metadata key `0x1e`. Source optical feature/controller code exists even though
the source device is ultrasonic. The child selects that existing code, not a
new counterfeit native/HAL implementation.

Read-only decoded producer input:
`out/oneui9-four-ports-20261025/optical/source-biometric/`.
Original APK SHA256:
`673c910dcbe1ea6cb8d057099ee5a945ed8c7eb780a4b14505f139c150af5ade`.

## Observed r9s consumer contract

All addresses here are ELF virtual addresses, not file offsets. Inputs are
`out/fw/SM-G990E_THL/vendor/lib64/`:

| Artifact | SHA256 |
| --- | --- |
| `libexynosdisplay.so` | `21ec8cf91ba79c838b04f2dedaf7af9192c194757a462549d8c9caa1dc7d1955` |
| `libexynosgraphicbuffer.so` | `177570fe889185ea8834a2f4c55b513a4941e660328a43d452ad81fce1e58e54` |

`ExynosDisplay::deliverWinConfigData()` starts at `0x40500`.
At `0x405f8`, metadata destination is `sp+0x10`; `0x40614` constructs
`ExynosGraphicBufferMeta` from a layer's native buffer handle. `0x4061c` reads
byte `sp+84`, and `0x40620` tests bit 2 before entering the optical-positive path.

The buffer metadata constructor at `0x4328`, specifically `0x43e4-0x43e8`,
copies `[handle+64]` to `[metadata+64]`. Exported
`get_consumer_usage()` at `0x3fc0` independently reads `[handle+64]`.
Thus byte `metadata+68`, bit 2 is consumer-usage bit 34, `0x400000000`.
Producer usage is separately `[handle+56]`, corroborated by its exported getter.

The positive branch at `0x40790` references
`Mask layer for indisplay fingerprint is shown`; `0x407a8` writes window state
`0x20000`. These are static instruction/data observations, not executed HBM.

Reproducible raw disassembly and identities are retained in
`out/oneui9-four-ports-20261025/optical/final-checks-01/`:

- `libexynosdisplay.so-optical.s`
- `libexynosgraphicbuffer.so-optical.s`
- `r9s-native-identities.json`

## One UI 9 SurfaceFlinger evidence and bounded unknowns

Exact source SHA256:
`e3275abef1ce1a72753d6605adcb8d71393ca6de2653bc7a31a7f07e3d82109c`.
For this REA binding, its analysis addresses are ELF address + `0x100000`.

| Function | ELF | REA |
| --- | --- | --- |
| `LayerSnapshotBuilder::updateInput` | `0x287d8c` | `0x387d8c` |
| `SurfaceFlinger::buildWindowInfos` | `0x53f6d0` | `0x63f6d0` |
| `OutputLayer::writeStateToHWC` | `0x483138` | `0x583138` |

Matching-subject REA evidence already obtained:

- updateInput dossier:
  `ev_7f34021e6f5ef170a732d76d6e2beacdb871deff691fa37d4a6832ccaf20c985`.
- Its paged pseudocode:
  `ev_9d08b22a5a3af1935b66910f92aa9dcde4196df5be78d72af7159f9cd5f319e9`,
  `ev_273086458e15930463b9e40b34c0244db1bb7b0861d580127e48a2eac52c4057`.
- writeStateToHWC:
  `ev_63aee51029bfc2c54dd2b22f187e780462b8d0efa53820f90c099fbf04d06922`.

updateInput copies Samsung input information generically. Its observed special
metadata `0x1e` tests for values 1/2 do not establish optical value-4 allocation
behavior. These functions did not establish the consumer-usage mapping.

Source/target compressed debug symbol inventories and disassemblies are saved
under `out/oneui9-four-ports-20261025/optical/`. No fingerprint/optical/HBM-named
SurfaceFlinger symbol was found in those inventories; this is a bounded negative
search, **not evidence that support is absent**. Most libgui bit-34 matches refer
to the unrelated `layer_state_t.what` background-color change flag. Do not use
them as graphics-buffer usage evidence.

`writeStateToHWC.json` contains a cancelled independent CLI attempt, not
positive evidence. A query that raced with the shared target's change to a
different libexynosdisplay subject was excluded from the source conclusion.

## Device qualification still required

The original missing allocation implementation is now supplied above. The
metadata-only path remains unproven and is not used as the compatibility proof.
No native analysis is pending and the parent's REA sessions are closed.

On an authorized r9s runtime, verify real buffer allocation and HWC logs, panel
illumination, HBM off/cancellation, enrollment, unlock, error paths, screen-off/
AOD and repeated surface recreation. Static mapping and host compilation do
not validate ART/JNI loading, linker namespaces, GPU composition selection,
vendor ABI, panel timing or fingerprint HAL operation. No device success is
claimed by this implementation.

## Reviewed runtime metadata refresh (29 October 2026)

The native gate retains runtime identity
`4a21077a466d05232d8fc521455a3b9e1b036793e3a91bb32ac51252f6beb6b9`
and admits only additional identity
`7e7d3c0ecb6adc789e02d8d76e8defa0fc003651f514ec22b15efdb446c3f755`.
All 32 section identities match except the GNU build-id and non-loaded
`.gnu_debugdata`; all program headers, code/data, dynamic symbols, relocations,
dependencies and symbol versions match. Load segments are identical after
accounting only for the GNU build-id note and ELF section-table pointer.
The shorter debug metadata moves the section table; it does not change the
runtime load layout or any optical allocation instruction.

All seven other cohort hashes, the bridge source, five ordinary optical patches,
method contracts and exact one-bit libui input/output identities are unchanged.
Every cohort input must be a regular non-symlink file, and the report records
the actual measured runtime hash, not an array of allowed hashes. Unknown or
incomplete cohorts still stop before product-feature mutations or output creation.
No arbitrary equivalent-binary normalization or automatic hash refresh is used.

Evidence: `out/r9s-full-rom-rebuild-20261029/optical-native-review/` contains
complete ELF/load-segment comparisons and readelf ABI inventories. REA artifact
identity is `ev_66ed785e3763e6f676ef09b44e81aa5f7107d87a7aa5cf4cdca67f17f4a9c29b`;
that bounded artifact inspection is not a new decompilation or runtime test.
No fingerprint/HBM/device qualification follows from this metadata comparison.
