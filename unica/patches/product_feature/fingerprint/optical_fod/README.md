# One UI 9 r9s optical fingerprint port

**Status: Java/services/UI and the explicit native allocation bridge are
implemented; shared selection, DEX rebuilds and host contracts pass. Device
qualification is still required.** See [NATIVE.md](NATIVE.md) for the real usage
path and its limits. No SDK36 compositor/runtime is imported.

Audited inputs: `SM-S942B_INS`, One UI 9/OneUI90000,
`google_touch_display_ultrasonic` -> `SM-G990E_THL` r9s, ESSI,
`google_touch_display_optical,settings=3`.

## Deliverables

- The product-feature module's root `customize.sh`: real `DECODE_APK`/`APPLY_PATCH`, and
  optical floating feature / local-HBM=0 / self-mask-version=0 configuration.
- Ordinary `.patch` files and `contract.json`: exact One UI 9 owners and method
  anchors, including the ViewRootImpl/native-usage changes.
- Root native build logic and `consumer_usage.c`: ARM64 JNI bridge and one One UI 9 libui
  instruction admitting r9s's legacy HIDL consumer-usage bit. SurfaceFlinger,
  libgui, runtime and vendor libraries stay unchanged.

Implemented changes cover sensor-type/SPF mapping, compiled ultrasonic feature
corrections, optical SystemUI feature selection, keyguard/Settings mask ownership
and cleanup, shade/bouncer extension flags, captured-blur sizing, optical warning
resources and enrollment exclusion while SurfaceFlinger surface-update debugging
is enabled. The debug query uses the shipped Settings protocol, transaction
`0x3f2`; a failed query does not report enrollment-safe success.

The source One UI 9 BiometricSetting is retained: its optical client factory,
controller, software mask/light source, HBM state machine and calibration code
already exist. Authentication callbacks, listening eligibility, lockdown,
two-step verification, permission enforcement, sensor strength, HAT handling and
HAL error processing are not replaced with success stubs. Mask helpers do not
start or approve authentication.

## Integrated selection

`unica/patches/product_feature/customize.sh` applies this port **instead of the
entire legacy fingerprint block**, before generic SPF replacements or donor
imports. Selection requires source One UI 9 ultrasonic → r9s SDK36 optical/ESSI,
and the exact measured native cohort must pass preflight before any other
product-feature mutations. Other transitions remain fail-closed. SDK36 retains
its original route. No blanket removal of capability guards is used.

The ViewRootImpl insertion runs only for the actual biometric package, mask
window type `0xa3b`, and `surfaceType=4`. It requests usage through the existing
locked consumer API before the queue exposes its producer. A failed request
throws with its actual status, rather than presenting an unmarked mask as ready.
The source optical controller still owns visibility, HBM lifecycle and HAL work.

## Validation receipts

All paths below are relative to the repository root.

Final combined replay (after the selected Camera/platform work):
`out/oneui9-four-ports-20261025/combined-final/r9s/result.json` and
`out/oneui9-four-ports-20261025/combined-final/r9s.log`.
The independent replay is retained at `optical/shared-native-final/` in the
same task directory.

- Actual shared preflight and both hardware dispatch sections executed; no
  legacy donor import or legacy native patch ran.
- Real floating-feature writes preserve the mass Camera V1 codec selection;
  all 50 preceding Camera work files are checked and its input seed is unchanged.
- 18 changed One UI 9 classes; five generated patches applied by real `APPLY_PATCH`.
- Changed-class assembly passed; all 25 introduced field/method references resolved
  against shipped source definitions and its ART boot JAR, with call-kind checks.
- Seven resource IDs checked directly against original One UI 9 APK tables using
  the existing bundled aapt2; hashes/names in `combined-final/r9s/resources.json`.
- Both services DEX041 logical units retained: 9,252 and 9,667 classes.
- Unsigned source APK/JAR repacks under `combined-final/r9s/unsigned/`; non-DEX resources
  and manifest remain byte-identical. Generated patches and per-class receipts
  are under `combined-final/r9s/apktool/.optical-fod/`.
- Lockdown/listening-policy preservation and three unsupported-route rejections
  passed. Firmware inputs remain unchanged; the sandbox has the exact one-bit
  One UI 9 libui edit and the linked bridge. The native receipt contains all hashes.
- Eight compiled-native contract/build tests pass; unsupported cohort and
  mask-scope/error cases are included. No Android native consumer was executed.
- Ancillary SystemUI `ui/after-official-02` passed **plan-only** validation:
  `out/oneui9-four-ports-20261025/optical/final-checks-01/ancillary-result.json`.
  That ancillary tree was not modified, assembled or repacked.

Development replay tools and the superseded Python helpers are archived under
`out/oneui9-shell-migration-20261026/retired-source/`, not loaded by the build.

Only affected class slices and bounded native inputs are copied; firmware and
supplied decoded trees remain read-only. The boot JAR is the actual source
One UI 9 ART APEX member, not a host JDK classpath.
Earlier failed receipts are retained, not overwritten.

### Limits of these tests

API29 selects valid **DEX039 encoding**, not a platform/minSdk downgrade. The
installed writer rejects API36/37 and emits invalid old-header/magic041 output
for API35. The test therefore normalizes the source services DEX041 container
to conventional DEX039 multidex, retaining every logical unit. This does not
validate a production apktool DEX041 roundtrip or a complete ROM build.

No ART verifier, phone, fingerprint HAL, HBM transition, enrollment, unlock,
screen-off/AOD, keyguard cancellation or compositor/vendor runtime was executed.
Successful assembly/repacking is not proof of illumination or authentication.
No commit, flash, firmware-input modification, SDK36 native import or fake
HBM/authentication success is included.
