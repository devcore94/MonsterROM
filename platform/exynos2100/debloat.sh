# Copyright (c) 2025 Salvo Giangreco
# SPDX-License-Identifier: GPL-3.0-or-later

# Debloat list for Samsung Exynos 2100 devices (exynos2100)
# - Add entries inside the specific partition containing that file (<PARTITION>_DEBLOAT+="")
# - DO NOT add the partition name at the start of any entry (eg. "/system/dpolicy_system")
# - DO NOT add a slash at the start of any entry (eg. "/dpolicy_system")

# Overlays
SYSTEM_DEBLOAT+="
system/app/WifiRROverlayAppLls
"
PRODUCT_DEBLOAT+="
overlay/SoftapOverlayQC
"

# DevGPUDriver
SYSTEM_DEBLOAT+="
system/priv-app/DevGPUDriver-EX2200
"

# GameDriver
SYSTEM_DEBLOAT+="
system/priv-app/GameDriver-EX2200
"

if [[ "$TARGET_CODENAME" == "t2s" ]]; then
    SYSTEM_DEBLOAT+="
system/priv-app/DevGPUDriver-EX2600
system/priv-app/GameDriver-EX2600
"
fi
