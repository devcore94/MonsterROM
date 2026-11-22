.class Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$2;
.super Landroid/content/BroadcastReceiver;
.source "HideMyApplistFragment.java"


# annotations
.annotation system Ldalvik/annotation/EnclosingClass;
    value = Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;
.end annotation

.annotation system Ldalvik/annotation/InnerClass;
    accessFlags = 0x0
    name = null
.end annotation


# instance fields
.field final synthetic this$0:Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;


# direct methods
.method constructor <init>(Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;)V
    .locals 0
    .annotation system Ldalvik/annotation/MethodParameters;
        accessFlags = {
            0x8010
        }
        names = {
            null
        }
    .end annotation

    iput-object p1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$2;->this$0:Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;

    invoke-direct {p0}, Landroid/content/BroadcastReceiver;-><init>()V

    return-void
.end method


# virtual methods
.method public onReceive(Landroid/content/Context;Landroid/content/Intent;)V
    .locals 0

    iget-object p1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$2;->this$0:Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;

    invoke-static {p1}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->access$000(Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;)Z

    move-result p1

    if-eqz p1, :cond_0

    iget-object p0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$2;->this$0:Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;

    invoke-static {p0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->access$200(Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;)V

    :cond_0
    return-void
.end method
