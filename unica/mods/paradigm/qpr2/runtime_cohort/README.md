# Paired QPR2 ART / Conscrypt trial profile

`UN1CA_QPR2_RUNTIME_COHORT=trial-r15` selects the two complete custom-signed APEX
inputs in prebuilts/qpr2-runtime. `off` is the default. The normal Paradigm entry
point runs this finite preflight before either component is copied, then the
separate art_runtime and conscrypt_trust hooks use normal ADD/DELETE helpers.
There is no adapter or additional patch logic in scripts/.

This profile was exercised offline with the current Samsung One UI 9 zygote64
cohort. It retains the Samsung Bionic/compat32 runtime, libc++, vendor libraries,
SELinux policy, Floppy/r54 and existing APK signing key. Both old/new container
names and exact hashes are checked; unrelated local containers are rejected.

Both APEXes use the existing persistent owner-controlled module signing pairs.
Their signatures are verified, but are not the original Google signatures.
They are inputs for a custom-ROM first preinstallation. A previously installed
/data APEX with the old Google identity requires a separate migration review;
this patch never deletes, edits or bypasses that data/update state. It does not
disable signature verification or automatically enroll another update signer.

The complete ART images, compiled service artifacts and cache-info.xml exported
on G: are offline evidence for the exact recorded JAR/APEX cohort. They are not
copied to system/framework or /data by these patches. The normal art_boot /
odrefresh / odsign first-boot flow must regenerate and authenticate the actual
post-patch ROM cache on the device. Its SELinux, odsign/device key handling,
zygote, system_server and installed data-update lifecycle are not proved by a
host namespace. No phone action has been performed.
