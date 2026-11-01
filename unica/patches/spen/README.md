# p3s One UI 9 S Pen: native provider and complete recognition clients

## Status

The **One UI 9 input/SMPS and SmartEye client implementation is wired** through
`unica/patches/spen/customize.sh`. It does not copy SDK36 `libandroid_runtime`,
`libandroid_servers`, audio, Binder, libc++, or input platform libraries.

The previously identified stripped handwriting callback and old Stride client
gaps are repaired with coherent, genuine One UI 9 clients. The bounded static,
APK-build and host instruction-model suite passes. **Android/device execution
is still untested**; static completion is not hardware functional certification.

## Implemented

* One UI 9's `libandroid_servers.so` already registers genuine input JNI methods:

  | Method | Descriptor | JNI table VA | Function VA |
  | --- | --- | --- | --- |
  | `setPenHovering` | `(Z)V` | `0x183d68` | `0xf8ad0` |
  | `setShowHovering` | `(Z)V` | `0x183d50` | `0xf8a74` |
  | `setPenModeOnDex` | `(I)V` | `0x183c60` | `0xf8618` |
  | `setStylusPointerIconEnabled` | `(Z)V` | `0x183a80` | `0xf7900` |

  These forward into the existing native input implementation, not stubs.
  Fresh `SystemServer.smali:13169` starts `spengestureservice` unconditionally;
  `SpenGestureManagerService.smali:1256..1342` enables its pointer listener from
  `SEC_FLOATING_FEATURE_FRAMEWORK_CONFIG_SPEN_VERSION`. USP75 and the actual
  p3s external-pen garage specification are copied from the target.

* Samsung b0sxxx's real SMPS implementation is retained. Its 14 JNI functions,
  synthesis, tuning, source-file parsing, ring buffer, callback and start/stop
  implementations are unchanged. Only two measured ARM64 instructions change:

  | Provider VA | Old | New | Reason |
  | --- | --- | --- | --- |
  | `0x6cb4` | `mov w0,#0x550` | `mov w0,#0x578` | actual One UI 9 AudioTrack allocation |
  | `0x700c` | `ldr w6,[x8,#0x220]` | `ldr w6,[x8,#0x238]` | actual One UI 9 mStatus offset |

  One UI 9's deleting destructor explicitly uses size `0x578`; its constructor
  and `set` use status offset `0x238`. The provider uses the dynamic vtable
  offset for RefBase, not an embedded old RefBase offset. Its callback vtable
  layout and Buffer size/raw offsets are unchanged at the used boundary.

* `audiotrack_set.S` exports the exact old `AudioTrack::set` symbol and calls
  the exact One UI 9 symbol with the added `const std::string& codecProvenance`.
  It supplies an empty 24-byte libc++ string, as stock One UI 9 ToneGenerator does
  for generated PCM. One UI 9 `createTrack_l` forwards this into the real track
  request and labels it `codecProvenance` in metrics. All original arguments,
  attribution, callback, `s0`, and the real success/error result pass through.
  No JNI success is fabricated and no permission/CFI/SELinux check is removed.
  The adapter has BTI/PAC, RELRO, immediate binding and a non-executable stack.

* The module-root `customize.sh` pins the donor and One UI 9 C++ layout cohort by SHA-256,
  verifies exports/imports and JNI registrations, builds the adapter with
  installed clang/lld, adds an explicit provider dependency with patchelf,
  and verifies that ELF editing did not alter native code/data/relocations
  beyond the two requested instructions. Unmeasured cohorts fail before app
  staging. It never edits its native input libraries.

* The route stages all five existing S Pen APKs, donor permission/sysconfig
  XMLs and pen-sound data, and retains source One UI 9 `SmpsManager.jar` and
  `HandwritingService.apk`. Normal ROM APK rebuild and platform signing remain
  in the existing build pipeline.

## Genuine One UI 9 SmartEye clients

The same root script selectively disassembles the pinned source SmartCapture APK with
the installed apktool JAR's baksmali entry point. It installs **all 47 handwriting
and 44 OCR classes**, including the real native listeners, result readers,
language/resource managers, Stride implementation, postprocessing, and
layout/table/document result models. It does not guess wrappers for removed
legacy native methods or manufacture recognition results.

