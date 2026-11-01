# Retained Floppy/r54 build cohort

The earlier kernel-only repair recommendation is withdrawn as an explanation
of the reported One UI 9.5 APEX bootloop. A measured kernel/module mismatch
does not establish that it initiated that boot failure. The APEX investigation
and its separate comparison image leave the installed kernel unchanged.

The One UI 9 ROM stages the pinned Floppy source base `113ce9d986f7` with Mali
`r54p3-01eac0` (UK 11.46), its own vendor-boot modules and its vendor-partition
modules together. The reviewed uname-only variant below is built from that
same base, not a different kernel/driver release. The build verifier checks the
kernel, both module sets, DTB/DTBO and matching userdata-encryption contract.
The retained kernel uses `selinux_mode=2` / always-permissive as selected; this
does not remove the separate strict offline platform/vendor policy checks.

## External kernel ZIP compatibility

The published `Floppy_v1.1.2-KSUNext-SUSFS-exynos2100-20261021-2157.zip`
contains a different build, `dde5201b5006`, with `mali.version=r38p1`.
Installing it over this ROM changes boot and vendor_boot while the read-only
vendor partition retains this ROM's r54 module set. Keeping the visible
Floppy version number at 1.1.2 does not make those build cohorts equivalent.

The 26 October S21+ read-only diagnosis verified all 36 retained vendor files.
The installed external kernel differed only in its selected uname-BPF and
SELinux configuration bytes from that published r38 image. Its overlapping
ramdisk modules had `module_layout` CRC `654e740b`; retained vendor modules had
`ae700a76`, with additional imported-symbol CRC differences. This is a real
module ABI mismatch, beyond a different displayed kernel version.

Restore the matching boot.img and vendor_boot.img as a pair from the same
reviewed ROM build when resolving this mismatch. DTBO was already identical
in that diagnosis. Do not replace only the kernel while retaining a foreign
vendor ramdisk, or install the separate r38 package over the r54 ROM afterward.

The initiating Android/kernel crash was not captured in that run. Recovery
buffers and the one permitted diagnostic restart do not establish that a
repaired cohort has booted. No automatic flash, userdata formatting, key
deletion, capability bypass or new driver fallback is implemented here.

## Retained first-stage panic and exact module-set checks

A later read-only capture on 26 October retained a specific, earlier panic from
`5.4.302-Floppy-v1.1.2-KN-g2c0ee7d2e6e3-dirty`: `dwc3.ko` could not resolve
`is_usb_aoffload_disabled`, and `exynos_gpex.ko` exported
`exynos_migov_set_gpu_margin` already owned by that kernel. First-stage init
reported `Failed to load kernel modules`, exited with status 127 and triggered
`Attempted to kill init`. This establishes that captured attempt's failure, not
the initiating cause of every later APEX/Android bootloop.

The phone was in TWRP during collection. Its current boot readback instead had
`5.4.304-Floppy-v1.1.2-KN-gfec6ba70690d`, with that external build's ramdisk
modules; it was not the pinned `113ce9d986f7` cohort. Recovery log history also
records separate kernel installs, a boot-only restore and userdata formatting.
Raw private evidence is retained under `out/oneui9-phone-logs-20261026/`, not in
tracked test fixtures. No phone image, mount, service or userdata was changed by
this capture. A stale pstore panic must not be labeled as a new Android crash.

The package verifier now requires the **exact module/load-metadata member set**
in the vendor ramdisk and vendor partition, in addition to the existing payload
and byte hashes. Extra stale `.ko` or `modules.*` files and vendor-module
symlinks fail before a successful staging receipt is written. Unrelated files
and the existing target-encryption fstab adaptation remain permitted; no
module is silently deleted and no load or signature check is disabled.

Development regression fixtures and superseded helpers are archived under
`out/oneui9-shell-migration-20261026/retired-source/`, not loaded by the build.

These synthetic image fixtures check rejection/publication behavior, not boot
success. The guard cannot prevent a separate kernel ZIP from replacing images
after ROM installation. Use matching boot/vendor_boot images from the same ROM
build; further Android fixes require an attributable Android boot/crash log.

## Unencrypted userdata policy and module ordering

