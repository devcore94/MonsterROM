# Camera control surfaces

Adds circular surfaces behind the existing quick-setting buttons, using the
early One UI 9.5 Camera image as a visual reference. The existing IDs, child
classes, ripple, dimensions, focus and camera actions are retained. This does
not add a 24 MP sensor mode or alter capture processing.

The source RRO is compiled and signed with the selected normal UN1CA platform
key during the ROM build and added to product/overlay. The original Camera APK
and its native libraries stay intact. Actual One UI 9 idmap2 accepted the mapping
under enforced public/product policy; Android UI inflation and hardware camera
sessions remain untested. A standalone overlay APK is a ROM companion, not an
ordinary Camera update that activates simply by tapping Install.

Reference: https://www.sammobile.com/news/massive-one-ui-9-5-leak-smoother-animations-fingerprint-design-camera-ui/

## Linker requirements and regression checks

Samsung's referenced IDs, dimensions, styles and drawables are private resources.
Use `@*com.sec.android.app.camera:...`, and use
`http://schemas.android.com/apk/prv/res/com.sec.android.app.camera` for the three
Camera-owned custom attributes. The ordinary public namespace fails AAPT2's
visibility checks; changing the Camera APK's public table or inventing new IDs is
not necessary. The overlay's own background stays an ordinary local reference.

The build uses the staged Camera APK and the matching normalized Apktool
framework, then the original platform signing/staging helpers. Cleanup runs in a
subshell so that success or a failed link cannot replace the parent EXIT trap.

The 27 October 2026 host regression reproduced the original private-resource
failure, passed compile/link/sign/stage and repeat metadata stability, checked all
17 Camera resource/attribute IDs in binary XML, and passed genuine One UI 9 idmap2
creation/lookup with public/product policy and overlayable enforcement enabled.
Missing inputs and either incorrect namespace reject without installing an
overlay; SDK36 stays unchanged. The full t2s source/APK build also passed. These
checks do not establish Android view inflation, visual equivalence or camera
hardware behavior.

The framework-cache tag comes from the active work-tree incremental property,
exactly as in the original `scripts/apktool.sh`, not the raw donor's extraction
metadata. A QPR2 property profile may legitimately select `S942BXXU5CZJJ` while
the donor still reports `S942BXXU5BZJA`. Decode provisions that selected cache;
the overlay uses the same cache and still aborts if it is missing. Empty/unsafe
tags reject before decode/link/sign/stage. No firmware property, generated
Apktool tag, resource table, original Camera APK or signing helper is changed.