R8 moved some SDK code into shared application helpers. Twelve referenced
outline methods are extracted verbatim into four isolated helper classes; the
complete URL predicate is copied into a fifth. References are renamed so they
cannot bind to unrelated obfuscated SmartEye methods. Three small platform
boundary adaptations avoid importing the unrelated drawing SDK:

* `Recognizer.getOneUIVersion` reads the same property through retained One UI 9
  `android.os.SystemProperties.get`; availability/device checks remain real.
* `SepUseWrapper` uses the cohort's genuine `SepUseDirect` implementation of
  the same interface, backed by Samsung's retained floating-feature API.
* The optional `HwrLibraryLoader.loadLibrary` path resolves `Spen` reflectively
  instead of hard-linking its Kotlin companion. Primary `loadTextLibrary`,
  native names and genuine load failures are unchanged.

It also adds the required public
`libSDKRecognitionText.spensdk.samsung.so` dependency. The existing Stride
declaration stays unchanged. It uses the normal UN1CA decoded XML manifest,
without altering resource IDs or other declarations. No target-SDK lowering,
permission removal, namespace bypass or security-policy change is used.

### Preserved application semantics

The `smarteye/` files replace only SmartEye's old initialization/engine/listener
facades. `LM1/b;` retains its existing fields and request ABI; `LO1/a;` retains
its lifecycle/stroke/language API. The old SDL facade names also delegate to
the same current SDK, rather than referring to absent framework APIs.

* Initialization checks the actual SDK's package/device availability and keeps
  true initialization/load errors. The backend is a real async `TextRecognizer`.
* Stroke arrays, language selection, supported languages, request, cancel and
  close delegate to the shipping SDK. Its validation and native failures stay
  failures; incorrect-usage exceptions retain their original cause.
* The native `onRecognize(II)V` callback invokes the shipping `ResultImpl`, which
  reads `getResultCount/getResult` from the real native engine. The SDK's public
  result/listener layer then calls `RecognitionCallback`.
* Status zero forwards the actual `String[]` candidates to the existing
  `0x7d2` handler message; nonzero status forwards null, never candidate text.
  Status is preserved in `arg1`. The existing handler still delivers candidate
  zero to `LF2/b;->m(ILjava/lang/String;)V`, handles empty/null results, and
  schedules native close. That handler was not rewritten.
* Each request has a one-shot callback identity. Cancel/close detach it before
  calling the actual SDK, so a detached/duplicate callback cannot post a result.
  The facade does not hold its monitor across native cancel/dispose/request.
  The SDK's own no-strokes async status `2`/null path is preserved.
* If SDK request dispatch throws, cleanup detaches only that request's captured
  token under the bridge monitor, and clears its listener only if it still
  belongs to that token. A newer registration is not erased. Checked incorrect
  usage retains its original cause in `LM1/a;`; SDK `RuntimeException`s are
  rethrown unchanged. Fatal `Error`s remain uncaught. Cleanup neither calls
  cancel/dispose nor retries, changes SDK state, or manufactures a completion.
* The actual OCR consumer still calls `getInstance(options)`, `initialize(I)`,
  `process_ARGB_bmp(bitmap, page)` and `deinitialize()`. Its return-code checks,
  page-to-application conversion, cleanup and error propagation are unchanged.
  The current Stride client supplies the matching native methods and models.

The dispatch-unwind cleanup is required by the selected caller lifecycle:
`InfoExtractionService` reuses its handwriting-manager singleton;
`LF2/b;->g` sends stroke requests (`0x7d1`) without reinitializing it. The
`LG2/a;` handler catches `LM1/a;` by logging only, not closing the engine;
normal result handling (`0x7d2`) is what schedules close (`0x7d3`). Leaving a
failed token pending would therefore block a corrected request. The regression
test retries on the same facade/engine without close/cancel; native-runtime
fault tests supply new strokes where the real SDK consumed its public stroke
count before dispatch. These are caller-driven retries, not hidden recovery.

All client member references, including callers outside the transplanted
packages, are checked before mutation. Existing decoded clients must match the
measured original; modified classes are rejected without overwriting them.
Source/provider hashes and per-class extraction/transformation provenance are
recorded in `configs/spen-clients.json` in the build work directory.

