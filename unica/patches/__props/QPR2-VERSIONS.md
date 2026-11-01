# User-selected QPR2 version metadata

For One UI 9 the version profile reports build
CP4A.261005.017.S942BXXU5CZJJ, SDK-full 37.2 and One UI 90500 across system,
product and system_ext, retaining each fingerprint's existing device/product,
build type and signing tags. Android's major API remains 37. Build.VERSION reads
sdk_full and parses 37.2 into SDK_INT_FULL 3700002; no extra Build class override
is needed. The original platform identity is recorded under ro.unica.qpr2.base.

The reviewed Samsung donor provides Knox 3.14 / API 41. The user clarified that
no Knox 3.15/API-42 donor is available and the temporary label-only patch was
removed from active sources. Existing Knox version reporting, enum dispatch,
classes, methods, authorization and caller-scoped KnoxPatch behavior are retained.
The Google QPR2 GSI contains no Samsung Knox replacement.

Vendor/ODM/boot-image fingerprints and API levels, first/shipping/board APIs,
VNDK, firmware versions, build timestamps and security-patch levels are not
rewritten as a fictitious component update. Floppy/r54 is retained. The profile
runs through the existing property helpers; scripts/ is unchanged.

Samsung's official mapping currently identifies Knox 3.14 as API 41:
https://docs.samsungknox.com/dev/knox-sdk/introduction/knox-version-mapping/
