.class public final synthetic Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda2;
.super Ljava/lang/Object;
.source "D8$$SyntheticClass"

# interfaces
.implements Ljava/lang/Runnable;


# instance fields
.field public final synthetic f$0:Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;

.field public final synthetic f$1:Landroid/content/Context;

.field public final synthetic f$2:I


# direct methods
.method public synthetic constructor <init>(Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;Landroid/content/Context;I)V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    iput-object p1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda2;->f$0:Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;

    iput-object p2, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda2;->f$1:Landroid/content/Context;

    iput p3, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda2;->f$2:I

    return-void
.end method


# virtual methods
.method public final run()V
    .locals 2

    iget-object v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda2;->f$0:Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;

    iget-object v1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda2;->f$1:Landroid/content/Context;

    iget p0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda2;->f$2:I

    invoke-virtual {v0, v1, p0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->lambda$loadApps$2$io-mesalabs-unica-settings-hma-HideMyApplistFragment(Landroid/content/Context;I)V

    return-void
.end method
