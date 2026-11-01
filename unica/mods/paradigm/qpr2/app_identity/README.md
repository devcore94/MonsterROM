# QPR2 app identity helpers for Samsung One UI 9

This ordinary Paradigm patch adds three methods directly from the local CRB
`android17QPR2gsi` framework, build `CP41.260831.007.A3`:

- Public QPR2 `Process.areUidsForSameApplication(int, int)`.
- Internal `PackageUtils.computeSignaturesSha256DigestsBytes(Signature[])`.
- Internal `PackageUtils.toHexString(byte[])`.

The UID comparison normalizes a Private Compute Core UID to its corresponding
app UID before comparing complete UIDs. Different Android users stay distinct;
an SDK-sandbox UID is not treated as a PCC alias. This method compares values,
including equal negative inputs; it is not UID validation or authorization.
Samsung's UID constants, native declarations, class initializer and existing
PCC mapping methods remain intact. In particular the existing Samsung mapping
method's hidden-API visibility is retained.

The raw-digest helper preserves signature order and duplicates, returning one
SHA-256 byte array for each `Signature.toByteArray()` result. It calls Samsung's
existing digest implementation. The hex helper uses retained HexEncoding with
uppercase output and returns null for null input. These helpers do not parse
or verify a certificate, replace an APK key or change signature verification.

Only three method bodies are added, with their exact original access/hidden-API
metadata. Process remains in classes3.dex and PackageUtils in classes4.dex.
`SOURCES.json` pins the source JAR and retained field/dependency contracts.
Preflight rejects moved/duplicated classes, existing new helpers or changed
dependencies before the normal UN1CA patch helper applies the ordinary diff.
SDK 36 skips the feature. The success marker is
`ro.unica.qpr2.app_identity=uid-and-raw-digests`.

The host proof first confirms the three methods are absent in the previous
composed framework, then executes actual framework boot classes under ARM64
ART/QEMU. UID expectations come from independent host user/app decomposition;
digest expectations come from host hashlib SHA-256. Tests include user and PCC
range boundaries, signed integer limits, cross-user rejection, legacy digest
agreement, order/duplicate handling, output ownership and exhaustive byte-to-hex
conversion. Compile stubs are absent from the executed probe. Previous QPR2
collection and dimension additions are preserved in an identical selected DEX.

These tests use the existing QPR2 ART/Conscrypt trial and retained Samsung
Bionic/native providers. They do not establish phone boot, real package-manager
authorization, process spawning, ARM32 ART or regenerated boot artifacts. The
normal ROM build must regenerate its framework/boot cohort. The private host
test JAR is not a standalone phone update.
