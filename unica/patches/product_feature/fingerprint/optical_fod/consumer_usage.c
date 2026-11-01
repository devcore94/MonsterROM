/* SPDX-License-Identifier: GPL-3.0-or-later
 * SM-S942B One UI 9 / r9s ONLY. See native.py and NATIVE.md for the measured
 * layouts. Called synchronously before a new BLAST queue exposes a producer;
 * never retain either pointer or change an allocated native_handle.
 */
typedef unsigned long u64;
typedef long long jlong;

extern int set_consumer_usage(void *, u64)
    __asm__("_ZN7android12ConsumerBase20setConsumerUsageBitsEm");

__attribute__((visibility("default")))
int Java_android_view_ViewRootImpl_nativeSetOpticalMaskBufferUsage(
        void *env, void *clazz, jlong native_queue)
{
    (void)env;
    (void)clazz;
    if (!native_queue || ((u64)native_queue & 7))
        return -22; /* BAD_VALUE */
    const unsigned char *queue = (const unsigned char *)(u64)native_queue;
    /* update() binds mSurfaceControl; after that, the pre-producer contract
     * no longer holds. Never try to retrofit a live queue's buffer usage. */
    if (*(void *const *)(queue + 0x58))
        return -16; /* BUSY */
    void *consumer = *(void *const *)(queue + 0xc48);
    if (!consumer || ((u64)consumer & 7))
        return -19; /* NO_INIT */
    const u64 usage = *(const u64 *)((const unsigned char *)consumer + 0xa8);
    if (usage != 0x900)
        return -22; /* Not the measured, freshly initialized BLAST consumer. */
    /* ConsumerBase locks, calls the actual BufferQueueConsumer and returns
     * its status_t (including abandonment). Do not manufacture success. */
    return set_consumer_usage(consumer, usage | 0x400000000UL);
}