New Floppy staging explicitly records `userdata_encryption_policy=unencrypted`
in `kernel/floppy-preserved.json`, as requested by the user. These builds do
**not** require encrypted userdata. Platform `miscs` invokes the Floppy root script to
remove active FBE/FDE, metadata-encryption and related key options from the
vendor `/data` and `/metadata` entries. The later fs adapter synchronizes both
ramdisk fstabs to that unencrypted contract. It rejects a vendor fstab that has
not been normalized, rather than silently claiming success.

The final verifier rejects reintroduced encryption/key flags even when vendor
and ramdisk agree, while keeping the exact kernel/module/DTB/DTBO checks. It
records `userdata_unencrypted=true` only after those checks pass. Unknown
policies, missing/duplicate mounts and incompatible filesystems remain errors.
Non-crypto options, including the `inlinecrypt` filesystem capability, are not
encryption requests and remain unchanged. Comments are not active configuration.
Other misc actions and non-Floppy behavior are unchanged.

Receipts without a policy field retain the former target-FBE behavior solely
for compatibility with older work. New staging always writes the unencrypted
policy; old image caches need no kernel rebuild or binary modification.

Firmware-independent tests cover the real misc→adapter order, unencrypted and
legacy receipts, final directory/ZIP verification and rejection without partial
fstab writes. New genuine-input replays are retained in
`out/oneui9-unencrypted-userdata-20261026/`; earlier FBE-preserving replays in
`out/oneui9-fbe-ordering-20261026/` are historical, not this requested policy.
Rerunning the normal ROM build recopies pristine target vendor inputs before
patching, so no manual work-fstab edit or cache deletion is needed.

This changes build inputs only. It does **not** decrypt existing userdata,
delete device keys or format anything. Moving an encrypted installation to an
unencrypted policy may require a destructive data format; no migration, flash
or device operation is performed automatically, and host checks are not proof
that such a migration or a complete Android boot has succeeded.

## 5.15.206 uname-spoof source variant

`uname/0001-Report-5.15.206-for-the-selected-uname-spoof.patch` changes only the
two `CONFIG_FAKE_UNAME_5_15` version strings in `kernel/sys.c`.
`uname/uname.config` switches the existing choice from 5.10 to 5.15. The
workaround description and the scoped `newuname` result therefore agree on
**5.15.206** instead of the retained configuration's 5.10.200.

This preserves Floppy's privileged BPF-loader
caller restrictions and SUSFS ordering. It does **not** replace ordinary
`uname`, change the real 5.4.304 kernel/module release, backport 5.15 features,
enable the spoof for new callers or claim to repair a kernel/module mismatch.

New staging selects the matching, separately rebuilt images and modules:

- `out/floppy-images/uname-5.15.206-bpf-option/<target>/`
- `out/kernel/floppy/install/uname-5.15.206-bpf-option/<target>/vendor/lib/modules/`

The captured Android failure rejected kernel 5.4 in `netbpfload` and rebooted
with `bpfloader-failed`. Staging explicitly adds `uname_bpf_spoof=1` for the
existing root/netbpfload-only caller gate. Source patch `0002` applies the
disabled default before argument parsing, so the explicit option is respected.
It does not broaden callers or suppress BPF load failures. The cache alone is
not the complete configuration: normal staging and ramdisk adaptation are required.

The image manifest and work receipt bind the exact patch/config-fragment hashes
and the selected uname configuration. Missing/changed provenance, image hashes,
module hashes or configuration fail before staging writes. There is no fallback
to the old 5.10.200 cache. Explicit legacy work-receipt verification still reads
the original cache for auditing previous outputs; it is not the new staging path.

The isolated build and reproduction drivers are retained under
`out/oneui9-uname-5.15.206-20261026/`: `prepare.py`, `build.py`, `verify_abi.py`,
`package.py` and `verify_integration.py`. Preparation snapshots the existing
kernel source overlay into a separate worktree before applying this patch;
old source files, caches and ROM outputs are not overwritten. Those historical
drivers required the retained private source/cache and AOSP Clang r596125.
The pinned source/publication route below no longer needs that private image
cache. A genuine full build still compiles kernel, DTBs and all 284 modules
together; it is not a binary string patch or a qualified cold build here.

