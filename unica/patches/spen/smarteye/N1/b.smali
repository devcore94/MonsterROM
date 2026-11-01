# SPDX-License-Identifier: GPL-3.0-or-later
# LO1/a is SmartEye's existing lifecycle/stroke/language/request ABI.
.class public LN1/b;
.super Ljava/lang/Object;
.implements LO1/a;

.field private final context:Landroid/content/Context;
.field private engine:Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;
.field private listener:LA0/c;
.field private callback:Lunica/spen/RecognitionCallback;

.method public constructor <init>(Landroid/content/Context;)V
    .locals 0
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V
    iput-object p1, p0, LN1/b;->context:Landroid/content/Context;
    return-void
.end method

.method public final b()V
    .locals 3
    iget-object v0, p0, LN1/b;->engine:Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;
    if-nez v0, :already_initialized
    new-instance v0, Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;
    iget-object v1, p0, LN1/b;->context:Landroid/content/Context;
    const/4 v2, 0x1
    invoke-direct {v0, v1, v2}, Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;-><init>(Landroid/content/Context;Z)V
    iput-object v0, p0, LN1/b;->engine:Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;
    return-void

    :already_initialized
    new-instance v0, Ljava/lang/IllegalStateException;
    const-string v1, "Recognizer already initialized"
    invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
    throw v0
.end method

