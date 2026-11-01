# SPDX-License-Identifier: GPL-3.0-or-later
# One-shot identity token: cancellation/close detach it, so late results cannot
# complete another SmartEye request. Candidates come only from One UI 9 Result.
.class public Lunica/spen/RecognitionCallback;
.super Ljava/lang/Object;
.implements Lcom/samsung/android/sdk/handwriting/text/TextRecognizer$RecognitionListener;

.field private final owner:LN1/b;
.field public final listener:LA0/c;

.method public constructor <init>(LN1/b;LA0/c;)V
    .locals 0
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V
    iput-object p1, p0, Lunica/spen/RecognitionCallback;->owner:LN1/b;
    iput-object p2, p0, Lunica/spen/RecognitionCallback;->listener:LA0/c;
    return-void
.end method

.method public final onResult(ILcom/samsung/android/sdk/handwriting/text/TextRecognizer$Result;)V
    .locals 1
    iget-object v0, p0, Lunica/spen/RecognitionCallback;->owner:LN1/b;
    invoke-virtual {v0, p0, p1, p2}, LN1/b;->deliver(Lunica/spen/RecognitionCallback;ILcom/samsung/android/sdk/handwriting/text/TextRecognizer$Result;)V
    return-void
.end method
