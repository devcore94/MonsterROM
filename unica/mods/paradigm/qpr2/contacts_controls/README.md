# Contacts: QPR2 comparison and a standalone system signing identity

r12 enables the existing material patch together with country-aware telephone
comparison in the native typed-recipient selection guard. The reference is
CP41.260831.007.A3 ContactsPicker ContactsRepositoryImplKt.distinctByPhoneNumber,
which uses PhoneNumberUtils.areSamePhoneNumber with a country. The native app's
exact-match and non-telephone paths remain unchanged. The helper also keeps
different extensions and pause/wait suffixes distinct. It does not merge,
delete or rewrite contacts. The actual R8 Fragment.m0() ABI is retained.

The source is Samsung-signed with certificate
32c332b4ad0f837cda2e2b342974aea5d5708616dc40c9fbad665ab338cbea36 and has no
shared UID or signing-certificate lineage. The r12 APK is signed with the same
existing UN1CA key as the other candidates. That new certificate is kept as the
real Contacts signing identity; Contacts is excluded from the old platform
certificate alias and is not marked platform-signed by that alias.

The companion One UI 9 signature patch and final-JAR contract checker are required.
The image verifier accepts this one explicit preinstalled Contacts transition
only with the expected old certificate, package, system path, empty shared UID,
verified new signature and exact knownSigner backup permission. The original
Samsung certificate remains authorized for that one backup permission through
Android's normal knownSigner mechanism. The provider, its shared-UID group and
signature/permission verification remain unchanged.

This is a system-image integration. Samsung's existing system-package
reconciliation code supports a changed system-app signer while retaining data;
the implementation is not changed here. An ordinary APK update over the old
Samsung certificate is still incompatible. Installation, data retention and
provider behavior have not been exercised by flashing or installing on a phone.

The separate version patch replaces the inactive r11 version patch; it does not
stack a second version patch on top. The shared glass module runs first.
