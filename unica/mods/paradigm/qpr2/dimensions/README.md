# QPR2 dimension rounding for Samsung One UI 9

The reviewed Samsung `TypedValue.floatToComplex` throws an
`IllegalArgumentException` for the positive floats immediately below 1, 256 and
65536. Their first selected fixed-point representation rounds to 8388608, beyond
the positive limit of a signed 24-bit mantissa, even though a coarser radix can
represent the value. This can also affect callers of `createComplexDimension`.

This ordinary Paradigm patch copies `floatToComplex` and the private
`isValidMantissa` helper directly from the local CRB `android17QPR2gsi` framework,
build `CP41.260831.007.A3`. QPR2 tries the next radix when rounding would overflow.
The methods' exact source hashes and retained Samsung contracts are recorded in
`SOURCES.json`. The GSI's DEX-041 container is read directly across its segments.

Only that existing conversion method is replaced; one private helper is added.
Samsung's fields, constants, `createComplex`, `complexToFloat`, dimension-unit
validation and remaining TypedValue methods stay in place. Original exception
behavior for values outside the supported magnitude range is retained. The
existing NaN-to-zero behavior is retained as well. No public API, native library,
resource table, font scale, display setting or input-validation policy is added.

The module uses normal UN1CA `DECODE_APK`, `APPLY_PATCH` and `SET_PROP` helpers.
Preflight verifies the exact reviewed conversion/dependency bodies before the
patch is applied, and rejects an existing helper or changed field contract.
SDK 36 skips it. The successful-build marker is
`ro.unica.qpr2.dimension_rounding=mantissa-fallback`.

The host proof first reproduces all three exceptions on the original Samsung
framework, then tests the corrected framework boot class on ARM64 ART/QEMU.
An independent BigDecimal oracle enumerates the representable mantissas for
boundary-adjacent, random, negative, tiny, nonfinite and out-of-range inputs;
the six dimension units and invalid units are exercised too. The previous five
collection additions and two callback interfaces are retained byte for byte in
their independently selected DEX, so both patches can compose in the same build.

This is an offline framework proof with the existing QPR2 ART trial and retained
Samsung Bionic/native providers. It does not establish a physical phone's UI,
ARM32 ART, zygote/system_server startup or regenerated boot images. The normal ROM
build must regenerate the complete framework/boot cohort. The private test JAR
is not a standalone phone update.
