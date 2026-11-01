# QPR2 long-key and double sparse compute support

This ordinary Samsung One UI 9 Paradigm patch adds two more internal QPR2 APIs
from the local CRB `android17QPR2gsi` framework, build `CP41.260831.007.A3`:

- `LongSparseLongArray.compute(long, LongBinaryOperator)`
- `SparseDoubleArray.compute(int, DoubleBinaryOperator)`

Both methods retain their original `blacklist` hidden-API metadata. These are
additional internal framework methods, not new public Android SDK promises.
The GSI method bodies, one private synthetic adapter method and the exact
`SparseDoubleArray$$ExternalSyntheticLambda0` class are copied without edits.
`SOURCES.json` records source hashes and the retained Samsung field contracts.

The Double variant deliberately delegates storage to the preceding QPR2
`SparseLongArray.compute` addition. Preflight requires that exact method before
applying anything. The dispatcher loads `collections` before this feature.
Original Samsung fields and existing methods of the two classes remain intact.
Neither the existing LongSparseLongArray parcel format nor its Parcelling class
is modified. A conflicting callback class, existing compute methods, changed
field layouts or missing dependencies cause an early failure. SDK 36 skips it.

Callbacks see zero for an absent value. Returning zero still creates/retains an
entry. Double keys are the exact signed integer key converted to double, and
values use raw IEEE-754 bits: negative zero, infinities and NaN payloads are not
canonicalized by this adapter. Callbacks must not structurally mutate the same
collection; this adds no synchronization or atomicity.

The host proof checks that the two methods are absent before the patch, then
executes the real framework boot classes under ARM64 ART/QEMU. Independent
TreeMap state comparisons cover growth, sorting, updates/deletion, full-width
long keys, callback counts/errors, clone isolation and raw Double payloads,
including signed zero and signalling/quiet NaN examples. Compile stubs are
excluded from the executed probe JAR. The earlier collection interfaces/methods
and TypedValue rounding fix are retained in an identical selected DEX.

The successful build marker is `ro.unica.qpr2.collections_numeric=long-and-double`.
These offline tests use the existing QPR2 ART trial with retained Samsung
Bionic/native providers. Physical phone boot, ARM32 ART, JNI parcel roundtrips
and regenerated boot images are not established by this proof. The normal ROM
build must regenerate its framework/boot cohort; the private test JAR is not a
standalone phone update.