The retained receipts check both compiled version references, all module
vermagic/import CRCs, test-key AVB and the normal staging/fstab path on all four
targets. These are host-build/static-package results, not a phone boot test.


## One UI 9 full BPF mode (26 October follow-up)

The source patch `uname/0003-Select-full-BPF-uname-mode.patch`
selects the requested full mode 2 as the One UI 9 kernel's compiled default. This removes
dependence on forwarding the image-header argument; the existing explicit boot
option and its precedence remain. Root/caller restrictions, the real 5.4.304
release, r54 selection, verifier and loader failure handling are unchanged.
It does not add 5.15 kernel features or establish successful device boot.

That follow-up selected the separately built `uname-5.15.206-bpf-full` cache
and matching module install root. Current staging instead selects the newer
`uname-5.15.206-bpf-bind` cohort (legacy cache or atomic publication below),
retaining compiled mode 2 and its explicit vendor-boot argument. Historical
full-mode caches remain readable for their own earlier receipts, not as a
fallback when current selection is absent or invalid.

The follow-up device log records a different installed external kernel,
`dde5201b5006`, reporting BPF version 5.10.200 and selecting r38p1. NetBpfLoad
explicitly rejects that start with `Android 26Q3 requires kernel 5.15`.
The earlier start with the first 5.15.206 image pair has a persisted reboot
reason but no surviving detailed loader message. The compiled-default change
is a conservative build-profile correction, not proof of that lost cause.

## Provisioning status: warm artifact publication tested, cold build unqualified

The normal `stage` action requires a matching image **and** module-install
cohort. It is **not** an automatic clean-host kernel builder. The root script
can now verify and publish genuine full-build outputs without old image/module
caches; see `publish-build` below. Source preparation alone is still incomplete
cold-build support. Missing/partial selected inputs fail before work-directory
changes, without substituting stock images or older profiles.

### Pinned source route

The module now carries the previously private inputs as ordinary patches:

- `source/0001-Retain-the-UN1CA-source-overlay.patch` is byte-identical to the
  saved retained overlay (SHA-256
  `fce2b6505a9c7ccc93be69d805b14f4a7f14327747029dc49e8ace5ce181fbe9`).
- `source/0002-Pin-the-retained-configuration.patch` supplies the original
  14-option `unica.config` fragment, correcting its SELinux choice to the
  **always-permissive** choice actually present in the retained resolved config,
  then adds the two existing `uname/uname.config` choices. The original fragment
  alone does **not** reproduce the final cached configuration.
- `source/0003-Pin-vendor-load-policy-and-reproducible-ramdisk.patch` pins the
  two vendor load requests common to all four pristine target firmwares. Their
  dependency closure is derived from the newly verified modules, not a cached
  `modules.dep` or previous vendor install. It also makes upstream's CPIO/gzip
  assembly reproducible when the publisher normalizes timestamps.

Run from the repository root, with an existing parent directory and a **new**
absolute destination outside any retained checkout/cache:

```bash
bash platform/exynos2100/patches/floppy/customize.sh source-inputs
bash platform/exynos2100/patches/floppy/customize.sh prepare-source /absolute/new/floppy-source
```

`prepare-source` fetches only kernel commit
`113ce9d986f74e1526981324ec164e4d90930071` from
`https://github.com/FlopKernel-Series/flop_exynos2100_kernel.git`, without tags,
and initializes only `build/mkbootimg`, pinned by that commit to
`d2bb0af5ba6d3198a3e99529c97eda1be0b5a093` at Android's official mkbootimg
repository. It applies the three source patches, the three uname patches, and the
newer selected `bpf/0001-Backport-cgroup-bind-permission-flags.patch` in order.
That bind patch is separate from the retained mode-2 base; provisioning does
not undo its newer staging selection or qualify its compiled outputs.

The pinned kernel Git tree includes `build/boot/ramdisk`, `build/vboot/`,
`build/dtconfigs/` and `build/dtb/mkdtboimg.py`. They are not missing templates
and need not be extracted from a private image cache. A GitHub source archive
alone is insufficient: it omits the mkbootimg submodule contents and Git SCM
state used in the real `5.4.304-...-g113ce9d986f7-dirty` module release.

