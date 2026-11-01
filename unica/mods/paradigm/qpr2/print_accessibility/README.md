# Print preview selection state, preserving Samsung's signer

The One UI 9 root customization adds localized selected/not-selected accessibility
state descriptions through `framework.jar`. It never rebuilds or re-signs
`PrintSpooler.apk`; SDK36 is unchanged.

`LinearLayout.setSelected` first performs its original superclass behavior.
Only the exact final `com.android.printspooler.widget.PreviewPageFrame` class,
under context package `com.android.printspooler`, then receives the appropriate
state description. This matches the QPR2 app override while retaining the
original app's CompoundButton-like checkable/checked accessibility semantics.
Other layouts keep their original behavior. Existing Samsung framework string
fields/localizations are used, not copied GSI resource IDs.

The root verifies complete `framework.sha256` and `apks.sha256` contracts before
applying the ordinary framework patch. The [reviewed metadata refresh](../ORIGINAL_APPS.md)
admits one exact BZJA APK identity while retaining the original baseline. The
original APK, manifest, Samsung signature, UID/data identity,
private job/PDF persistence and app resources/version remain unchanged. Direct
APK/identification patches remain inactive: the configured platform signer is
not this app's signer. Do not copy an unsigned proof artifact into the ROM.

`ro.unica.qpr2.print_accessibility=true` records successful source application,
not measured TalkBack behavior, installed-data compatibility or full One UI 9.5
parity. New app/framework revisions need reviewed contracts. ART/boot, selected/
unselected announcements and existing print jobs require separate runtime tests.

Private complete-DEX assembly, original resource/signature contracts and 18
bounded guard cases are retained at
`out/oneui95-close-gaps-20261027/signing/`. The guard cases are instruction models,
not actual accessibility-service or device execution.

`out/oneui95-close-gaps-20261027/signing/integrated/RESULT.json` verifies the root/helper route
against the previously merged framework, complete DEX4/5 and aligned-archive
re-decoding, source/manifest/repeat rejection and exact original APK bytes/v3
signer/metadata. This is an incremental offline proof, not a new whole-ROM build.
