.class public final synthetic Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda1;
.super Ljava/lang/Object;
.source "D8$$SyntheticClass"

# interfaces
.implements Ljava/lang/Runnable;


# instance fields
.field public final synthetic f$0:Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;

.field public final synthetic f$1:I


# direct methods
.method public synthetic constructor <init>(Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;I)V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    iput-object p1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda1;->f$0:Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;

    iput p2, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda1;->f$1:I

    return-void
.end method


# virtual methods
.method public final run()V
    .locals 1

    iget-object v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda1;->f$0:Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;

    iget p0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda1;->f$1:I

    invoke-virtual {v0, p0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->lambda$loadApps$1$io-mesalabs-unica-settings-hma-HideMyApplistFragment(I)V

    return-void
.end method