Existing directories and symlinks are refused, even if empty/broken. A failed
fetch/apply leaves its new destination for inspection, not automatic deletion
or reuse. `floppy-source-inputs.json` records source **inputs only**, explicitly
not a kernel-build, module-ABI, cache-publication or clean-host success receipt.

### Exact compiler input, not “latest”

The retained compiler is AOSP Clang **r596125, build 15682573, version 22.0.2**.
An observed immutable source for that prebuilt is:

- Git repository:
  `https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86`
- Repository commit: `95ecb5c85cd772cae7b67dabf0a1c34c103b6351`
- Subdirectory: `clang-r596125`
- Subtree Git object: `44e59376d6231e87e4ba5545c6baa619b6d4ad54`

Read-only Gitiles metadata matched the retained `BUILD_INFO` bytes and the
actual Git blob identities of `clang`, `clang-22`, `clang-real`, `lld`,
`ld.lld`, `llvm-ar`, `llvm-objcopy` and `llvm-strip`, including symlink contents.
This establishes the precise candidate, **not** successful archive retrieval,
an independently verified complete toolchain or a valid kernel prebuilt.
No toolchain was downloaded for this investigation. Obtain that exact pinned
subtree on a suitably sized host and preserve its directory/symlink structure;
do not use upstream `CLANG_TYPE=aosp`, which scrapes the latest compiler.

### Upstream build entry point and remaining gap

Use the fetched kernel's own `build/ckbuild.sh`, not the private historical
Python/Perl build drivers. On a separate, sufficiently provisioned host, the
intended invocation is the following, **not executed or full-build-qualified
here** (replace both absolute paths):

```bash
cd /absolute/new/floppy-source
env CLANG_TYPE=custom CUST_DIR=/absolute/pinned-toolchain/clang-r596125 \
    EXTRA_CONFIG_FRAGMENTS=unica.config DEFAULT_DEFCONFIG=exynos2100-unified_defconfig \
    KBUILD_BUILD_USER=unica KBUILD_BUILD_HOST=kernel-builder KBUILD_BUILD_VERSION=1 \
    KBUILD_BUILD_TIMESTAMP='Mon Oct 26 19:53:18 UTC 2026' \
    PLATFORM_VERSION=12 ANDROID_MAJOR_VERSION=s TARGET_SOC=universal2100 \
    KERNEL_BUILD_JOBS=4 USE_CCACHE=0 USE_THINLTO_CACHE=0 \
    SKIP_BUILD_DEPENDENCY_SETUP=1 KEEP_KERNEL_BUILD_INTERMEDIATES=1 \
    DO_ZIP=0 DO_TAR=0 BOOT_OS_VERSION=16.0.0 BOOT_OS_PATCH_LEVEL=2026-10 \
    bash build/ckbuild.sh kq
```

Install host build dependencies first; this invocation intentionally skips
upstream's privileged dependency installer, latest-toolchain downloader,
AnyKernel clone and external ZIP/TAR packaging. It still compiles the whole
kernel, DTBs and modules through upstream's builder. It is **not** a command
that installs a ready-to-use UN1CA image cache. Fixed time/configuration do not
guarantee byte-identical binaries, CPIO metadata, dependency metadata or AVB.

Two independent private **Kconfig-only** replays from 2,184 pinned Git files,
using no cached `.config`, produced the exact retained resolved SHA-256:
`40971838c329afaa1c25af65392dfd99ea326595d909e2e6f110c8e94a85268f`.
They used upstream's `exynos2100-unified_defconfig unica.config ksu.config
droidspaces.config`, its normal `LOCALVERSION=-Floppy-v1.1.2-KN`, then
`olddefconfig`. This closes the source/config input gap, not the compilation
or ROM integration gap.

### Cache-independent verification and publication

After a genuine complete build, with its `out/vmlinux`, `Image`, DTBs,
`Module.symvers`, `System.map`, `.config`, `modules.order` and installed
`modules_out` still present, run from the UN1CA repository root:

```bash
OUT_DIR=/absolute/existing/output-root \
TOOLS_DIR=/absolute/existing/UN1CA-tools \
FLOPPY_CLANG_DIR=/absolute/pinned-toolchain/clang-r596125 \
    bash platform/exynos2100/patches/floppy/customize.sh publish-build /absolute/floppy-source
