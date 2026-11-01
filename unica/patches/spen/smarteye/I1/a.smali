# SPDX-License-Identifier: GPL-3.0-or-later
# SmartEye initialization facade, backed by the shipping One UI 9 recognizer.
.class public final LI1/a;
.super Ljava/lang/Object;

.field public static e:I = -0x1
.field public static f:I = -0x1
.field public a:Z
.field public b:Z
.field public c:Z
.field public d:Landroid/content/Context;

.method public final a(Landroid/content/Context;)V
    .locals 2

    if-eqz p1, :invalid_context
    iput-object p1, p0, LI1/a;->d:Landroid/content/Context;
    const/4 v0, 0x0
    iput-boolean v0, p0, LI1/a;->a:Z
    iput-boolean v0, p0, LI1/a;->b:Z
    iput-boolean v0, p0, LI1/a;->c:Z

    invoke-static {p1}, Lcom/samsung/android/sdk/handwriting/Recognizer;->isTextRecognizerAvailable(Landroid/content/Context;)Z
    move-result v0
    if-eqz v0, :unavailable
    invoke-static {}, Lcom/samsung/android/sdk/handwriting/Recognizer;->isSDLAvailable()Z
    move-result v1
    iput-boolean v1, p0, LI1/a;->b:Z
    invoke-static {}, Lcom/samsung/android/sdk/handwriting/Recognizer;->isSDKAvailable()Z
    move-result v1
    iput-boolean v1, p0, LI1/a;->c:Z
    iput-boolean v0, p0, LI1/a;->a:Z
    return-void

    :unavailable
    new-instance v0, LH1/a;
    const-string v1, "One UI 9 handwriting resources or supported device are unavailable"
    invoke-direct {v0, v1}, LH1/a;-><init>(Ljava/lang/String;)V
    throw v0

    :invalid_context
    new-instance v0, Ljava/lang/IllegalArgumentException;
    const-string v1, "Context is null"
    invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
    throw v0
.end method
