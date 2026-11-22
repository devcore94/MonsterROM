.class public Lio/mesalabs/unica/settings/ui/LiveBlurPreferenceController;
.super Lcom/android/settings/core/TogglePreferenceController;
.source "LiveBlurPreferenceController.java"

.implements Landroid/content/DialogInterface$OnClickListener;


# direct methods
.method public constructor <init>(Landroid/content/Context;Ljava/lang/String;)V
    .locals 0

    invoke-direct {p0, p1, p2}, Lcom/android/settings/core/TogglePreferenceController;-><init>(Landroid/content/Context;Ljava/lang/String;)V

    return-void
.end method

.method private getStringId(Ljava/lang/String;)I
    .locals 2

    iget-object v0, p0, Lcom/android/settingslib/core/AbstractPreferenceController;->mContext:Landroid/content/Context;

    invoke-virtual {v0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;

    move-result-object v1

    invoke-virtual {v0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;

    move-result-object v0

    const-string p0, "string"

    invoke-virtual {v1, p1, p0, v0}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I

    move-result p0

    return p0
.end method

.method private showRestartDialog()V
    .locals 3

    iget-object v0, p0, Lcom/android/settingslib/core/AbstractPreferenceController;->mContext:Landroid/content/Context;

    instance-of v1, v0, Landroid/app/Activity;

    if-eqz v1, :done

    check-cast v0, Landroid/app/Activity;

    invoke-virtual {v0}, Landroid/app/Activity;->isFinishing()Z

    move-result v1

    if-nez v1, :done

    invoke-virtual {v0}, Landroid/app/Activity;->isDestroyed()Z

    move-result v1

    if-nez v1, :done

    new-instance v1, Landroidx/appcompat/app/AlertDialog$Builder;

    invoke-direct {v1, v0}, Landroidx/appcompat/app/AlertDialog$Builder;-><init>(Landroid/content/Context;)V

    const-string v0, "unica_dialog_reboot_title"

    invoke-direct {p0, v0}, Lio/mesalabs/unica/settings/ui/LiveBlurPreferenceController;->getStringId(Ljava/lang/String;)I

    move-result v0

    invoke-virtual {v1, v0}, Landroidx/appcompat/app/AlertDialog$Builder;->setTitle(I)V

    const-string v0, "unica_dialog_reboot_msg"

    invoke-direct {p0, v0}, Lio/mesalabs/unica/settings/ui/LiveBlurPreferenceController;->getStringId(Ljava/lang/String;)I

    move-result v0

    invoke-virtual {v1, v0}, Landroidx/appcompat/app/AlertDialog$Builder;->setMessage(I)V

    const-string v0, "unica_dialog_reboot_negative"

    invoke-direct {p0, v0}, Lio/mesalabs/unica/settings/ui/LiveBlurPreferenceController;->getStringId(Ljava/lang/String;)I

    move-result v0

    const/4 v2, 0x0

    invoke-virtual {v1, v0, v2}, Landroidx/appcompat/app/AlertDialog$Builder;->setNegativeButton(ILandroid/content/DialogInterface$OnClickListener;)V

    const-string v0, "unica_dialog_reboot_positive"

    invoke-direct {p0, v0}, Lio/mesalabs/unica/settings/ui/LiveBlurPreferenceController;->getStringId(Ljava/lang/String;)I

    move-result v0

    invoke-virtual {v1, v0, p0}, Landroidx/appcompat/app/AlertDialog$Builder;->setPositiveButton(ILandroid/content/DialogInterface$OnClickListener;)V

    invoke-virtual {v1}, Landroidx/appcompat/app/AlertDialog$Builder;->show()Landroidx/appcompat/app/AlertDialog;

    :done
    return-void
.end method


# virtual methods
.method public getAvailabilityStatus()I
    .locals 1

    invoke-static {}, Lio/mesalabs/unica/FloatingFeatureHooks;->isLiveBlurSupported()Z

    move-result v0

    if-eqz v0, :unsupported

    const/4 v0, 0x0

    return v0

    :unsupported
    const/4 v0, 0x3

    return v0
.end method

.method public isChecked()Z
    .locals 2

    const-string v0, "persist.sys.unica.nativeblur"

    const/4 v1, 0x1

    invoke-static {v0, v1}, Landroid/os/SemSystemProperties;->getBoolean(Ljava/lang/String;Z)Z

    move-result v0

    return v0
.end method

.method public isControllable()Z
    .locals 1

    const/4 v0, 0x0

    return v0
.end method

.method public onClick(Landroid/content/DialogInterface;I)V
    .locals 2

    const/4 v0, -0x1

    if-ne p2, v0, :done

    iget-object v0, p0, Lcom/android/settingslib/core/AbstractPreferenceController;->mContext:Landroid/content/Context;

    const-class v1, Landroid/os/PowerManager;

    invoke-virtual {v0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;

    move-result-object v0

    check-cast v0, Landroid/os/PowerManager;

    if-eqz v0, :done

    const/4 v1, 0x0

    invoke-virtual {v0, v1}, Landroid/os/PowerManager;->reboot(Ljava/lang/String;)V

    :done
    return-void
.end method

.method public setChecked(Z)Z
    .locals 2

    invoke-virtual {p0}, Lio/mesalabs/unica/settings/ui/LiveBlurPreferenceController;->isChecked()Z

    move-result v0

    if-eq v0, p1, :success

    const-string v0, "persist.sys.unica.nativeblur"

    invoke-static {p1}, Ljava/lang/Boolean;->toString(Z)Ljava/lang/String;

    move-result-object v1

    :try_start_0
    invoke-static {v0, v1}, Landroid/os/SemSystemProperties;->set(Ljava/lang/String;Ljava/lang/String;)V
    :try_end_0
    .catch Ljava/lang/RuntimeException; {:try_start_0 .. :try_end_0} :catch_0

    invoke-direct {p0}, Lio/mesalabs/unica/settings/ui/LiveBlurPreferenceController;->showRestartDialog()V

    :success
    const/4 v0, 0x1

    return v0

    :catch_0
    move-exception v0

    const/4 v0, 0x0

    return v0
.end method
