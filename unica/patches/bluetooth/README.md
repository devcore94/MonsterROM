# Bluetooth APEX port

## What is changed

For the reviewed SM-S942B One UI 9 source with the SDK35 S21 or SDK36 S21 FE vendor cohort:

- Apply the existing One UI 9 **SBM-enable** and **XLNA-disable** smali patches.
  A2DP sink and HEAD SAR remain unchanged. Unported transitions still fail.
- Keep **every byte of One UI 9 `libbluetooth_jni.so`**. Do not patch its
  VaultKeeper branches, storage encryption, retries, key generation or error
  handling, and do not transplant an older Bluetooth runtime.
- Replace the APEX-local `libvkmanager.so` **symlink**, not the system library,
  with the genuine target's small HIDL client. Include its genuine HIDL 2.0
  interface library and **the donor's One UI 9** `libhidlbase.so` locally. All
  remaining platform libraries stay One UI 9. No namespace allowlist is widened.

The root `customize.sh` requires the target VINTF declaration to be HIDL 2.0 /
`ISehVaultKeeper/default`. An AIDL target keeps its original backend. Unrecognized
manifests, native bytes, symbols, symbol versions, SONAMEs, unresolved imports or
new external namespace dependencies are errors, not reasons to bypass security.

The manager and interface are checked as **one exact pair**, not independent
allowlists. SDK35 t2s/o1s/p3s share the original pair. SDK36 r9s ships a distinct
pair with the same four reviewed opaque APIs and HIDL 2.0 transport:

| Vendor cohort | Manager SHA-256 | HIDL interface SHA-256 |
| --- | --- | --- |
| S21 SDK35 | `4d84d6674aa779b3460ddcf94f69459ba828ed30ffe2d00feccc500245a81aa5` | `adb95777c6db31a45ea88cb2b554e897c6e13c5802f4c4766e4fda89b35f1602` |
| r9s SDK36 | `63610e52c7f110c68eff36c3fa1d870968ee5822ca78d94f91989bd579c2a778` | `d13537814b4d0a8ff4088bcd518031932981b968aea4e6f7d3540178e38551bd` |

Unknown bytes or mixed known pairs still fail before payload writes. Selecting
r9s does not relax the source JNI/AIDL-manager/current-hidlbase pins, dependency,
symbol-version or namespace checks. The chosen pair is named in the contract
receipt. The r9s manager still allocates/frees its own 32-byte object, forwards
the same read/write API and retains real service/data/status/error handling.
Its complete interface export set matches the SDK35 interface. Native Evidence,
whole-APEX proof and reproduction for this second cohort are retained under
`out/oneui9-bluetooth-r9s-20261026/`; static review is not a hardware-success claim.

## Why the native change is needed

The parent captured the installed t2s device read-only on 2026-10-26. In
`out/oneui9-remaining-fixes-20261026/device/20261026T015339Z/`:

- `focused-system-log.txt` records repeated five-second waits for the missing
  **AIDL** VaultKeeper service, `getKeyIVLen = 0`, a 29,310 ms scan-controller
  startup, `BLE_START_TIMEOUT`, and the process's subsequent SIGKILL.
- `bluetooth-processes.txt` and `bluetooth-properties.txt` establish that the
  target's genuine **HIDL** VaultKeeper daemon/service are running. Bluetooth HCI
  firmware initialization completes; the evidence does not support blaming it
  for the VaultKeeper wait.
- `bluetooth-native-identities.txt` matches the immutable donor JNI and AIDL
  `libvkmanager.so` hashes used by this port.

This establishes an actual client/backend mismatch, not an authorization failure
that should be disguised as success. The replacement performs genuine HIDL calls
and retains the target library's returned status, data and data length.

## ABI boundary and evidence

The One UI 9 JNI imports exactly four `VaultKeeperManager` methods, also exported by
the target client:

```
getInstance()
read(int, char*, int*)
write(int, char*, int)
freeInstance()
```

The target manager allocates a **32-byte** object; the source manager uses a
different **48-byte** representation. They must **not** share an object. The
reviewed JNI obtains its opaque pointer from `getInstance`, stores/loads that
pointer, passes it to the above out-of-line methods and frees it through the
same library. It does not call a constructor/destructor, allocate the object or
access either layout's fields. Native-call mapping identifies these One UI 9 call
sites (ELF virtual addresses):

| API | Call sites |
| --- | --- |
| `getInstance()` | `0x7ab394` |
| `read(int,char*,int*)` | `0x7ab4c0` |
| `write(int,char*,int)` | `0x7abbb4` |
| `freeInstance()` | `0x7ab5f0`, `0x7abea0` |

