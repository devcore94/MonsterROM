# Dual Messenger whitelist refresh

`WhiteListApps` is populated dynamically rather than by its old static
initializer. Refresh at the beginning of the provider query, using a dead local
`v0` for the Context. Keep the original register frame and URI parameters.

Do **not** inject `p0.getContext()` before every MatrixCursor allocation. In the
One UI 9 query's default-package branch, `p0` already holds integer `5`. ART rejects
the entire provider class before it can be instantiated. This was observed on
the rooted t2s device as `VerifyError ... [0x1B6] ... v10 (PositiveByteConstant)`;
`v10` is the physical alias of `p0` in this `.locals 10` method.

The archived development regression exercises the shell module and smali helper
for SDK36/37 dispatch, safe entry insertion, parameter/frame preservation, both
cursor sites and fail-closed entry drift. Complete source/installed APK evidence
and host rebuilds are retained under `out/oneui9-remaining-fixes-20261026/`.
Host assembly/static checks are not a substitute for verifying the rebuilt APK
on Android. The diagnostic phone is not modified by this source fix.
