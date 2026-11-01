# Standalone Contacts signing in a One UI 9 system image

The One UI 9 0002 patch narrows the existing custom-platform alias: the exact
package com.samsung.android.app.contacts keeps its cryptographically verified
UN1CA signing details and is not promoted to the Samsung platform identity.
Other packages retain the previous alias behavior. Certificate collection,
APK verification and ReconcilePackageUtils are unchanged.

Contacts is eligible for the existing system-image signer-change route because
the reviewed APK has no shared UID. The Contacts provider uses android.uid.shared
and keeps its original certificate and APK. No shared-UID cohort is re-signed.
The previous Contacts backup signer is retained only on its original backup
permission using signature|knownSigner and the exact original SHA-256 digest.

The offline validation checked both guards in the compiled services.jar, the
reviewed source signer/permission, empty shared UID, image path and candidate
certificate. Its development tools are archived under
`out/oneui9-shell-migration-20261026/retired-source/`. Production uses the original
UN1CA signing flow and certificates in `security/`; no alternate signer is added.

The loose Contacts APK cannot be installed as an ordinary update over the old
Samsung-signed APK. A system-image build with the paired policy is required.
The existing system scan supports data retention; an actual upgrade has not been
tested on the device. No private Samsung key or rotation proof is fabricated.

Android references:
- https://source.android.com/docs/security/features/apksigning/v3
- https://android.googlesource.com/platform/frameworks/base/+/refs/heads/master/services/core/java/com/android/server/pm/ReconcilePackageUtils.java
