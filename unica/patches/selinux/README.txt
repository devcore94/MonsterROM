One UI 9 / API30 vendor policy compatibility

Keep the original UN1CA module layout and SDK36 entry-removal logic.
customize.sh imports the actual target firmware's platform and system_ext
30.0.cil / 30.0.compat.cil files; it never replaces them with an API31 file
or an empty mapping. ADD_TO_WORK_DIR registers their image metadata.

system/0001-Backport-public-type-splits-to-API30.patch is an ordinary patch
for eight additive public type splits. Each added member comes from the
same alias's difference between the target and current API31 mappings.
Every original API30 member remains present.

The root module applies the mappings and strict-policy patches using the
original UN1CA helpers. Missing mappings or patch mismatches abort that module.
No replacement policy validator or packaging gate is installed in scripts/.

Historical offline checks compiled the complete CIL cohort in formats 30/31
with neverallow and neverallowx assertions enabled. Their tools are archived
under out/oneui9-shell-migration-20261026/retired-source/. Those results are not
a claim that every later build is validated, nor proof of runtime policy loading
or successful physical boot. No precompiled-policy hash is forged. Floppy/r54,
enforcement configuration and userdata are unchanged by these policy patches.
