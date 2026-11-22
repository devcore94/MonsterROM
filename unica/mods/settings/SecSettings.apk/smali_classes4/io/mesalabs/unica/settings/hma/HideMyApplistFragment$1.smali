.class Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$1;
.super Landroid/database/ContentObserver;
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
.method constructor <init>(Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;Landroid/os/Handler;)V
    .locals 0
    .annotation system Ldalvik/annotation/MethodParameters;
        accessFlags = {
            0x8010,
            0x0
        }
        names = {
            null,
            null
        }
    .end annotation

    iput-object p1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$1;->this$0:Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;

    invoke-direct {p0, p2}, Landroid/database/ContentObserver;-><init>(Landroid/os/Handler;)V

    return-void
.end method


# virtual methods
.method public onChange(Z)V
    .locals 0

    iget-object p1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$1;->this$0:Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;

    invoke-static {p1}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->access$000(Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;)Z

    move-result p1

    if-eqz p1, :cond_0

    iget-object p0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$1;->this$0:Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;

    const/4 p1, 0x0

    invoke-static {p0, p1}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->access$100(Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;Z)V

    :cond_0
    return-void
.end method
