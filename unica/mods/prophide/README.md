# Prophide

**One UI 9 implemented and host-verified; physical boot is not yet qualified.**
SDK36 keeps its original implementation. Unsupported source SDKs, native
providers, targets and firmware fail explicitly instead of silently skipping.

This changes the global presentation of the original 13 boot/AVB/warranty and
vendor-security-patch properties. It does **not** lock the bootloader, restore
verified boot, change hardware attestation or guarantee an integrity verdict.
Already-copied/cached values in running consumers are not invalidated.

## One UI 9 handoff

1. At `service.bootanim.exit=1`, platform init asynchronously starts
   `/system/bin/prophide_stage` as **system UID**, in its own core domain, with
   an init-opened **read-only** vbmeta FD. The native helper never reopens the
   block device, executes a shell, acquires capabilities or transitions to init.
2. The helper checks FD access mode, block type/device identity and AVB geometry,
   then hashes exactly 9,344 image bytes and the 1,032-byte key at offset 8,288.
   Both digests are 64 lowercase hex characters, without the filename suffix
   incorrectly captured by the original `sha256sum -b` command substitution.
   It publishes only ordinary private staging properties.
3. Platform RC performs the original 13 assignments. A pinned ordinary
   `init.hex.patch` redirects one call **after `CheckPermissions`**. Its adapter
   requires kernel-supplied peer **PID 1, UID/GID 0**, a real socket and the exact
   property/value allowlist. All other calls retain `PropertySet(..., false)`.
4. Approved calls reuse init's actual Bionic find/update/add imports without
   `PropertyChanged`, preserving `rezetprop -n` event semantics. Existing long
   read-only records are rejected using Bionic's **bit-16 long-value flag** and
   inline-length bound, avoiding an unsafe short-record update. This is a narrow
   write-once exception **inside init**, not an unchanged init trust boundary.
5. The helper verifies 12 actual readbacks. SELinux forbids this core domain
   from reading the vendor warranty property (`vendor_default_prop`), so init
   publishes that actual readback through a separate **init-only** result type.
   The helper cannot forge it. `result.done=1` means handoff finished, **not**
   successful hiding. Only **`sys.unica.prophide.status=verified`** means every
   readback matched; failure attempts `failed` and exits nonzero. Waiting is
   bounded to 30 seconds.
   Repeated starts reverify an already-completed handoff.

The 13 writes are not an atomic transaction. Partial failures are reported,
not rolled back or disguised as success. Runtime vbmeta contents are hashed
as read, not replaced with an installer-time stock digest.

## Policy and build boundaries

- No source neverallow is removed/weakened, no domain becomes permissive, and
  the helper gets no protected-property setter or property-area write grant.
  Init already has the required authority. One UI 9 installs **no `rezetprop` or
  `init_exec`-labelled helper**.
- All four target vbmeta nodes use `vbmeta_block_device`. The helper has only
  read/getattr on that block type, not open/write/ioctl or generic block access.
  FD/library access and some general execution permissions are inherited from
  stock domain rules; no new shell grant is added and the helper has no shell
  calls. This is not a claim of a syscall sandbox.
- Adding a domain exposed an inherited API30 charger-property read grant.
  Ordinary common/r9s patches subtract **only `prophide_stage`** from that grant.
  Existing domains, mapping members and donor assertions stay unchanged.
- Root `customize.sh` checks source SDK/security patch, stock target vbmeta,
  bootstrap/crypto providers, payload checksums, init input/output hashes and
  conflicting declarations before installation. Reapplication is byte-idempotent.
  Original build scripts/signing remain in use; no test fixture is installed.
- Reviewed targets: `o1s`, `t2s`, `p3s`, `r9s`, with their pinned AUT/THL firmware
  and current SM-S942B_INS One UI 9 source/security patch `2026-10-05`.

## Native identity / reproduction

Original init SHA-256:
`78d3644ddc9021364864e5dcdb41e400f28071c0da74b8a6da47171ede4bbb1b`.
Patched init SHA-256:
`1b3d2850aa95e88320ee6fb0cc14f0f9640aa8b7953337a4481e58fb2eb83274`.
The 1,509-byte adapter occupies existing RX padding at ELF VA `0xb57100`.
That segment now ends at `0xb576f0`, before the next segment at `0xb58000`.
No added segment, W+X mapping, relocation or init dependency.

`init_adapter.c` and `init_adapter.ld` reproduce the payload with Clang
21.1.8: `--target=aarch64-linux-android37 -O2 -ffreestanding -fPIC -fno-builtin
-fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables
-mbranch-protection=standard`. Link with LLD using that script and
`stock_property_set=0x98232c`, `stock_property_find=0xb55280`,
`stock_property_update=0xb55298`, `stock_property_add=0xb552c8` as `--defsym`
values, then extract `.prophide` as binary. Payload SHA-256:
`bf4f7d93e7edcf7ecc9b51fb7a2a498945571c6313c0c5a521a95947a04e31cd`.

`prophide_stage.c` is the shipped PIE helper's source. It links only actual
One UI 9 libc/crypto providers, with full RELRO, immediate binding, NX stack, stack
protection and BTI/PAC. Its local build used Clang 21.1.8 with AArch64 LP64 Linux
headers for standard ABI declarations (`__errno_location=__errno`); no GNU libc
code is linked. The stat layout is compile-time asserted. Exact build commands
are retained in `out/oneui9-full-adaptation-20261026/prophide-fix/native/helper-build.json`.
ROM builds use the checksum-pinned helper without a new toolchain step.

The local helper rebuild command, from the repository root (output kept private):

```sh
LIB="$PWD/out/fw/SM-S942B_INS/system/system/lib64"
clang --target=aarch64-linux-android37 --sysroot=/usr/aarch64-linux-gnu \
  -isystem /usr/aarch64-linux-gnu/include -D__errno_location=__errno \
  -O2 -fPIE -fvisibility=hidden -ffunction-sections -fdata-sections \
  -fstack-protector-strong -mbranch-protection=standard -Wall -Wextra -Werror \
  -nostdlib -fuse-ld=lld -pie \
  -Wl,-e,_start,--gc-sections,--no-undefined,-z,relro,-z,now,-z,noexecstack,-z,max-page-size=16384,--build-id=sha1 \
  -Wl,--dynamic-linker=/system/bin/bootstrap/linker64 \
  -Wl,-rpath,/system/lib64/bootstrap:/system/lib64 \
  unica/mods/prophide/prophide_stage.c \
  -L"$LIB/bootstrap" -L"$LIB" -lc -lcrypto -o /tmp/opencode/prophide_stage
```

Expected helper SHA-256:
`e2bb42517b4c792e1a157d20ee42c142dd6b9704f1364a947feebccca81bdf3a`.

## Verification limits

Private evidence: `out/oneui9-full-adaptation-20261026/prophide-fix/`.
Four original installer/repeat replays and strict full-policy formats 30/31
pass, alongside 234 adapter/callsite cases per CPU, genuine Bionic update/add/
long-record tests on Cortex-A55/A76/max, 24 helper/RC cases and 22 build negatives.
Both stock and original-pipeline flag-patched vbmeta images pass for all four targets.
Helper fixtures simulate FD delegation/block kind, property-service dispatch
and init credentials; the helper ELF, crypto, Bionic, RC assignments and native
adapter are real. **No full init, enforcing Android runtime, phone boot or
complete ROM build was executed.**
