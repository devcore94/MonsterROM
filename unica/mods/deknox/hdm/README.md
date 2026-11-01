# One UI 9 HDM patch ordering

`product_feature` runs before DeKnox. On One UI 9, R8 inlines the HDM vendor
controller initialization into `EnterpriseDeviceManagerServiceImpl`'s Context
constructor. Product-feature adaptation changes its shipping API string from
the source's `36` to the target's value (for example, `30` on t2s/p3s/r9s).

The checked-in removal patch is the pristine-source template. `customize.sh`
specializes **only its deleted HDM API literal** in a private temporary patch,
then calls the normal `APPLY_PATCH`. It does not change the template or undo
any target API values outside the removed HDM block. Temporary files are
removed on success and failure; unknown source literals and nonnumeric config
fail before patching. Other context mismatches still stop the module.

The archived development regression replays the product-feature API section and
the selected DeKnox entry point with real helpers for the affected class. It
covers target APIs 30/31/35/36, neighboring API preservation, cleanup, unexpected
input rejection and error propagation. Unrelated module operations are mocked;
these fixtures are not firmware or Android-runtime validation.
