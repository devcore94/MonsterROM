# SPDX-License-Identifier: GPL-3.0-or-later
# Keep SmartEye's field/caller ABI; delegate recognition to the complete One UI 9 client.
.class public final LM1/b;
.super Ljava/lang/Object;

.field public final a:Z
.field public final b:LO1/a;
.field public c:Z

.method public constructor <init>(LI1/a;)V
    .locals 3

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V
    iget-boolean v0, p1, LI1/a;->a:Z
    if-eqz v0, :uninitialized
    iget-object v0, p1, LI1/a;->d:Landroid/content/Context;
    new-instance v1, LN1/b;
    invoke-direct {v1, v0}, LN1/b;-><init>(Landroid/content/Context;)V

    :try_start
    invoke-virtual {v1}, LN1/b;->b()V
    :try_end
    .catch Lcom/samsung/android/sdk/handwriting/UninitializedException; {:try_start .. :try_end} :unavailable

    iput-object v1, p0, LM1/b;->b:LO1/a;
    const/4 v0, 0x1
    iput-boolean v0, p0, LM1/b;->a:Z
    const/4 v0, 0x0
    iput-boolean v0, p0, LM1/b;->c:Z
    return-void

    :unavailable
    move-exception v2
    invoke-virtual {v2}, Ljava/lang/Throwable;->getMessage()Ljava/lang/String;
    move-result-object v0
    new-instance v1, LI1/b;
    invoke-direct {v1, v0}, LI1/b;-><init>(Ljava/lang/String;)V
    invoke-virtual {v1, v2}, Ljava/lang/Throwable;->initCause(Ljava/lang/Throwable;)Ljava/lang/Throwable;
    throw v1

    :uninitialized
    new-instance v0, LI1/b;
    const-string v1, "Recognizer SDK for Text Recognizer has not been initialized"
    invoke-direct {v0, v1}, LI1/b;-><init>(Ljava/lang/String;)V
    throw v0
.end method

.method public final a(LA0/c;)V
    .locals 2

    if-eqz p1, :null_listener
    iget-boolean v0, p0, LM1/b;->a:Z
    if-eqz v0, :sync_mode
    iget-object v0, p0, LM1/b;->b:LO1/a;
    check-cast v0, LN1/b;
    invoke-virtual {v0, p1}, LN1/b;->setListener(LA0/c;)V
    invoke-interface {v0}, LO1/a;->d()V
    const/4 v1, 0x0
    iput-boolean v1, p0, LM1/b;->c:Z
    # The SDK's real no-strokes path is also asynchronous and returns null.
    invoke-interface {v0}, LO1/a;->request()V
    return-void

    :sync_mode
    new-instance v0, LM1/a;
    const-string v1, "Async API is not allowed in Sync mode."
    invoke-direct {v0, v1}, Ljava/lang/Exception;-><init>(Ljava/lang/String;)V
    throw v0

    :null_listener
    new-instance v0, Ljava/lang/IllegalArgumentException;
    const-string v1, "Listener is null"
    invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
    throw v0
.end method