```

`TOOLS_DIR` is the ordinary UN1CA tools directory containing `bin/avbtool`
(defaults to this repository's `out/tools`). No compiler/tool download or
kernel compilation happens in `publish-build`. The input checkout and its
outputs are read-only; upstream packaging runs in a new private snapshot.

The publisher independently checks:

- the source base, reviewed C/source changes and exact resolved configuration;
- `Image` regenerated from that `vmlinux` with the pinned objcopy operation;
- all actual vmlinux export/provider CRC tables against **that build's**
  `Module.symvers`, also checking `System.map` export addresses;
- exactly 284 regular ARM64 ELF modules, common real-release vermagic, every
  versioned/strong import and actual module export CRC/provider, including the
  r54 version and the new compiled bind-flags export;
- the installed/built module order, complete upstream ramdisk module/load/dep
  sets and bytes, and the vendor load policy's actual dependency closure.

Upstream intentionally embeds `exynos2100-r9sxxx-stock_defconfig` (5.4.242)
through `kernel/Makefile`. The publisher checks that **pinned stock template**,
not equality with the real build `.config`, and explicitly records
`embedded_config_is_actual_build_config=false`. Do not use `/proc/config.gz`
as proof of these compiled choices. The real release stays 5.4.304.

Assembly reuses pinned upstream `post.sh`, `images.sh` and `dtbo.sh`, with
repository boot/vendor-ramdisk templates and freshly compiled device trees.
It does not read `out/floppy-images`, prior `build/images`/`build/tmp`, old
module metadata, or private historical packagers. It signs and verifies all
twelve images using the original UN1CA `SIGN_IMAGE_WITH_AVB` function,
`avbtool` and existing public test key. Original build/signing scripts and keys
are not changed. Test-key signing is not production-key or device qualification.

Only after every check succeeds, Linux `renameat2(RENAME_NOREPLACE)` atomically
publishes **one directory containing both image and install trees**:

```text
$OUT_DIR/kernel/floppy/cohorts/uname-5.15.206-bpf-bind/
  cohort.json, module-abi-proof.json, source-inputs.json, assembly.log, signing.log
  cache/<target>/{boot.img,vendor_boot.img,dtbo.img,kernel.config,floppy-build-info.json}
  install/<target>/vendor/lib/modules/
```

Existing destinations, including one created during publication, are never
replaced. Failed private snapshots are removed; no partial cohort becomes
visible. Unsupported atomic-rename hosts fail closed. To test another build,
use a different output root rather than deleting/replacing retained inputs.

Normal `stage`/`install-root` select this committed cohort when present; its
receipt binds it for subsequent directory/ZIP verification. An incomplete or
changed publication fails rather than falling back. When no publication exists,
the current bind-profile legacy cache remains supported unchanged. Historical
work receipts without a publication identity still verify against their own
legacy cache, even if a newer publication now exists.

Published cache images are build inputs, **not flash-ready outputs**: the normal
staging, unencrypted userdata/fstab adaptation and final signing still follow.

The warm test used the existing current bind build read-only: 284 modules,
15,904 strong imports, 16,188 version records, all kernel/module exports and
the derived 32-module vendor closure passed. All four newly assembled targets
passed the original Floppy→misc→fs→AVB→directory/ZIP pipeline. Corruption,
signing-failure, repeat-destination and mid-publication no-clobber tests passed.
No manifest's ABI booleans are accepted as a substitute for these ELF checks.

**Still unqualified:** a complete remote source/submodule/toolchain retrieval
and clean full upstream compilation through this pinned recipe, a full ROM
build and physical boot/BPF loading. Warm artifact publication plus static/host
replays do not establish any of those. AVB uses the existing random salt flow,
so signed-image hashes need not repeat even when payloads do.

Private narrow tests and metadata evidence:
`out/oneui9-full-adaptation-20261026/kernel-provision/`. They cover deterministic
source patches/configuration, duplicate-patch rejection, all four missing-cache
errors, existing dirty destinations/broken symlinks, failed fetches and wrong
revisions. No full kernel compilation, retained source/cache change, ROM output
replacement or phone operation was performed.

The publication follow-up lives separately under
`out/oneui9-full-adaptation-20261026/kernel-provision/publication-followup/`;
earlier source-only reports remain historical, not current publication status.
