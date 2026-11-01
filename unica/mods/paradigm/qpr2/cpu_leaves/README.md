# QPR2 CPU leaves

This normal UN1CA module imports three exact arm64 libraries from the user's
local CRB `android17QPR2gsi/ROM`, CP41.260831.007.A3. It does not bundle a GSI,
modify `scripts/`, add a universal adapter, or alter any APK signing identity.

The r14 One UI 9 profile selects these three pinned inputs by default, from
prebuilts/qpr2. The original source files and digests are recorded there.
The SDK-36 profile is unchanged. An explicit external source remains supported:

```sh
export UN1CA_QPR2_CPU_LEAVES=true
export UN1CA_QPR2_GSI_DIR='/mnt/g/crb_327_Patched/crb_327/Projects/android17QPR2gsi/ROM'
```

All input and retained-provider hashes are checked before the first copy.
`ADD_TO_WORK_DIR` handles the normal image filesystem metadata. No runtime APEX,
libc++, ARM32 library, vendor HAL, Mali r54 driver or boot image is replaced.
An unreviewed cohort aborts instead of disabling checks or extending a namespace.

The root's shared, read-only runtime check also serves camera metadata and the
optional software-codec/ART profiles. It accepts the exact donor APEX or reads
the post-VNDK signed payload and compares every original provider, symlink,
UID/GID, mode and SELinux label against the pinned One UI 9 donor. It does not
trust a receipt's claim, call a removed VNDK dispatcher, or rerun the graft.

Offline evidence: real Android arm64 binaries ran on unmodified Samsung Bionic,
under QEMU Cortex-A55 and Cortex-A76 CPU profiles (no SVE). The old and new libraries produced equal results
for 24 Sonic rate/channel/speed cases, 12 Speex resampling rate/quality cases and
10 ETC1 RGB/RGB565 texture-size/round-trip cases. Existing exports and SONAMEs
were retained, with no new DT_NEEDED dependency and no exported JNI entrypoint.

These are finite CPU tests, not complete equivalence, a physical-device boot
test, camera pipeline validation or a Vulkan DEVICE_LOST fix. The component can
be disabled with UN1CA_QPR2_CPU_LEAVES=false. Reapplication accepts only the
original baseline or the exact already-reviewed replacement.
Source files remain on G: unchanged.
