# SM-S947B native APEXs

These packages combine the `S947BXXU6ZZKN` system APEXs with the native ARM32 providers from `G990EXXSOHZH4`. Both original Android manifests, the ARM64 binaries and the S26+ ICU data are preserved byte for byte. The runtime adds the ARM32 bionic libraries, linker and crash dump tool. The i18n package adds the ARM32 ICU libraries and their matching ICU 76 data alongside the beta's ICU data.

The payloads use the repository's RSA-4096 AVB development key. The outer containers use the AOSP platform test certificate. Each rebuilt payload was mounted and checked against the source file hashes, owners, modes, symlinks and SELinux labels.

| Package | S26+ input SHA-256 | S21 FE input SHA-256 | Rebuilt SHA-256 |
| --- | --- | --- | --- |
| `com.android.runtime.apex` | `d8d63011b480e7f99a573e7c2a859f745424f4f5bbb2e53ef33d41e5a0815b50` | `a4bd1cbfcb34d206db1bb6482b33818c4aff5a3e2e8a5b80d011c04e53b88cf6` | `273405f44c53458cc26cdccf75028120bee98ec25f373f42ea35427c88a834c2` |
| `com.android.i18n.apex` | `df3984bceb9ce6923817c0ae8bfd7ed4818aa01bd8f057b625ec039bad3a0d7c` | `425a2bcfdd941f137c7ccb67ffb06241b5a84beadda489da69e9baf7c9309927` | `f0a13aa95ef3a2211f5782ff05ad601204a5528263f707a383ea2e1c097a735b` |