.method public final c([F[F)V
    .locals 1
    invoke-direct {p0}, LN1/b;->requireEngine()Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;
    move-result-object v0
    invoke-virtual {v0, p1, p2}, Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;->addStroke([F[F)V
    return-void
.end method

.method public final e(Ljava/lang/String;)V
    .locals 1
    invoke-direct {p0}, LN1/b;->requireEngine()Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;
    move-result-object v0
    invoke-virtual {v0, p1}, Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;->setLanguage(Ljava/lang/String;)V
    return-void
.end method

.method public final f()Ljava/util/List;
    .locals 1
    invoke-direct {p0}, LN1/b;->requireEngine()Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;
    move-result-object v0
    invoke-virtual {v0}, Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;->getSupportedLanguages()Ljava/util/List;
    move-result-object v0
    return-object v0
.end method

.method private requireEngine()Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;
    .locals 2
    iget-object v0, p0, LN1/b;->engine:Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;
    if-eqz v0, :closed
    return-object v0

    :closed
    new-instance v0, Ljava/lang/IllegalStateException;
    const-string v1, "Recognizer is closed"
    invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
    throw v0
.end method

.method public final setListener(LA0/c;)V
    .locals 2
    if-eqz p1, :null_listener
    iput-object p1, p0, LN1/b;->listener:LA0/c;
    return-void

    :null_listener
    new-instance v0, Ljava/lang/IllegalArgumentException;
    const-string v1, "Listener is null"
    invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
    throw v0
.end method

.method public final declared-synchronized d()V
    .locals 2
    monitor-enter p0
    :try_start
    invoke-direct {p0}, LN1/b;->requireEngine()Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;
    iget-object v0, p0, LN1/b;->callback:Lunica/spen/RecognitionCallback;
    if-nez v0, :pending
    iget-object v1, p0, LN1/b;->listener:LA0/c;
    if-eqz v1, :missing
    new-instance v0, Lunica/spen/RecognitionCallback;
    invoke-direct {v0, p0, v1}, Lunica/spen/RecognitionCallback;-><init>(LN1/b;LA0/c;)V
    iput-object v0, p0, LN1/b;->callback:Lunica/spen/RecognitionCallback;
    monitor-exit p0
    return-void

    :pending
    new-instance v0, Ljava/lang/IllegalStateException;
    const-string v1, "Recognition is already pending"
    invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
    throw v0

    :missing
    new-instance v0, Ljava/lang/IllegalArgumentException;
    const-string v1, "Listener is null"
    invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
    throw v0
    :try_end
    .catchall {:try_start .. :try_end} :unlock
    :unlock
    move-exception v0
    monitor-exit p0
    throw v0
.end method

.method private declared-synchronized detachFailedRequest(Lunica/spen/RecognitionCallback;)V
    .locals 2
    monitor-enter p0
    :try_start
    # Only detach the token captured by the request that threw. A callback may
    # already have completed, or cancel/close may have allowed a new request.
    iget-object v0, p0, LN1/b;->callback:Lunica/spen/RecognitionCallback;
    if-ne p1, v0, :done
    const/4 v0, 0x0
    iput-object v0, p0, LN1/b;->callback:Lunica/spen/RecognitionCallback;
    iget-object v1, p0, LN1/b;->listener:LA0/c;
    iget-object p1, p1, Lunica/spen/RecognitionCallback;->listener:LA0/c;
    if-ne v1, p1, :done
    iput-object v0, p0, LN1/b;->listener:LA0/c;
    :done
    monitor-exit p0
    return-void
    :try_end
    .catchall {:try_start .. :try_end} :unlock
    :unlock
    move-exception v0
    monitor-exit p0
    throw v0
.end method

.method public final request()V
    .locals 3
    invoke-direct {p0}, LN1/b;->requireEngine()Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;
    move-result-object v0
    iget-object v1, p0, LN1/b;->callback:Lunica/spen/RecognitionCallback;
    if-eqz v1, :missing
    :try_start
    invoke-virtual {v0, v1}, Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;->requestRecognition(Lcom/samsung/android/sdk/handwriting/text/TextRecognizer$RecognitionListener;)V
    :try_end
    .catch Lcom/samsung/android/sdk/handwriting/text/IncorrectUsageException; {:try_start .. :try_end} :incorrect_usage
    .catch Ljava/lang/RuntimeException; {:try_start .. :try_end} :request_failure
    return-void

    :incorrect_usage
    move-exception v0
    invoke-direct {p0, v1}, LN1/b;->detachFailedRequest(Lunica/spen/RecognitionCallback;)V
    invoke-virtual {v0}, Ljava/lang/Throwable;->getMessage()Ljava/lang/String;
    move-result-object v1
    new-instance v2, LM1/a;
    invoke-direct {v2, v1}, Ljava/lang/Exception;-><init>(Ljava/lang/String;)V
    invoke-virtual {v2, v0}, Ljava/lang/Throwable;->initCause(Ljava/lang/Throwable;)Ljava/lang/Throwable;
    throw v2

    :request_failure
    move-exception v0
    # Restore only local bookkeeping; do not cancel/dispose native work, retry,
    # synthesize a result, or replace the SDK's exception/type/cause.
    invoke-direct {p0, v1}, LN1/b;->detachFailedRequest(Lunica/spen/RecognitionCallback;)V
    throw v0

    :missing
    new-instance v0, Ljava/lang/IllegalStateException;
    const-string v1, "Recognition listener has not been registered"
    invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
    throw v0
.end method

.method public final cancel()V
    .locals 2
    # Detach before native cancellation. Never hold our monitor across a native
    # call that might wait for a callback on another thread.
    monitor-enter p0
    :try_start
    const/4 v0, 0x0
    iput-object v0, p0, LN1/b;->callback:Lunica/spen/RecognitionCallback;
    iput-object v0, p0, LN1/b;->listener:LA0/c;
    invoke-direct {p0}, LN1/b;->requireEngine()Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;
    move-result-object v1
    monitor-exit p0
    :try_end
    .catchall {:try_start .. :try_end} :unlock
    invoke-virtual {v1}, Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;->cancel()V
    return-void
    :unlock
    move-exception v0
    monitor-exit p0
    throw v0
.end method

.method public final a()V
    .locals 2
    monitor-enter p0
    :try_start
    iget-object v1, p0, LN1/b;->engine:Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;
    const/4 v0, 0x0
    iput-object v0, p0, LN1/b;->callback:Lunica/spen/RecognitionCallback;
    iput-object v0, p0, LN1/b;->listener:LA0/c;
    iput-object v0, p0, LN1/b;->engine:Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;
    monitor-exit p0
    :try_end
    .catchall {:try_start .. :try_end} :unlock
    if-eqz v1, :done
    invoke-virtual {v1}, Lcom/samsung/android/sdk/handwriting/text/TextRecognizer;->close()V
    :done
    return-void
    :unlock
    move-exception v0
    monitor-exit p0
    throw v0
.end method

.method public final declared-synchronized deliver(Lunica/spen/RecognitionCallback;ILcom/samsung/android/sdk/handwriting/text/TextRecognizer$Result;)V
    .locals 4
    monitor-enter p0
    :try_start
    iget-object v0, p0, LN1/b;->callback:Lunica/spen/RecognitionCallback;
    if-ne p1, v0, :done
    const/4 v0, 0x0
    iput-object v0, p0, LN1/b;->callback:Lunica/spen/RecognitionCallback;
    iput-object v0, p0, LN1/b;->listener:LA0/c;
    # One UI 9 STATUS_SUCCESS == 0. Never turn native failure into candidates.
    if-nez p2, :post
    if-eqz p3, :post
    invoke-virtual {p3}, Lcom/samsung/android/sdk/handwriting/text/TextRecognizer$Result;->getCandidates()[Ljava/lang/String;
    move-result-object v0

    :post
    iget-object v1, p1, Lunica/spen/RecognitionCallback;->listener:LA0/c;
    iget-object v1, v1, LA0/c;->e:Ljava/lang/Object;
    check-cast v1, LG2/b;
    iget-object v1, v1, LG2/b;->f:Ljava/lang/Object;
    check-cast v1, LG2/a;
    const/16 v2, 0x7d2
    const/4 v3, 0x0
    invoke-virtual {v1, v2, p2, v3, v0}, Landroid/os/Handler;->obtainMessage(IIILjava/lang/Object;)Landroid/os/Message;
    move-result-object v0
    invoke-virtual {v0}, Landroid/os/Message;->sendToTarget()V

    :done
    monitor-exit p0
    return-void
    :try_end
    .catchall {:try_start .. :try_end} :unlock
    :unlock
    move-exception v0
    monitor-exit p0
    throw v0
.end method
