# Reviewed modular NFC cohorts

Keep the signed NFC CAPEX intact. Do not substitute an older NFC APK, transplant
individual JNI/framework files, re-sign the module, or disable this preflight.
Unknown hashes require another artifact review, not a wildcard acceptance rule.

Accepted SHA-256 identities:

- `408f490bf488a6ef364ed0d1d1c249a7546fe6cec1efecfce6552c9192dab597`:
  original reviewed One UI 9 cohort (retained for existing inputs).
- `00a29b4a9f83cf07746400613e0fa0910c50836e17ab92928a2c9651ed921ae0`:
  stock SM-S942B/INS `S942BXXU5BZJA/S942BOXM5BZJA/S942BXXU5BZJA`.
  Its original APEX is
  `65d568a65a6b2355b664a1211e305dfab0de46aa91166fcbb810a43059030903`;
  its ARM64 JNI is
  `e312f4fd01044e2bb3ee26900df73090a4a657ed6292d4e0e056fa73b23e5d81`.

## October 29, 2026 review

The newer CAPEX, copied unchanged from the extracted donor, contains a matched
`com.android.nfc` app (version 37 / Android 17, min SDK36, target One UI 9),
`framework-nfc.jar`, and `lib64/libnfc_nci_jni.so`. Static Ghidra analysis of
`NfcAdaptation::InitializeHalDeviceContext` at provider address `0x2e736c`
shows the HIDL path resolving `INfc/default` at 1.2, then 1.1 and 1.0, alongside
the separate AIDL path. This is more than a string/name match, but it does not
establish successful execution on a phone.

REA evidence:

- CAPEX inventory: `ev_d45094bec1e034b3ede5b016c33f6555d1d94fadfe41ac884f91ef795e746fdf`.
- Native initialization: `ev_efc82a84c71570b997a7fff6a1d9374a07dfb63e32ac9f4a9e69627d73010290`.

The inspected SM-G996B/AUT `G996BXXSJHZC2/G996BOXMJHZC2/G996BXXSJHZA6`
target retains the NXP service and `nfc_nci_nxpsn.so`, with a VINTF declaration
for `android.hardware.nfc@1.2::INfc/default` over `hwbinder`. Its separate
Samsung NFC 2.0 extension is present too. The preflight checks the actual NFC
HAL declaration, not an unrelated `<version>1.2</version>` elsewhere in XML.
Both standard version/interface and equivalent `fqname` notation are accepted.

Validation must happen before target-config writes. The existing Settings
antenna adaptation and its mismatch checks remain in place. These are static
artifact and host-replay checks, not device qualification or a complete ROM
build. Original APEX signatures/bytes are not modified by this patch.
