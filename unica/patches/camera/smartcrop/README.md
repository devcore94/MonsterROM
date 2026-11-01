# SmartCrop One UI 9 / Exynos 2100 GPU route

This is an app-local native selector patch, not an NCP29 model converter or a
SmartCrop feature disable. The original S21 libfixsal chooses the TFLite file
and sets its model selector to 2; its SnapOptionsV3 Open call uses vtable slot
0x38. The pinned One UI 9 reader retains that GPU branch, including input
`serving_default_input:0`, output `PartitionedCall:0` and model path
`/vendor/etc/singletake/SmartCrop/SmartCrop.tflite`.

Only the first route-selector load in openSnapSession changes to `mov w8,#2`.
The branch then stores that selector and executes its existing GPU options and
model loading. Its inference, error propagation, callbacks and JNI processing
are not replaced with synthetic output. The patch checks the original reader,
target model/reader pair, actual staged SNAP V3 and OpenCV checksums before any
change. Other cohorts stop rather than receiving a guessed binary patch.

Physical Single Take / GPU inference still requires a device test after the
new ROM has been installed by the user. Building this patch does not flash or
prove camera quality, private NPU execution or Vulkan fault recovery.

Offline execution check: the actual stock reader and the four-byte-patched
donor reader produced identical Open parameters under retained Samsung Bionic
on Cortex-A55 and Cortex-A76 emulation: `1 0 9`, the original TFLite path and
the exact tensor names above. An unpatched donor was a rejection control and
selected `3 1 2` with `.nnc`, `input`, `output`. SNAP Open was explicitly mocked
for this test; hardware/weights were not executed. The fixture and its receipt
are outside the shipped patch in `out/oneui95/smartcrop-contract-test`.
