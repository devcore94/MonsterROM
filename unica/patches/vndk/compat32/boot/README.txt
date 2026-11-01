One UI 9 native-only ARM32 boot compatibility

The API30-policy-r1 boot reached SELinux policy loading successfully, then
init rebooted because /system/bin/boringssl_self_test32 was absent. Both
stock vendor self tests passed. A vendor default of zygote64_32 also selected
a secondary app runtime that the 64-bit-only donor does not contain.

Restore the unmodified system self-test from the same reviewed S21 FE SDK36
cohort as system/lib. Do not patch its result, disable its service, or remove
reboot_on_failure. Explicit early-init/init actions keep native vendor32 and
system32 crypto tests enabled independently of app ABI advertisement.

Retain the donor's 64-bit app runtime and ABI. This does not remove the ARM32
native libraries, linker, vendor services or GPU driver. It does not pretend
that a 32-bit ART/Conscrypt app runtime was ported. All existing ARM64 runtime,
crypto and Conscrypt providers remain unchanged. No data migration or wipe
is part of this patch.