The read call passes slot **2**, a byte buffer and an output-length pointer; its
caller requires **32 bytes**. The write call passes slot 2 and 32 bytes. The stock
target Bluetooth JNI imports the same four APIs. Exact input hashes gate reuse
of this reviewed opaque-object boundary; symbol-name similarity alone is not
considered object-layout compatibility.

`abi-proof.py`/`abi-proof.json` in the private proof directory map actual ELF
relocations through GOT/PLT instructions to these call sites and retain complete
unwind-bounded caller disassembly. The host GNU objdump mislabels some newer BTI
PLT slots; its printed call-target names are **not** used as symbol identities.

REA/Ghidra evidence for the target client is exported under
`out/oneui9-remaining-fixes-20261026/bluetooth/target-vk-evidence-complete.json`:

- `getInstance`: `ev_dcf75c54cd8041c2c2ca55d9975dc2be65e1300a918b3ac00d066a6fddcf13fb`
- `read`: `ev_9fb6ccff6f3d1b3a12ac883d33378346c2be4c123f03bc18d7aca0a550b7fdb6`
- `write`: `ev_dd346ed2cd44df4ccda02de84df9e472b145b6047626060ea364d6dd6e2810e1`
- constructor: `ev_be1cff9aecf524deb4d5aedc034109fc2ac4d9383f0c8b67bbfe30099b5b9a00`

**Decompiler limitation:** Ghidra incorrectly drops the HIDL `getService`
success path in `read`'s pseudocode because of the indirect structure-return
boundary. The complete returned assembly, including the HIDL virtual call and
response/error branches, is retained; do not mistake the shortened pseudocode
for a client that always returns failure. The larger JNI analysis timed out;
its call mapping and disassembly are explicitly ordinary ELF/objdump evidence,
not invented REA results. REA Android inspection was unavailable because
`REA_JADX_MCP_JAR` was unset; APK/smali inspection uses Apktool/Dexlib instead.

`native-contract.json` records a **14-provider ARM64 dependency closure**, with
zero unresolved strong/versioned imports, using One UI 9 platform providers (and
its bootstrap bionic mirrors), not target platform replacements.

## Build safety

- Rootless read-only `debugfs` extraction; **no sudo or mounts**. Preserve actual
  UID/GID/mode, SELinux labels and representable Linux capabilities. Fail on
  unsupported metadata rather than resetting it to zero.
- Create symlinks last; never follow Android `/system/...` links on the host.
  Check debugfs diagnostics as well as status and dumped file lengths.
- Private work/APKTool/framework caches and a unique temporary directory. Existing
  standalone APKs/JARs, caches and the caller's temp directory are not consumed or
  deleted. All function/environment overrides and cleanup traps are subshell-local.
- Propagate every decode, patch, build, AVB, signing and verification error, even
  when sourced in a conditional where Bash ignores implicit `errexit`.
- Check the rebuilt payload's complete file set, bytes, links and Android inode
  metadata. Verify the AVB hashtree/footer against the public test key, the rebuilt
  app and outer APEX's actual APK signature against the selected platform
  certificate, and 4096-byte outer alignment.
- Publish only the verified result by a same-filesystem rename after detecting
  concurrent APEX updates. Record receipts outside the work image under
  `$APKTOOL_DIR/.bluetooth/`, bound to output bytes, source, target native inputs,
  configuration, certificate and implementation. Unknown/missing/foreign modified
  inputs are errors; hash inequality is no longer an unconditional successful skip.

Host prerequisites: `debugfs`/e2fsprogs, binutils `readelf`, Perl, a JDK 17+ and the repository's
normal Android build tools. The signature verifier uses the APK verifier already
bundled in `out/tools/bin/signapk.jar`.

## Checks and limits

Development tests and superseded Python helpers are archived under
`out/oneui9-shell-migration-20261026/retired-source/`, not loaded by the build.

Transaction fixtures mock Android builders/signers and are **not** firmware-build
proof. The separate private sandbox at
`out/oneui9-remaining-fixes-20261026/bluetooth/` retains real-donor replay scripts,
native proof, stage logs, final package and exact validation results.

The final real `full-08` replay completes extraction, selected patches, app rebuilding,
payload rebuilding, AVB signing/verification, outer repack, APK signing and an
idempotent rerun. Final-package inspection preserves all original inode metadata,
framework JAR and JNI bytes; the payload is stored at ZIP offset 4096. All
**5,879 classes** match pristine code plus the two selected patches, allowing only
DEX's equivalent elision of explicit static `false`/`null` defaults in nine
classes. Modified signed bytes, a wrong certificate and a modified AVB payload
are independently rejected. See `REPORT.md` in that directory for exact hashes.

No device operations are performed by this module audit. Static ABI/packaging
checks do not prove successful binder/SELinux/TEE responses, key compatibility,
bond persistence or Bluetooth communications on the phone. Those require a
parent-controlled, separately authorized device test; no success is fabricated.
