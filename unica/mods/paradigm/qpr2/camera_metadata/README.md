# QPR2 camera metadata schema — experimental isolated-build component

Enable explicitly with `UN1CA_QPR2_CAMERA_METADATA=true` only in an isolated
One UI 9 build using the pinned Samsung native cohort. Paradigm's One UI 9 test
profile now sets this opt-in together with camera_path; the child customize
file alone still does nothing without the flag. No installer, live mount,
driver or OS identity change. See ../README.md for the integrated profile.

Payload: original arm64 `libcamera_metadata.so` from the local CRB GSI
CP41.260831.007.A3. SHA-256:
`6f9903343859e8af58f2661db15baed9e1053286fbe19e244954661d821724f6`.

The schema adds FLOAT tag `0x00200003` (`subjectSegmentationPathData`). All 348
existing standard tag names/types remain equal in the reviewed Samsung library.
Real allocation/add/sort/validation/clone/find/update/cross-provider-free code
passed 2,088 vectors per CPU under unmodified Samsung Bionic on QEMU A55/A76.
Synthetic global and per-vendor cache callbacks passed 12 more cross-provider
vectors per CPU. These are not actual Samsung vendor callbacks or sensor tests.

This library understands the packet; it does not produce a subject mask/path.
The adjacent camera_path feature stages the QPR2 framework conversion,
with explicit opt-in and a required fresh ART cohort; this schema module alone
does not provide it. A real live segmentation extension/HAL, private camera
C++/Binder contracts and physical ISP/GPU behavior are NOT implemented by this
module. The separate CameraExtensionsProxy patch preserves
a real vendor extension and otherwise reports it unavailable, like this GSI.
No camera capability or floatingfeature is forced on.

The retained Samsung runtime APEX, libc++ and old metadata provider are checked
before copying. No libcamera_client, libgui, libui, camera HAL, Mali driver,
32-bit provider, Bionic or ART replacement. Not a Vulkan DEVICE_LOST fix.
Production/hardware qualification is still required before enabling globally.
