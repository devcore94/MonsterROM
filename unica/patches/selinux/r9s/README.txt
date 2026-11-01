One UI 9 donor / SM-G990E_THL SDK36 API30 compatibility

Selection
---------
The owning module's root customize.sh selects these patches
only for TARGET_CODENAME=r9s. Other targets keep their original patch
selection. The two common system compat patches and vendor/0003 remain
shared because the original compat files and plat_pub_versioned.cil
are byte-identical to SM-G996B_AUT.

Reviewed differences
--------------------
system/0001 preserves the newer r9s API30 declarations and mapping
members. persist_debug_prop/system_user_mode_emulation_prop,
vendor_file/vendor_boot_ota_file, and sysfs_mem_sleep/sysfs_udc are
already present; only the remaining public type splits are added.

vendor/0001 retains the common policy operations, rebased onto the r9s
domain/file_type context and genuine vendor EOF. vendor/0002 changes
only the iofdaemon context anchor and omits the removal of two firmware
getattr grants that DEVICE variants never inject on r9s. The regression
test compares every added/removed CIL operation with the common patches.

vendor/0004 removes the single conflicting vendor /bus/usb/devices
genfscon. The untouched One UI 9 donor owns that exact path as sysfs_usb;
no replacement allow is granted for the retired sysfs_ss_writable label.

vendor/0005 accounts for the real additional dmd, hal_kg30_default and
MLS-trusted vendor_telephony_silentlogging_app domains. It restricts 83
concrete access tuples, including a forbidden modem-logging service
lookup, without introducing any new access tuple. The only old API30
guard exceptions are eight existing donor domain.te:607 tuples:
  { dmd hal_kg30_default } x { shell_exec toolbox_exec }
      :file { execute execute_no_trans }
The guards remain active for every other executable. No donor allow,
neverallow or neverallowx is edited; tests also compare donor system_ext
and product access/assertion rules unchanged.

Historical checks
-----------------
The offline regression sourced the original module helpers and compiled the
complete real policy with assertions enabled in formats 30/31. It checked
mapping preservation and exact policy operations. Development tests and the
removed validator are archived under
out/oneui9-shell-migration-20261026/retired-source/. They are not production
build hooks or packaging gates; the normal UN1CA scripts remain unchanged.

No policy is loaded or flashed, no precompiled-policy hash is forged,
and successful host compilation is not a claim of physical boot.