## Historical bounded validation

The development harness and superseded Python helpers are archived under
`out/oneui9-shell-migration-20261026/retired-source/`. They are not build inputs.

The test executes the main route with real build helper definitions in a new
sandbox; rebuilds and signs the selected SmartEye APK; verifies 14 unchanged
SMPS JNI bodies/descriptors, all provider/adapter strong imports and symbol
versions, embedded APK native dependencies, selected Samsung/sem framework
methods/fields, feature/data/metadata staging, and rejection of a changed
platform cohort. A symbolic walk of the actual emitted ARM64 instructions
checks arguments, stack, callee-saved state, empty provenance and unchanged
error-result transport. It additionally verifies:

* all 91 extracted SDK classes and complete method/field inventories;
* all **27 handwriting and 20 Stride native bindings** against unchanged One UI 9
  providers, with exactly the shipping descriptors;
* the **38 GetFieldID contracts and constructors in 10 native-created OCR
  model classes**, including layout/table results, and `onRecognize(II)V`;
* unchanged SmartEye handler/OCR consumers, resources, assets and permission
  declarations, apart from the additive handwriting native-library dependency;
* host interpretation of the rebuilt APK's actual smali, covering real candidate
  forwarding through both shipping listener layers, deferred/empty/error paths,
  language/stroke delegation, cancellation, duplicate results, close, failed
  dispatch followed by corrected retry, interleaved token replacement, unchanged
  runtime exception/cause propagation, and uncaught fatal native Errors;
* rejection of a modified decoded facade before class/manifest mutation.

The host model uses explicit Android/JNI test doubles. Candidate payloads are
test inputs, **not observed OCR output**; those doubles never ship in the APK.
No Android or native recognizer is executed by this test.

The final complete bounded run is
`out/oneui9-four-ports-20261025/spen/validation-11/validation.json`, with a signed
sandbox APK alongside it and `client-contracts/report.json` containing the
binding/model/behavior checks. `suite_complete` means the **static test suite**;
`implementation_complete: true` and `device_validated: false` are separate.
Historical validation-05/06 reports predate the client repair and are superseded.
Validation-11 additionally fixes and tests the dispatch-unwind retry issue that
was reproduced against validation-10's immutable rebuilt APK.

No firmware/existing work output or phone was changed by these tests. All
test output is under the task's new `out/oneui9-four-ports-20261025/spen` tree.

## Native evidence

REA was used through independent installed CLI processes; the shared MCP
SurfaceFlinger binding was not opened, closed or otherwise changed. The full
inline Evidence envelopes are retained under the test tree:

* `smps-open-evidence.json`:
  `ev_561b330b9206cd2718fcc4ad70280164f2af4e2e5a8bcb2b35194fcc8bf5219c`
* `audiotrack-constructor-evidence.json`:
  `ev_3dd2ea3a1433d4979a6054cf5d7ed931c6a2a77330b1aba368b49f072c3a1abd`
* `audiotrack-set-evidence.json`:
  `ev_f35675993e92b845fabef7eec74b19b5eafa3ee1c5e80a860602480de9115e29`
* `audiotrack-create-evidence.json`:
  `ev_f3ea718212458661a9b1568cf6956fc8173831693e84ccde093bc451b96c790a`
* `handwriting-onrecognize-evidence.json` (real Java callback name/descriptor):
  `ev_0912df97abbfba0fb2fe6969bb26f20a12a96c9965aa1a6db85ac9567358841e`
* `stride-fields-evidence.json` (actual GetFieldID names/types):
  `ev_b040928a2c27e205722639a510a96329e56a7fb4830c0e955c598f1d7ac2000a`
* `stride-output-contract-evidence.json` (real Page/model population):
  `ev_55fde6d0e693c34b2bf59fe1dcd7c3fa495336c919accf6db5bbd437c36aae61`

Static evidence does not establish Android linker namespace behavior, CFI
callback execution, AudioFlinger operation/latency, pressure/hover/button
events, Air Command UI, suspend/resume, recognition or actual p3s hardware
behavior or recognition accuracy. Those require subsequent Android/device
testing. No known source-level client incompatibility remains in the selected
handwriting/OCR request paths after these checks.
