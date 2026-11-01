# Downloads Unicode predicates — prepared, not safely deployable

The One UI 9 root deliberately keeps the original Samsung-signed DownloadsProvider.
Neither ordinary patch here nor the identification patch is applied by that root.
Adding a patch file is **not** deployment or feature parity.

`0001` supplies the QPR2 raw-or-normalized/default-ignorable-filtered check for
external `Android/(data|obb|media)` paths. `0002` additionally covers Samsung's
separately inlined private `Android/(data|obb)` check inside destination-path
validation. Both routes are needed. The second patch depends on the first and
retains canonicalization, exception handling, existing package/permission/AppOps
checks and the rejection branch. No database/schema or public API changes.

Private smali/resource assembly and 16 bounded path fixtures pass, including
supplementary default-ignorable code points. See
`out/oneui95-close-gaps-20261027/signing/REPORT.md`. Those test APKs are unsigned
and must not be installed or substituted into a ROM.

The deployed APK belongs to `android.media` alongside five other genuine
media-signed packages. Its signer SHA-256 is
`02280123f03cf1d289a3861390becbcc0cadd5000d16b484251ce0fd99004652`.
The original build helper re-signs rebuilt APKs with its platform key, which is
not that media identity. Copying old signatures, inventing a key, changing shared
UIDs, re-signing the whole cohort or weakening signature authorization does not
preserve this contract. Keep the original signing helpers unchanged.

Safe activation needs an authorized matching media signing service or a correctly
signed revised original APK containing both changes, followed by package-specific
integration and data/runtime qualification. Do not send private keys merely to
continue analysis. Samsung's current downloads database schema is 116; a wholesale
GSI replacement uses 114 and is not an established installed-data migration.
