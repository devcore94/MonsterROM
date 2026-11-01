# One UI 9 Settings NFC antenna adaptation

The complete One UI 9 NFC APEX remains paired with the target NXP HIDL service.
Settings is a separate app: both its NFC page and guide dialog inline donor
antenna position `27`. On t2s the genuine vendor property is `1` (CENTER), so
the native consistency check throws and closes Settings. This was captured from
the rooted device, not inferred from a source-only build.

The module-root `customize.sh` changes only those two literals to the actual work-vendor
property and preserves every existing mismatch/error branch. It also copies the
genuine target APK's corresponding day/night Lottie compositions over the
One UI 9 DEFAULT enum's existing animation resource, retaining its IDs and Java ABI.
Changing only the literal would leave the donor M1 antenna illustration behind.
No target APK, Java class, NFC stack, JNI or platform runtime is transplanted.

Positions 0–22 follow the inspected target SDK35 `NfcAntennaInfo` enum, including
its resource aliases. Position 27 selects the generic resource from a matching
target APK. Missing/unknown vendor positions, missing/ambiguous target art,
external image dependencies, source method/enum/resource-layout drift and
invalid JSON fail before any decoded file is written. No vendor property is
spoofed and no NFC check is disabled. Unchanged inputs are repeat-safe.

Development tests and the superseded helper are archived under
`out/oneui9-shell-migration-20261026/retired-source/`.
Source/target/installed APK identities, crash logs and complete integrated APK
rebuild receipts live under `out/oneui9-remaining-fixes-20261026/`.
Device diagnostics are read-only; rebuilt changes still require authorized
deployment and Android UI/NFC-hardware validation.
