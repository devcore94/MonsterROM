# Copyright (c) 2025 Salvo Giangreco
# SPDX-License-Identifier: GPL-3.0-or-later

# Debloat list for Galaxy S21+ 5G (Exynos) (t2s)
# - Add entries inside the specific partition containing that file (<PARTITION>_DEBLOAT+="")
# - DO NOT add the partition name at the start of any entry (eg. "/system/dpolicy_system")
# - DO NOT add a slash at the start of any entry (eg. "/dpolicy_system")

# Overlays
SYSTEM_DEBLOAT+="
system/app/WifiRROverlayAppH2E
"

# S26 product overlays for Wi-Fi features absent on the S21+.
PRODUCT_DEBLOAT+="
overlay/WifiRROverlayAppH2E.apk
overlay/WifiRROverlayAppLls.apk
"
