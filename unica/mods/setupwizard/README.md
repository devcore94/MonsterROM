# Setup Wizard resource and SDK contracts

The module uses the original automatic `smali` patch layout for the One UI 9
firmware. The navigation gates use `e7/f` and `e(String)`; the disclaimer uses
`l7/a`'s UI methods/IDs. The donor is Android 17 (API 37), but this shipped app
itself has `minSdk=33`, `targetSdk=36`. Keep those values. The legacy API 36
variant is not included in this module.

## Resource patching

The module-root `customize.sh` handles only Setup Wizard resources:

- Remove complete OMC recommendation items in `sequence_list*` string arrays,
  including qualified `values*/arrays.xml` overrides. Never delete XML lines
  merely because they contain `omcagent`: minified XML loses unrelated steps;
  multiline items otherwise leave an empty sequence entry.
- Insert the module's disclaimer string as literal XML data. The former
  EVAL/sed pipeline interpreted backticks and backslash escapes, and inserting
  before a compact `</resources>` line placed the string outside the root.
- Update/de-duplicate only the owned `disclaimer_unica_description` resource
  within each exact qualifier, including definitions in other values files.
  Append-only injection causes AAPT duplicate definitions in retained decodes.
- Preserve all unrelated XML bytes and copy the module's WebP images verbatim.
  Validate the complete planned XML changes and required resources before
  writing; replace each changed file atomically while preserving its mode.
- Restore the original UN1CA tips artwork on the setup completion page. The
  One UI 9 donor no longer references it, so the outro layouts explicitly add
  the image without replacing Samsung's existing background or controls.
  Its actual appearance and sizing still require a device test.

The resource operation is idempotent. The entire smali module is intentionally
still a one-shot patch operation, not an invitation to reapply patched smali.
The helper does not support Settings' first-line sed-instruction file format.

Development tests and the superseded Python helper are archived under
`out/oneui9-shell-migration-20261026/retired-source/`; they are not build inputs.

## Firmware-backed validation (2026-10-26)

Proof and commands are retained at
`out/oneui9-remaining-fixes-20261026/setupwizard/REPORT.md`. A fresh immutable
SM-S942B_INS decode, real selected script/helper/patch replays for official and
unofficial builds, full Apktool/AAPT2 builds with an isolated framework cache,
and final rebuilt-APK decode were used. No existing One UI 9 smali runtime defect
was confirmed; do not misreport the XML-input failures as an observed crash on
the pristine donor. On the normal donor, code/resource-table/manifest bytes are
unchanged by the safer resource handling.

Static final-artifact checks cover all injected calls and resource IDs,
register frames, both step-selection gates, native scroll layout and callback
result/finish contracts, all 32 payload locales (including Android's `in`/`id`
alias), and the exported Settings navigation target. No app/device execution
was performed; rendering, process death, Back/rotation and actual navigation
behavior still require an authorized Android test environment. These historical
results predate moving the patch to the original module layout.
