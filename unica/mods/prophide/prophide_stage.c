/* SPDX-License-Identifier: GPL-3.0-or-later
 * One UI 9 Prophide staging/readback helper. Never writes protected properties.
 * Init delegates ONLY a read-only vbmeta FD, then performs the protected sets.
 */
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

extern int __system_property_set(const char *, const char *);
extern int __system_property_get(const char *, char *);
extern const void *__system_property_find(const char *);
extern unsigned __system_property_serial(const void *);
extern unsigned char *SHA256(const unsigned char *, size_t, unsigned char *);

_Static_assert(sizeof(struct stat) == 128 && offsetof(struct stat, st_mode) == 16 &&
               offsetof(struct stat, st_rdev) == 32, "One UI 9 AArch64 stat ABI");

#define STAGE "sys.unica.prophide."
#define PATCH_DATE "2026-10-05"
#define VB_SIZE 9344U
#define PK_OFFSET 8288U
#define PK_SIZE 1032U

static const char *const names[] = {
    "ro.boot.flash.locked", "ro.boot.vbmeta.avb_version", "ro.boot.vbmeta.device_state",
    "ro.boot.vbmeta.digest", "ro.boot.vbmeta.hash_alg", "ro.boot.vbmeta.invalidate_on_error",
    "ro.boot.vbmeta.public_key_digest", "ro.boot.vbmeta.size", "ro.boot.warranty_bit",
    "ro.boot.verifiedbootstate", "ro.boot.veritymode", "ro.vendor.build.security_patch"
};

static int fail(const char *reason) {
    /* Only a staging/status key; it cannot forge init's result channel. */
    (void)__system_property_set(STAGE "status", "failed");
    fprintf(stderr, "Prophide: %s; property hiding is not verified\n", reason);
    return 1;
}

static int equal(const char *name, const char *expected) {
    char actual[92];
    return __system_property_get(name, actual) >= 0 && !strcmp(actual, expected);
}

static uint64_t be64(const unsigned char *p) {
    uint64_t value = 0;
    for (unsigned i = 0; i < 8; ++i) value = (value << 8) | p[i];
    return value;
}

static int vbmeta(unsigned char *image) {
    const char *s = getenv("ANDROID_FILE__dev_block_by_name_vbmeta");
    unsigned fd = 0;
    if (!s || !*s) return 0;
    for (; *s; ++s) {
        if (*s < '0' || *s > '9' || fd > 102) return 0;
        fd = fd * 10 + (unsigned)(*s - '0');
    }
    if (fd < 3 || fd > 1023) return 0;
    int flags = fcntl((int)fd, F_GETFL);
    struct stat inherited, named;
    if (flags < 0 || (flags & O_ACCMODE) != O_RDONLY ||
        fstat((int)fd, &inherited) || !S_ISBLK(inherited.st_mode) ||
        stat("/dev/block/by-name/vbmeta", &named) || !S_ISBLK(named.st_mode) ||
        inherited.st_rdev != named.st_rdev) return 0;
    /* pread does not depend on any inherited seek position. No reopen, ioctl,
     * write, block-size query, shell, temporary file or privileged capability. */
    size_t done = 0;
    while (done < VB_SIZE) {
        ssize_t n = pread((int)fd, image + done, VB_SIZE - done, (off_t)done);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return 0;
        done += (size_t)n;
    }
    if (close((int)fd)) return 0;
    if (memcmp(image, "AVB0", 4)) return 0;
    uint64_t auth = be64(image + 12), aux = be64(image + 20);
    uint64_t off = be64(image + 64), size = be64(image + 72);
    return auth <= VB_SIZE - 256 && aux == VB_SIZE - 256 - auth &&
           off <= aux && size <= aux - off &&
           256 + auth + off == PK_OFFSET && size == PK_SIZE;
}

static int digest(const unsigned char *data, size_t size, char hex[65]) {
    static const char digits[] = "0123456789abcdef";
    unsigned char result[32];
    if (!SHA256(data, size, result)) return 0;
    for (unsigned i = 0; i < 32; ++i) {
        hex[i * 2] = digits[result[i] >> 4];
        hex[i * 2 + 1] = digits[result[i] & 15];
    }
    hex[64] = 0;
    return 1;
}

int main(int argc, char **argv, char **envp) {
    (void)argv; (void)envp;
    if (argc != 1) return fail("unexpected argument");
    unsigned char image[VB_SIZE];
    char vb_hash[65], key_hash[65];
    if (!equal("ro.build.version.security_patch", PATCH_DATE)) return fail("unexpected system security patch");
    if (!vbmeta(image)) return fail("invalid read-only vbmeta descriptor, image or geometry");
    if (!digest(image, sizeof(image), vb_hash) || !digest(image + PK_OFFSET, PK_SIZE, key_hash))
        return fail("SHA-256 failed");
    const char *values[] = {"1", "1.3", "locked", vb_hash, "sha256", "yes", key_hash,
                           "9344", "0", "green", "enforcing", PATCH_DATE};
    /* Bionic cannot safely inline-update an existing long ro.* record.
     * The native adapter independently enforces the same record bound.
     * The vendor warranty record is checked inside init, not read here. */
    for (unsigned i = 0; i < sizeof(names) / sizeof(names[0]); ++i) {
        const void *pi = __system_property_find(names[i]);
        if (pi) {
            unsigned serial = __system_property_serial(pi);
            if ((serial & (1U << 16)) || (serial >> 24) > 91)
                return fail("unexpected long property record");
        }
    }
    if (!equal(STAGE "result.done", "1")) {
        /* Ready is published LAST. Invalid/short reads cannot trigger writes. */
        if (__system_property_set(STAGE "ready", "0") ||
            __system_property_set(STAGE "status", "staging") ||
            __system_property_set(STAGE "vbmeta_digest", vb_hash) ||
            __system_property_set(STAGE "vbmeta_public_key_digest", key_hash) ||
            __system_property_set(STAGE "vbmeta_size", "9344") ||
            __system_property_set(STAGE "security_patch", PATCH_DATE) ||
            __system_property_set(STAGE "ready", "1")) return fail("staging property rejected");
        struct timespec start, now, pause = {0, 100000000};
        if (clock_gettime(CLOCK_MONOTONIC, &start)) return fail("clock unavailable");
        while (!equal(STAGE "result.done", "1")) {
            if (clock_gettime(CLOCK_MONOTONIC, &now) || now.tv_sec - start.tv_sec >= 30)
                return fail("init handoff timed out");
            (void)nanosleep(&pause, NULL);
        }
    }
    for (unsigned i = 0; i < sizeof(names) / sizeof(names[0]); ++i)
        if (!equal(names[i], values[i])) return fail("protected property readback mismatch");
    /* vendor_default_prop cannot be read by this coredomain. Init reads the
     * real property into an init-only result type after attempting every set.
     * result.done marks handoff completion, NOT successful hiding. */
    if (!equal(STAGE "result.vendor_warranty_bit", "0")) return fail("init warranty readback mismatch");
    if (__system_property_set(STAGE "status", "verified")) return fail("status publication failed");
    return 0;
}

/* Standard Bionic dynamic-process startup. No constructors of our own. */
extern void __libc_init(void *, void (*)(void), int (*)(int, char **, char **), const void *) __attribute__((noreturn));
__attribute__((visibility("hidden"), noreturn)) void prophide_start(void *raw) {
    static const void *const structors[3] = {NULL, NULL, NULL};
    __libc_init(raw, NULL, main, structors);
}
__asm__(".text\n.p2align 2\n.global _start\n.hidden _start\n_start:\nbti c\nmov x0,sp\nb prophide_start\n");
