# QPR2 game-controller controls

Adds **Game controllers** to Samsung Settings → Advanced features → Labs.
The UI can change physical controller buttons and axes, map a button to either
trigger, restore one control, and reset this controller's mappings for the
current user. USB and Bluetooth controllers use the same Android input route.

The reference is the local CP41.260831.007.A3 QPR2 Settings
`com/android/settings/input/gamecontroller` implementation. Samsung One UI 9
already implements the matching InputManager APIs, permission-enforced Binder
methods, persistent per-user InputDeviceRemapper, native remapping entry points
and InputReader/EventHub support. This patch exposes those real APIs in Samsung's
existing preference UI; it does not import GSI Compose dependencies or replace
the input framework/native libraries.

The APK explicitly requests the existing signature permission
`android.permission.CONTROLLER_REMAPPING`. Binder permission checks are retained.
Setup wizard, a locked user, the wrong foreground user, virtual devices and a
missing permission cannot change mappings. Open dialogs are invalidated when a
controller changes or disconnects, or Settings pauses; input ID, generation,
descriptor, VID, PID, user and session are checked again before each operation.
No mappings change until the user makes a selection. Reset affects this device
and this user. Button-to-trigger offers LTRIGGER/RTRIGGER only, because no
unverified negative-stick encoding is assumed.

The first patch pins 86 previously unpublished UN1CA resource IDs from the
existing compiled Settings baseline. Adding QPR2 strings therefore preserves
the current UN1CA activity labels and the IDs already referenced by their DEX.

`source/` contains the reviewed Java sources. The normal UN1CA builder applies
the separate smali/resource patch and uses its usual APK signing. Compile-only
API stubs are not included. Offline verification does not constitute a physical
controller or on-device Settings lifecycle test.
