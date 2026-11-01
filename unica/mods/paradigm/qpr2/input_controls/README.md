# QPR2 controlled wheel scrolling in Samsung Settings

Integrates the QPR2 reverse-scrolling and controlled-scrolling controls into
Samsung's existing General management / Mouse and trackpad page. Its old wheel
speed dialog is replaced with the QPR2 SliderPreference and matching controller;
there is one speed preference, not two competing entries with the same key.
The fixed-speed slider is enabled only when controlled scrolling is selected.

The reference is the local CP41.260831.007.A3 GSI Settings inputmethod package:
MouseReverseVerticalScrollingPreferenceController,
MouseScrollingAccelerationPreferenceController and
MouseScrollingSpeedPreferenceController. Their implementations already exist
in this Samsung One UI 9 donor but were absent from this Samsung settings page.
This is UI integration of those actual QPR2 behaviors, not a new input algorithm
or a claim that the features are exclusive to QPR2.

The controllers call the existing InputSettings API. The corresponding settings
are observed by Samsung InputSettingsObserver / InputManagerService and reach
the native input implementation. No framework, service, native library, device
configuration or permission enforcement is replaced. Settings writes happen
only when the user operates a control. Actual wheel response still needs a
physical-device test.

The companion reset patch restores scroll acceleration and normal scroll
direction when Samsung's existing mouse-settings reset is invoked. It retains
Samsung's other reset defaults. Installing or opening the APK does not reset
anything.

The separate version patch identifies Settings r11, code 42. The loose APK is
based on the checked r9 Settings candidate and keeps its game-controller,
contrast and magnifier controls. Existing APK/shared-UID identity, manifest
permissions and UN1CA signing profile are retained.
