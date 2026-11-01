# Next-vsync Colors dream, preserving Samsung's signer

The One UI 9 root customization implements the QPR2 scheduling change through
`framework.jar`, not by rebuilding/re-signing `BasicDreams.apk`. SDK36 is unchanged.

Only a 25-ms `Choreographer.postFrameCallbackDelayed` request from the exact
`com.android.dreams.basic.ColorsGLRenderer` callback, with bound application
package `com.android.dreams.basic`, becomes a zero-delay/next-vsync request.
Callback identity, initial scheduling, cancellation, null-callback errors and
Samsung EGL failure handling are retained. Other callbacks, packages and delays
keep their original behavior; this is not a global frame-rate override.

The root checks complete `framework.sha256` and `apks.sha256` contracts before
applying the ordinary framework patch. The [reviewed metadata refresh](../ORIGINAL_APPS.md)
adds one exact BZJA APK identity without replacing the original baseline. The
original APK, manifest, non-platform Samsung signature,
UID/data identity, resources and version remain unchanged. The old direct-APK
patches stay inactive; the configured platform signer cannot preserve this APK's
identity. Do not activate those patches or copy an unsigned proof APK.

`ro.unica.qpr2.dream_vsync=true` records successful source application only, not
measured device scheduling/power or full One UI 9.5 parity. Different app/framework
versions require review rather than blind contract regeneration. Existing-data,
ART/boot, dream lifecycle, vsync timing, power and thermal behavior still require
separately authorized device validation.

Private complete-DEX assembly, source/signature contracts and 72 bounded guard
cases are retained at `out/oneui95-close-gaps-20261027/signing/`. The guard cases
are instruction/contract models, not an ART/display-runtime test.

`out/oneui95-close-gaps-20261027/signing/integrated/RESULT.json` passes the source blocks
through original helpers on the already merged framework, complete DEX4/5
assembly/archive re-decoding and zipalign, guard/repeat failures and exact
original APK v3-signature/metadata preservation. This remains an incremental
offline proof, not a new whole-ROM build or runtime qualification.
