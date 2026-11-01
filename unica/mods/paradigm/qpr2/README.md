# QPR2 backports in Paradigm

The existing SDK-36 Paradigm features remain in their original folders. The
One UI 9 branch applies the separate ordinary `.patch` files in this folder to the
reviewed SM-S942B_INS donor (CP2A.260605.016). It does not replace newer Samsung
Galaxy features with the older S25 APKs, weights or native libraries.

`unica/mods/paradigm/customize.sh` is the only customization entry point. The
39 feature bodies are incorporated there, in their reviewed order and with
their original child `MODPATH` values. The child folders retain all payloads,
contracts and ordinary patches; they contain no customization wrappers. The
root is sourced directly by the original builder, never under `||` or a
feature-function wrapper that suppresses Bash errexit inside builder commands.
There is no patch adapter in `scripts/`. The builder compiles all affected
APKs/JARs and uses its existing platform key.

The isolated One UI 9 build includes the native camera metadata schema, matching
framework Path conversion, and a separate, real CPU human-segmentation preview.
They are **not** a working live Camera2 subject-segmentation SessionProcessor.
The JNI/CPU model and app-local webcam libraries retain their payload checksums.
The reviewed One UI 9 profile includes complete original-signed QPR2 sdkext and
tzdata modules, plus libsonic, libspeexresampler and libETC1 for arm64. Their
finite source set is in `prebuilts/qpr2`. Payload/container signing identities,
retained-runtime contracts and source/current hashes are checked before copying.
`UN1CA_QPR2_MAINLINE=false` or `UN1CA_QPR2_CPU_LEAVES=false` disables the respective
optional component set. This is not a replacement of all APEX or native libraries.
Profile values and the exact finite mainline/runtime/CPU-provider lists are
validated before any Paradigm writes. An empty, truncated or duplicated list is
an error, not permission to stage a partial cohort. Changing a reviewed list
requires updating and requalifying its source contract; do not refresh hashes
just to bypass a mismatch.

The compiled Samsung framework base is still 37.0. The user-selected build
branding reports CP4A.261005.017.S942BXXU5CZJJ, SDK-full 37.2 and One UI 90500;
`patches/__props/QPR2-VERSIONS.md` distinguishes those labels from implemented
APIs. The original base is recorded in `ro.unica.qpr2.base.*`, and the GSI origin
in `ro.unica.qpr2.source.*`. Knox remains the actual 3.14 / API 41. Original S21
vendor and hardware API levels are retained. APK targetSdkVersion stays the major
integer 37: Android does not support targeting minor 37.2 in the manifest.
Floating features belong to `patches/__floating_feature`, the
existing product-feature/camera patches and target/platform `sff.sh` files.
No invented Samsung feature flags are used for the preview.

The r14 app additions are separate ordinary patches: SoundAlive's connected
audio-device information panel uses QPR2 MusicFX discovery and a listener scoped
to the open panel. Magnifier's Settings-button hold action exposes QPR2-style
zoom choices through the native discrete slider and camera presenter. Both apps
use the shared glass material behind existing controls, preserving native ripple
feedback and original control types. The same existing UN1CA APK key is reused.

The explicit `UN1CA_QPR2_RUNTIME_COHORT=trial-r15` profile adds separate complete
ART and Conscrypt candidates. `runtime_cohort` checks both inputs before either
copy; `art_runtime` and `conscrypt_trust` contain their patches and evidence
scope. It includes a real dual-ABI syscall companion and all 146 Samsung/QPR2
trust anchors. Its full 57-JAR/34-service odrefresh cache passed offline checking
and actual image/JNI/TLS execution. Phone boot, SELinux, odsign authentication
and installed /data APEX signer migration remain distinct unresolved checks.
The default is `off`; host-generated cache files are never installed by it.

The measured 26 October bootloop profile uses the original Samsung ART
371000140 and Conscrypt 370549380 with QPR2 sdkext/tzdata 373040040. Tests of
the optional r15 ART/Conscrypt pair do not validate that default combination.
It has now passed separate offline classpath generation, compilation and
core/JNI/ICU/default-trust execution using the retained runtime linkerconfig
generator. APEX activation and a complete phone boot are still unproven.
The separate diagnostic system image restores only the two original Samsung
sdkext/tzdata containers and marks its comparison profile; the production
work_dir, kernel images, other APKs/APEXes and permanent feature selection
remain unchanged. Do not label this comparison a confirmed boot repair.

The separate opt-in `UN1CA_QPR2_SWCODEC=true` adds the original-signed whole
373040140 software-codec APEX. Its existing 38 codec entries and isolated
namespace remain intact; in-process MP3 and FLAC are added and were executed
with real audio on both native ABIs under emulation with CFI enabled. The
reviewed 37.2 property profile is required before installation because the
new xHE-AAC implementation enforces its real minor-API gate. This option
defaults to `false`; it does not patch that gate or claim hardware validation.
The r16 current-JAR odrefresh cache and Conscrypt TLS checks were regenerated
after preserving seven changed framework/service JARs and updated Bluetooth.

A successful image build alone does not validate Camera2/ISP sessions, physical
USB webcam operation, graphics/Skia, private NPU jobs, EDEN leases, Vulkan
DEVICE_LOST, Kmx attestation or app-zygote/watchdog behavior. Do not install a
standalone framework.jar on a running device; its boot-classpath cohort must be
handled by the ROM build. Nothing in this feature patch flashes the phone.
