.class public final Lio/mesalabs/unica/settings/hma/HideMyApplistPreferenceController;
.super Lcom/android/settings/core/TogglePreferenceController;
.source "HideMyApplistPreferenceController.java"


# direct methods
.method public constructor <init>(Landroid/content/Context;Ljava/lang/String;)V
    .locals 0

    invoke-direct {p0, p1, p2}, Lcom/android/settings/core/TogglePreferenceController;-><init>(Landroid/content/Context;Ljava/lang/String;)V

    return-void
.end method


# virtual methods
.method public getAvailabilityStatus()I
    .locals 3

    iget-object v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistPreferenceController;->mContext:Landroid/content/Context;

    const-class v1, Landroid/os/UserManager;

    invoke-virtual {v0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;

    move-result-object v0

    check-cast v0, Landroid/os/UserManager;

    invoke-virtual {v0}, Landroid/os/UserManager;->isProfile()Z

    move-result v0

    const/4 v1, 0x3

    if-eqz v0, :cond_0

    return v1

    :cond_0
    :try_start_0
    const-string v0, "io.mesalabs.unica.HideAppListUtils"

    invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;

    move-result-object p0

    invoke-virtual {p0}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;

    move-result-object p0

    const/4 v2, 0x0

    invoke-static {v0, v2, p0}, Ljava/lang/Class;->forName(Ljava/lang/String;ZLjava/lang/ClassLoader;)Ljava/lang/Class;
    :try_end_0
    .catch Ljava/lang/ClassNotFoundException; {:try_start_0 .. :try_end_0} :catch_0

    return v2

    :catch_0
    return v1
.end method

.method public isChecked()Z
    .locals 1

    iget-object v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistPreferenceController;->mContext:Landroid/content/Context;

    invoke-virtual {v0}, Landroid/content/Context;->getContentResolver()Landroid/content/ContentResolver;

    move-result-object v0

    iget-object p0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistPreferenceController;->mContext:Landroid/content/Context;

    invoke-virtual {p0}, Landroid/content/Context;->getUserId()I

    move-result p0

    invoke-static {v0, p0}, Lio/mesalabs/unica/HideAppListUtils;->isEnabled(Landroid/content/ContentResolver;I)Z

    move-result p0

    return p0
.end method

.method public setChecked(Z)Z
    .locals 0

    iget-object p0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistPreferenceController;->mContext:Landroid/content/Context;

    invoke-static {p0, p1}, Lio/mesalabs/unica/HideAppListUtils;->setEnabled(Landroid/content/Context;Z)Z

    move-result p0

    return p0
.end method
