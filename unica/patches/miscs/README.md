# Miscellaneous policy patches

## One UI 9 RescueParty

The original module made `RescueParty.-$$Nest$smisDisabled()` return true.
One UI 9 moved that same implementation from `services.jar` into
`com.android.crashrecovery/javalib/service-crashrecovery.jar`. The One UI 9 root
customization patches the actual Mainline bridge, not Samsung's unrelated
`SecRescueParty`. All four package-failure/boot-loop observer entrypoints
check it before offering or executing mitigation. Watchdog and rollback
observers, the lifecycle service, and the original factory-reset policy
remain present. Persistent properties cannot re-enable that bridge.

The reviewed input is the source SM-S942B_INS compressed APEX, SHA-256
`810151b9dacdfe81baac963f3077d4a27e9e9f506bb6897cc95d2afa8d698c0f`.
Unexpected or already-repacked inputs fail rather than silently skipping
the policy. To rebuild, start from the original source APEX.

Packaging follows the original `target/a53x/patches/bluetooth/customize.sh`
pattern, entirely in this module's root `customize.sh`:

- Extract the source CAPEX's `original_apex`, verify its AVB payload, and
  mount it **read-only**. Copy its actual file modes, UID/GID, and SELinux
  labels, rather than supplying synthetic payload permissions.
- Apply the ordinary `.patch` and rebuild the Mainline JAR using the
  unchanged `scripts/apktool.sh` in private work/cache paths.
- Rebuild ext4 using the unchanged `scripts/build_fs_image.sh`. Generate and
  verify a real SHA256_RSA4096 AVB hashtree, with SHA256, no FEC, flags and
  rollback index zero, manifest-derived salt, and the source's
  `apex.key:com_google_android_crashrecovery-image` descriptor. Embed the
  matching public key from the existing UN1CA AVB key.
- Sign the outer APEX using the original platform-key selection:
  `aosp_platform` for unofficial builds, `unica_platform` for official
  builds. Missing official keys are an error, never a fallback. This is a
  genuinely re-signed UN1CA artifact, **not** a claim to possess Google's
  original signing keys or signature. Check 4096-byte alignment and exact
  preservation of both manifests after rebuilding.
- Publish a normal `com.google.android.crashrecovery.apex`, removing the
  old compressed wrapper and its now-stale digest. Remove the original
  Google source-stamp marker rather than misrepresenting it as covering
  new bytes. Update filesystem metadata through original UN1CA utilities.
  Delete only the source preopts for the changed Mainline JAR.

The module does not alter APEX verification, AVB verification flags,
boot-state properties, SELinux, core packaging utilities, or framework
identity. An interrupted or failed patch/build/sign operation does not
publish the candidate APEX. Runtime activation and mitigation behavior
still require a device test; static packaging checks are not that test.
Because this is re-signed, Google's existing `/data/apex` updates and future
Google-signed Mainline updates are not signer-compatible with the rebuilt
module. No update-signature bypass or userdata migration is installed.
