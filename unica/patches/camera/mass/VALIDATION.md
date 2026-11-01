# One UI 9 mass Camera validation

The port uses the original UN1CA build and signing tools. Its cohort checks
and recording-default adaptation are in the camera module's root `customize.sh`;
code changes are ordinary `.patch` files.

The earlier final Camera APK checks covered five changed DEX methods, 601
member uses, 92 types and all 18 native members. Static/assembly checks are
not a camera-HAL or Android execution test.

The detailed historical procedure and development tools are retained under
`out/oneui9-shell-migration-20261026/retired-source/unica/patches/camera/mass/`.
They are not an additional production build path.

Device qualification is still required for all lenses, photo/video modes,
repeated launch, Single Take, and native/linker/processor error handling.
