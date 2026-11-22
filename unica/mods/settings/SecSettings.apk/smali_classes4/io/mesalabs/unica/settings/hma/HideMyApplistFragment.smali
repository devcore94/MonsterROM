.class public final Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;
.super Lcom/android/settings/core/InstrumentedFragment;
.source "HideMyApplistFragment.java"

# interfaces
.implements Landroidx/picker/widget/AppPickerState$OnStateChangeListener;
.implements Landroid/widget/CompoundButton$OnCheckedChangeListener;


# instance fields
.field private binding:Z

.field private final changes:Landroid/database/ContentObserver;

.field private empty:Landroid/widget/TextView;

.field private generation:I

.field private observing:Z

.field private final packages:Landroid/content/BroadcastReceiver;

.field private picker:Landroidx/picker/widget/SeslAppPickerListView;

.field private progress:Landroid/view/View;

.field private rows:Ljava/util/List;
    .annotation system Ldalvik/annotation/Signature;
        value = {
            "Ljava/util/List<",
            "Landroidx/picker/model/AppInfoData;",
            ">;"
        }
    .end annotation
.end field

.field private switchBar:Lcom/android/settings/widget/SettingsMainSwitchBar;


# direct methods
.method public constructor <init>()V
    .locals 3

    invoke-direct {p0}, Lcom/android/settings/core/InstrumentedFragment;-><init>()V

    invoke-static {}, Ljava/util/Collections;->emptyList()Ljava/util/List;

    move-result-object v0

    iput-object v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->rows:Ljava/util/List;

    new-instance v0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$1;

    new-instance v1, Landroid/os/Handler;

    invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;

    move-result-object v2

    invoke-direct {v1, v2}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V

    invoke-direct {v0, p0, v1}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$1;-><init>(Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;Landroid/os/Handler;)V

    iput-object v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->changes:Landroid/database/ContentObserver;

    new-instance v0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$2;

    invoke-direct {v0, p0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$2;-><init>(Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;)V

    iput-object v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->packages:Landroid/content/BroadcastReceiver;

    return-void
.end method

.method static synthetic access$000(Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;)Z
    .locals 0

    iget-boolean p0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->observing:Z

    return p0
.end method

.method static synthetic access$100(Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;Z)V
    .locals 0

    invoke-direct {p0, p1}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->sync(Z)V

    return-void
.end method

.method static synthetic access$200(Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;)V
    .locals 0

    invoke-direct {p0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->loadApps()V

    return-void
.end method

.method private loadApps()V
    .locals 4

    iget v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->generation:I

    add-int/lit8 v0, v0, 0x1

    iput v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->generation:I

    invoke-virtual {p0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->requireContext()Landroid/content/Context;

    move-result-object v1

    iget-object v2, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->rows:Ljava/util/List;

    invoke-interface {v2}, Ljava/util/List;->isEmpty()Z

    move-result v2

    if-eqz v2, :cond_0

    iget-object v2, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->progress:Landroid/view/View;

    const/4 v3, 0x0

    invoke-virtual {v2, v3}, Landroid/view/View;->setVisibility(I)V

    iget-object v2, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->empty:Landroid/widget/TextView;

    const/16 v3, 0x8

    invoke-virtual {v2, v3}, Landroid/widget/TextView;->setVisibility(I)V

    :cond_0
    new-instance v2, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda2;

    invoke-direct {v2, p0, v1, v0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda2;-><init>(Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;Landroid/content/Context;I)V

    invoke-static {v2}, Lcom/android/settingslib/utils/ThreadUtils;->postOnBackgroundThread(Ljava/lang/Runnable;)Lcom/google/common/util/concurrent/ListenableFuture;

    return-void
.end method

.method private resource(Ljava/lang/String;Ljava/lang/String;)I
    .locals 1

    invoke-virtual {p0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->requireContext()Landroid/content/Context;

    move-result-object p0

    invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;

    move-result-object v0

    invoke-virtual {p0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;

    move-result-object p0

    invoke-virtual {v0, p1, p2, p0}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I

    move-result p0

    return p0
.end method

.method private saveFailed()V
    .locals 3

    invoke-virtual {p0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->requireContext()Landroid/content/Context;

    move-result-object v0

    const-string v1, "monsterrom_hma_save_error"

    const-string v2, "string"

    invoke-direct {p0, v1, v2}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->resource(Ljava/lang/String;Ljava/lang/String;)I

    move-result v1

    const/4 v2, 0x0

    invoke-static {v0, v1, v2}, Landroid/widget/Toast;->makeText(Landroid/content/Context;II)Landroid/widget/Toast;

    move-result-object v0

    invoke-virtual {v0}, Landroid/widget/Toast;->show()V

    const/4 v0, 0x1

    invoke-direct {p0, v0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->sync(Z)V

    return-void
.end method

.method private show(ILjava/util/List;Z)V
    .locals 3
    .annotation system Ldalvik/annotation/Signature;
        value = {
            "(I",
            "Ljava/util/List<",
            "Landroidx/picker/model/AppInfoData;",
            ">;Z)V"
        }
    .end annotation

    iget-boolean v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->observing:Z

    if-eqz v0, :cond_4

    iget v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->generation:I

    if-ne p1, v0, :cond_4

    iget-object p1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->picker:Landroidx/picker/widget/SeslAppPickerListView;

    if-nez p1, :cond_0

    goto :goto_2

    :cond_0
    iput-object p2, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->rows:Ljava/util/List;

    const/4 p1, 0x1

    invoke-direct {p0, p1}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->sync(Z)V

    iget-object p1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->progress:Landroid/view/View;

    const/16 v0, 0x8

    invoke-virtual {p1, v0}, Landroid/view/View;->setVisibility(I)V

    iget-object p1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->picker:Landroidx/picker/widget/SeslAppPickerListView;

    invoke-interface {p2}, Ljava/util/List;->isEmpty()Z

    move-result v1

    const/4 v2, 0x0

    if-eqz v1, :cond_1

    move v1, v0

    goto :goto_0

    :cond_1
    move v1, v2

    :goto_0
    invoke-virtual {p1, v1}, Landroidx/picker/widget/SeslAppPickerListView;->setVisibility(I)V

    iget-object p1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->empty:Landroid/widget/TextView;

    if-eqz p3, :cond_2

    const-string p3, "monsterrom_hma_load_error"

    goto :goto_1

    :cond_2
    const-string p3, "no_applications"

    :goto_1
    const-string v1, "string"

    invoke-direct {p0, p3, v1}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->resource(Ljava/lang/String;Ljava/lang/String;)I

    move-result p3

    invoke-virtual {p1, p3}, Landroid/widget/TextView;->setText(I)V

    iget-object p0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->empty:Landroid/widget/TextView;

    invoke-interface {p2}, Ljava/util/List;->isEmpty()Z

    move-result p1

    if-eqz p1, :cond_3

    move v0, v2

    :cond_3
    invoke-virtual {p0, v0}, Landroid/widget/TextView;->setVisibility(I)V

    :cond_4
    :goto_2
    return-void
.end method

.method private sync(Z)V
    .locals 6

    invoke-virtual {p0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->requireContext()Landroid/content/Context;

    move-result-object v0

    invoke-virtual {v0}, Landroid/content/Context;->getUserId()I

    move-result v1

    invoke-virtual {v0}, Landroid/content/Context;->getContentResolver()Landroid/content/ContentResolver;

    move-result-object v2

    invoke-static {v2, v1}, Lio/mesalabs/unica/HideAppListUtils;->getPackages(Landroid/content/ContentResolver;I)Ljava/util/Set;

    move-result-object v2

    const/4 v3, 0x1

    iput-boolean v3, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->binding:Z

    const/4 v3, 0x0

    :try_start_0
    iget-object v4, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->switchBar:Lcom/android/settings/widget/SettingsMainSwitchBar;

    invoke-virtual {v0}, Landroid/content/Context;->getContentResolver()Landroid/content/ContentResolver;

    move-result-object v0

    invoke-static {v0, v1}, Lio/mesalabs/unica/HideAppListUtils;->isEnabled(Landroid/content/ContentResolver;I)Z

    move-result v0

    invoke-virtual {v4, v0}, Lcom/android/settings/widget/SettingsMainSwitchBar;->setChecked(Z)V

    iget-object v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->rows:Ljava/util/List;

    invoke-interface {v0}, Ljava/util/List;->iterator()Ljava/util/Iterator;

    move-result-object v0

    :cond_0
    :goto_0
    invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z

    move-result v1

    if-eqz v1, :cond_2

    invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;

    move-result-object v1

    check-cast v1, Landroidx/picker/model/AppInfoData;

    invoke-interface {v1}, Landroidx/picker/model/AppInfoData;->getAppInfo()Landroidx/picker/model/AppInfo;

    move-result-object v4

    iget-object v5, v4, Landroidx/picker/model/AppInfo;->packageName:Ljava/lang/String;

    invoke-interface {v2, v5}, Ljava/util/Set;->contains(Ljava/lang/Object;)Z

    move-result v5

    if-eqz p1, :cond_1

    invoke-interface {v1, v5}, Landroidx/picker/model/AppInfoData;->setSelected(Z)V

    goto :goto_0

    :cond_1
    invoke-interface {v1}, Landroidx/picker/model/AppInfoData;->getSelected()Z

    move-result v1

    if-eq v1, v5, :cond_0

    iget-object v1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->picker:Landroidx/picker/widget/SeslAppPickerListView;

    invoke-virtual {v1, v4, v5}, Landroidx/picker/widget/SeslAppPickerListView;->setState(Landroidx/picker/model/AppInfo;Z)V

    goto :goto_0

    :cond_2
    if-eqz p1, :cond_3

    iget-object p1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->picker:Landroidx/picker/widget/SeslAppPickerListView;

    iget-object v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->rows:Ljava/util/List;

    invoke-virtual {p1, v0}, Landroidx/picker/widget/SeslAppPickerListView;->submitList(Ljava/util/List;)V
    :try_end_0
    .catchall {:try_start_0 .. :try_end_0} :catchall_0

    :cond_3
    iput-boolean v3, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->binding:Z

    return-void

    :catchall_0
    move-exception p1

    iput-boolean v3, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->binding:Z

    throw p1
.end method


# virtual methods
.method public getMetricsCategory()I
    .locals 0

    const/4 p0, 0x0

    return p0
.end method

.method synthetic lambda$loadApps$0$io-mesalabs-unica-settings-hma-HideMyApplistFragment(ILjava/util/ArrayList;)V
    .locals 1

    const/4 v0, 0x0

    invoke-direct {p0, p1, p2, v0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->show(ILjava/util/List;Z)V

    return-void
.end method

.method synthetic lambda$loadApps$1$io-mesalabs-unica-settings-hma-HideMyApplistFragment(I)V
    .locals 2

    invoke-static {}, Ljava/util/Collections;->emptyList()Ljava/util/List;

    move-result-object v0

    const/4 v1, 0x1

    invoke-direct {p0, p1, v0, v1}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->show(ILjava/util/List;Z)V

    return-void
.end method

.method synthetic lambda$loadApps$2$io-mesalabs-unica-settings-hma-HideMyApplistFragment(Landroid/content/Context;I)V
    .locals 9

    new-instance v0, Ljava/util/ArrayList;

    invoke-direct {v0}, Ljava/util/ArrayList;-><init>()V

    :try_start_0
    invoke-virtual {p1}, Landroid/content/Context;->getPackageManager()Landroid/content/pm/PackageManager;

    move-result-object v1

    invoke-virtual {p1}, Landroid/content/Context;->getUserId()I

    move-result v2

    invoke-static {p1, v2}, Lio/mesalabs/unica/HideAppListUtils;->getManagementApps(Landroid/content/Context;I)Ljava/util/Set;

    move-result-object p1

    const/4 v3, 0x0

    invoke-virtual {v1, v3}, Landroid/content/pm/PackageManager;->getInstalledPackages(I)Ljava/util/List;

    move-result-object v3

    invoke-interface {v3}, Ljava/util/List;->iterator()Ljava/util/Iterator;

    move-result-object v3

    :cond_0
    :goto_0
    invoke-interface {v3}, Ljava/util/Iterator;->hasNext()Z

    move-result v4

    if-eqz v4, :cond_2

    invoke-interface {v3}, Ljava/util/Iterator;->next()Ljava/lang/Object;

    move-result-object v4

    check-cast v4, Landroid/content/pm/PackageInfo;

    iget-object v5, v4, Landroid/content/pm/PackageInfo;->applicationInfo:Landroid/content/pm/ApplicationInfo;

    if-eqz v5, :cond_0

    iget v6, v5, Landroid/content/pm/ApplicationInfo;->flags:I

    and-int/lit16 v6, v6, 0x81

    if-nez v6, :cond_0

    invoke-virtual {v5}, Landroid/content/pm/ApplicationInfo;->isPrivilegedApp()Z

    move-result v6

    if-nez v6, :cond_0

    iget-object v6, v4, Landroid/content/pm/PackageInfo;->sharedUserId:Ljava/lang/String;

    if-nez v6, :cond_0

    iget v6, v5, Landroid/content/pm/ApplicationInfo;->uid:I

    invoke-static {v6}, Landroid/os/Process;->isApplicationUid(I)Z

    move-result v6

    if-eqz v6, :cond_0

    iget v6, v5, Landroid/content/pm/ApplicationInfo;->uid:I

    invoke-static {v6}, Landroid/os/UserHandle;->getUserId(I)I

    move-result v6

    if-ne v6, v2, :cond_0

    iget-object v6, v4, Landroid/content/pm/PackageInfo;->packageName:Ljava/lang/String;

    invoke-interface {p1, v6}, Ljava/util/Set;->contains(Ljava/lang/Object;)Z

    move-result v6

    if-eqz v6, :cond_1

    goto :goto_0

    :cond_1
    invoke-virtual {v5, v1}, Landroid/content/pm/ApplicationInfo;->loadLabel(Landroid/content/pm/PackageManager;)Ljava/lang/CharSequence;

    move-result-object v5

    invoke-interface {v5}, Ljava/lang/CharSequence;->toString()Ljava/lang/String;

    move-result-object v5

    new-instance v6, Landroidx/picker/model/AppInfo;

    iget-object v7, v4, Landroid/content/pm/PackageInfo;->packageName:Ljava/lang/String;

    const-string v8, ""

    invoke-direct {v6, v2, v7, v8}, Landroidx/picker/model/AppInfo;-><init>(ILjava/lang/String;Ljava/lang/String;)V

    new-instance v7, Landroidx/picker/model/AppData$ListCheckBoxAppDataBuilder;

    invoke-direct {v7, v6}, Landroidx/picker/model/AppData$ListCheckBoxAppDataBuilder;-><init>(Landroidx/picker/model/AppInfo;)V

    invoke-virtual {v7, v5}, Landroidx/picker/model/AppData$ListCheckBoxAppDataBuilder;->setLabel(Ljava/lang/String;)Landroidx/picker/model/AppData$ListCheckBoxAppDataBuilder;

    move-result-object v5

    iget-object v4, v4, Landroid/content/pm/PackageInfo;->packageName:Ljava/lang/String;

    invoke-virtual {v5, v4}, Landroidx/picker/model/AppData$ListCheckBoxAppDataBuilder;->setSubLabel(Ljava/lang/String;)Landroidx/picker/model/AppData$ListCheckBoxAppDataBuilder;

    move-result-object v4

    invoke-virtual {v4}, Landroidx/picker/model/AppData$ListCheckBoxAppDataBuilder;->build()Landroidx/picker/model/AppInfoData;

    move-result-object v4

    invoke-virtual {v0, v4}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z

    goto :goto_0

    :cond_2
    new-instance p1, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda0;

    invoke-direct {p1, p0, p2, v0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda0;-><init>(Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;ILjava/util/ArrayList;)V

    invoke-static {p1}, Lcom/android/settingslib/utils/ThreadUtils;->postOnMainThread(Ljava/lang/Runnable;)V
    :try_end_0
    .catch Ljava/lang/RuntimeException; {:try_start_0 .. :try_end_0} :catch_0

    goto :goto_1

    :catch_0
    move-exception p1

    const-string v0, "PersonalAppVisibility"

    const-string v1, "Could not load the app picker"

    invoke-static {v0, v1, p1}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    new-instance p1, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda1;

    invoke-direct {p1, p0, p2}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda1;-><init>(Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;I)V

    invoke-static {p1}, Lcom/android/settingslib/utils/ThreadUtils;->postOnMainThread(Ljava/lang/Runnable;)V

    :goto_1
    return-void
.end method

.method public onCheckedChanged(Landroid/widget/CompoundButton;Z)V
    .locals 0

    iget-boolean p1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->observing:Z

    if-eqz p1, :cond_0

    iget-boolean p1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->binding:Z

    if-nez p1, :cond_0

    invoke-virtual {p0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->requireContext()Landroid/content/Context;

    move-result-object p1

    invoke-static {p1, p2}, Lio/mesalabs/unica/HideAppListUtils;->setEnabled(Landroid/content/Context;Z)Z

    move-result p1

    if-nez p1, :cond_0

    invoke-direct {p0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->saveFailed()V

    :cond_0
    return-void
.end method

.method public onCreateView(Landroid/view/LayoutInflater;Landroid/view/ViewGroup;Landroid/os/Bundle;)Landroid/view/View;
    .locals 1

    const-string p3, "monsterrom_hma_picker"

    const-string v0, "layout"

    invoke-direct {p0, p3, v0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->resource(Ljava/lang/String;Ljava/lang/String;)I

    move-result p3

    const/4 v0, 0x0

    invoke-virtual {p1, p3, p2, v0}, Landroid/view/LayoutInflater;->inflate(ILandroid/view/ViewGroup;Z)Landroid/view/View;

    move-result-object p1

    const-string p2, "app_picker_view"

    const-string p3, "id"

    invoke-direct {p0, p2, p3}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->resource(Ljava/lang/String;Ljava/lang/String;)I

    move-result p2

    invoke-virtual {p1, p2}, Landroid/view/View;->requireViewById(I)Landroid/view/View;

    move-result-object p2

    check-cast p2, Landroidx/picker/widget/SeslAppPickerListView;

    iput-object p2, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->picker:Landroidx/picker/widget/SeslAppPickerListView;

    const/4 v0, 0x2

    invoke-virtual {p2, v0}, Landroidx/picker/widget/SeslAppPickerListView;->setAppListOrder(I)V

    iget-object p2, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->picker:Landroidx/picker/widget/SeslAppPickerListView;

    iput-object p0, p2, Landroidx/picker/widget/SeslAppPickerListView;->mOnStateChangeListener:Landroidx/picker/widget/AppPickerState$OnStateChangeListener;

    const-string p2, "main_switch_bar"

    invoke-direct {p0, p2, p3}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->resource(Ljava/lang/String;Ljava/lang/String;)I

    move-result p2

    invoke-virtual {p1, p2}, Landroid/view/View;->requireViewById(I)Landroid/view/View;

    move-result-object p2

    check-cast p2, Lcom/android/settings/widget/SettingsMainSwitchBar;

    iput-object p2, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->switchBar:Lcom/android/settings/widget/SettingsMainSwitchBar;

    invoke-virtual {p2}, Lcom/android/settings/widget/SettingsMainSwitchBar;->show()V

    iget-object p2, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->switchBar:Lcom/android/settings/widget/SettingsMainSwitchBar;

    invoke-virtual {p2, p0}, Lcom/android/settings/widget/SettingsMainSwitchBar;->addOnSwitchChangeListener(Landroid/widget/CompoundButton$OnCheckedChangeListener;)V

    const p2, 0x102000d

    invoke-virtual {p1, p2}, Landroid/view/View;->requireViewById(I)Landroid/view/View;

    move-result-object p2

    iput-object p2, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->progress:Landroid/view/View;

    const p2, 0x1020004

    invoke-virtual {p1, p2}, Landroid/view/View;->requireViewById(I)Landroid/view/View;

    move-result-object p2

    check-cast p2, Landroid/widget/TextView;

    iput-object p2, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->empty:Landroid/widget/TextView;

    return-object p1
.end method

.method public onDestroyView()V
    .locals 2

    iget-object v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->picker:Landroidx/picker/widget/SeslAppPickerListView;

    const/4 v1, 0x0

    iput-object v1, v0, Landroidx/picker/widget/SeslAppPickerListView;->mOnStateChangeListener:Landroidx/picker/widget/AppPickerState$OnStateChangeListener;

    iget-object v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->switchBar:Lcom/android/settings/widget/SettingsMainSwitchBar;

    invoke-virtual {v0, p0}, Lcom/android/settings/widget/SettingsMainSwitchBar;->removeOnSwitchChangeListener(Landroid/widget/CompoundButton$OnCheckedChangeListener;)V

    iput-object v1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->picker:Landroidx/picker/widget/SeslAppPickerListView;

    iput-object v1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->switchBar:Lcom/android/settings/widget/SettingsMainSwitchBar;

    iput-object v1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->empty:Landroid/widget/TextView;

    iput-object v1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->progress:Landroid/view/View;

    invoke-static {}, Ljava/util/Collections;->emptyList()Ljava/util/List;

    move-result-object v0

    iput-object v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->rows:Ljava/util/List;

    invoke-super {p0}, Lcom/android/settings/core/InstrumentedFragment;->onDestroyView()V

    return-void
.end method

.method public onPause()V
    .locals 2

    iget-boolean v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->observing:Z

    if-eqz v0, :cond_0

    const/4 v0, 0x0

    iput-boolean v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->observing:Z

    invoke-virtual {p0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->requireContext()Landroid/content/Context;

    move-result-object v0

    iget-object v1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->packages:Landroid/content/BroadcastReceiver;

    invoke-virtual {v0, v1}, Landroid/content/Context;->unregisterReceiver(Landroid/content/BroadcastReceiver;)V

    invoke-virtual {p0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->requireContext()Landroid/content/Context;

    move-result-object v0

    invoke-virtual {v0}, Landroid/content/Context;->getContentResolver()Landroid/content/ContentResolver;

    move-result-object v0

    iget-object v1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->changes:Landroid/database/ContentObserver;

    invoke-virtual {v0, v1}, Landroid/content/ContentResolver;->unregisterContentObserver(Landroid/database/ContentObserver;)V

    :cond_0
    iget v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->generation:I

    add-int/lit8 v0, v0, 0x1

    iput v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->generation:I

    invoke-super {p0}, Lcom/android/settings/core/InstrumentedFragment;->onPause()V

    return-void
.end method

.method public onResume()V
    .locals 5

    invoke-super {p0}, Lcom/android/settings/core/InstrumentedFragment;->onResume()V

    invoke-virtual {p0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->requireContext()Landroid/content/Context;

    move-result-object v0

    const-class v1, Landroid/os/UserManager;

    invoke-virtual {v0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;

    move-result-object v1

    check-cast v1, Landroid/os/UserManager;

    invoke-virtual {v1}, Landroid/os/UserManager;->isProfile()Z

    move-result v1

    const/4 v2, 0x0

    if-eqz v1, :cond_0

    iget-object v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->switchBar:Lcom/android/settings/widget/SettingsMainSwitchBar;

    invoke-virtual {v0, v2}, Lcom/android/settings/widget/SettingsMainSwitchBar;->setEnabled(Z)V

    iget-object v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->progress:Landroid/view/View;

    const/16 v1, 0x8

    invoke-virtual {v0, v1}, Landroid/view/View;->setVisibility(I)V

    iget-object p0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->empty:Landroid/widget/TextView;

    invoke-virtual {p0, v2}, Landroid/widget/TextView;->setVisibility(I)V

    return-void

    :cond_0
    invoke-virtual {v0}, Landroid/content/Context;->getContentResolver()Landroid/content/ContentResolver;

    move-result-object v1

    const-string v3, "monsterrom_hma_enabled"

    invoke-static {v3}, Landroid/provider/Settings$Secure;->getUriFor(Ljava/lang/String;)Landroid/net/Uri;

    move-result-object v3

    iget-object v4, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->changes:Landroid/database/ContentObserver;

    invoke-virtual {v1, v3, v2, v4}, Landroid/content/ContentResolver;->registerContentObserver(Landroid/net/Uri;ZLandroid/database/ContentObserver;)V

    invoke-virtual {v0}, Landroid/content/Context;->getContentResolver()Landroid/content/ContentResolver;

    move-result-object v1

    const-string v3, "monsterrom_hma_packages"

    invoke-static {v3}, Landroid/provider/Settings$Secure;->getUriFor(Ljava/lang/String;)Landroid/net/Uri;

    move-result-object v3

    iget-object v4, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->changes:Landroid/database/ContentObserver;

    invoke-virtual {v1, v3, v2, v4}, Landroid/content/ContentResolver;->registerContentObserver(Landroid/net/Uri;ZLandroid/database/ContentObserver;)V

    new-instance v1, Landroid/content/IntentFilter;

    invoke-direct {v1}, Landroid/content/IntentFilter;-><init>()V

    const-string v3, "android.intent.action.PACKAGE_ADDED"

    invoke-virtual {v1, v3}, Landroid/content/IntentFilter;->addAction(Ljava/lang/String;)V

    const-string v3, "android.intent.action.PACKAGE_REMOVED"

    invoke-virtual {v1, v3}, Landroid/content/IntentFilter;->addAction(Ljava/lang/String;)V

    const-string v3, "android.intent.action.PACKAGE_CHANGED"

    invoke-virtual {v1, v3}, Landroid/content/IntentFilter;->addAction(Ljava/lang/String;)V

    const-string v3, "package"

    invoke-virtual {v1, v3}, Landroid/content/IntentFilter;->addDataScheme(Ljava/lang/String;)V

    iget-object v3, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->packages:Landroid/content/BroadcastReceiver;

    const/4 v4, 0x4

    invoke-virtual {v0, v3, v1, v4}, Landroid/content/Context;->registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;I)Landroid/content/Intent;

    const/4 v0, 0x1

    iput-boolean v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->observing:Z

    invoke-direct {p0, v2}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->sync(Z)V

    invoke-direct {p0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->loadApps()V

    return-void
.end method

.method public onStateAllChanged(Z)V
    .locals 0

    return-void
.end method

.method public onStateChanged(Landroidx/picker/model/AppInfo;Z)V
    .locals 2

    iget-boolean v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->observing:Z

    if-eqz v0, :cond_0

    iget-boolean v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->binding:Z

    if-nez v0, :cond_0

    iget v0, p1, Landroidx/picker/model/AppInfo;->user:I

    invoke-virtual {p0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->requireContext()Landroid/content/Context;

    move-result-object v1

    invoke-virtual {v1}, Landroid/content/Context;->getUserId()I

    move-result v1

    if-ne v0, v1, :cond_0

    invoke-virtual {p0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->requireContext()Landroid/content/Context;

    move-result-object v0

    iget-object p1, p1, Landroidx/picker/model/AppInfo;->packageName:Ljava/lang/String;

    invoke-static {v0, p1, p2}, Lio/mesalabs/unica/HideAppListUtils;->setSelected(Landroid/content/Context;Ljava/lang/String;Z)Z

    move-result p1

    if-nez p1, :cond_0

    invoke-direct {p0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->saveFailed()V

    :cond_0
    return-void
.end method
