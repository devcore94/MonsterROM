.class public final synthetic Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda0;
.super Ljava/lang/Object;
.source "D8$$SyntheticClass"

# interfaces
.implements Ljava/lang/Runnable;


# instance fields
.field public final synthetic f$0:Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;

.field public final synthetic f$1:I

.field public final synthetic f$2:Ljava/util/ArrayList;


# direct methods
.method public synthetic constructor <init>(Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;ILjava/util/ArrayList;)V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    iput-object p1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda0;->f$0:Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;

    iput p2, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda0;->f$1:I

    iput-object p3, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda0;->f$2:Ljava/util/ArrayList;

    return-void
.end method


# virtual methods
.method public final run()V
    .locals 2

    iget-object v0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda0;->f$0:Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;

    iget v1, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda0;->f$1:I

    iget-object p0, p0, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment$$ExternalSyntheticLambda0;->f$2:Ljava/util/ArrayList;

    invoke-virtual {v0, v1, p0}, Lio/mesalabs/unica/settings/hma/HideMyApplistFragment;->lambda$loadApps$0$io-mesalabs-unica-settings-hma-HideMyApplistFragment(ILjava/util/ArrayList;)V

    return-void
.end method
