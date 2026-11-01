# Complete QPR2 Mainline modules in the isolated One UI 9 profile

Imports the original, byte-identical Google-signed SDK Extensions and Time Zone
Data APEX containers from the reviewed CP41.260831.007.A3 GSI. Both APK/container
signatures and both AVB payload signatures were verified; module names, payload
keys and container signers match the existing Samsung-distributed modules.
No signature check, trust key or payload is changed.

SDK Extensions updates derive_sdk, derive_classpath, its framework JAR and the
extension database together. It computes the supported extension levels from
the installed module versions; no extension level is forced by a property.
Both native binaries add no strong dynamic import relative to the reviewed
Samsung module, and the original Java class/member contracts are retained.
Time Zone Data keeps the same 010.001 file format and updates 2026b to 2026c.

All source/current hashes are checked before copying. The old compressed SDK
Extensions container is removed only after the new complete container has been
copied and read back. The normal file metadata helpers handle image entries.
Reapplying the selected modules accepts only their exact already-updated bytes.

This is two coherent module upgrades, not all 38 APEX modules. ART, Conscrypt,
OEM Bluetooth/Wi-Fi/telephony and private Samsung modules still need their own
ABI, JNI, signing, trust-store, classpath and hardware integration. Original
Google module signatures are preserved; they are not replaced by the APK key.
Nothing is installed or flashed by this build-time module.
