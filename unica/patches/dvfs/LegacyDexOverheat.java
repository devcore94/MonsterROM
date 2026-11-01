package com.sec.android.sdhms.thermal.overheatcontrol.overheatcomplex;

import android.content.Context;
import android.hardware.display.DisplayManager;
import android.os.Handler;
import android.view.Display;
import com.sec.android.sdhms.thermal.overheatcontrol.OverheatAppKillType;

/** Restores the target's DEX complex using the One UI 9 thermal controller. */
public final class LegacyDexOverheat extends i implements DisplayManager.DisplayListener {
    private final h5.g policy;
    private final com.sec.android.sdhms.thermal.overheatcontrol.e controller;
    private final DisplayManager displays;

    public LegacyDexOverheat(Context context, Handler handler, h5.g policy,
            com.sec.android.sdhms.thermal.overheatcontrol.e controller) {
        super(context, handler, OverheatComplexType.UNICA_DEX);
        this.policy = policy;
        this.controller = controller;
        this.displays = context.getSystemService(DisplayManager.class);
        if (displays == null) {
            throw new IllegalStateException("DEX thermal control needs DisplayManager");
        }
        displays.registerDisplayListener(this, handler);
    }

    private boolean desktopActive() {
        // Same non-default-display flag test as One UI 9 SDHMS p0.f.o(int).
        // Do not depend on the retired desktopmode Binder service.
        for (Display display : displays.getDisplays()) {
            int id = display.getDisplayId();
            if (id != 0 && id != -1 && (display.getFlags() & 0x20000) != 0) {
                return true;
            }
        }
        return false;
    }

    @Override
    public synchronized void a() {
        // Keep the parsed target formula, threshold and hysteresis intact.
        boolean hot = policy.a(b());
        OverheatComplexType.UNICA_DEX.isTempSatisfied = hot;
        boolean enabled = hot && desktopActive();
        if (enabled == b()) {
            return;
        }
        if (enabled) {
            controller.p(OverheatAppKillType.h);
        } else {
            controller.c(OverheatAppKillType.h);
        }
        c(enabled);
    }

    @Override public void onDisplayAdded(int id) { a(); }
    @Override public void onDisplayRemoved(int id) { a(); }
    @Override public void onDisplayChanged(int id) { a(); }
}
