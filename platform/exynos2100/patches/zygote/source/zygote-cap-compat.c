/* Only libcap_rust's capability-bound query uses this private import.
 * A capability not implemented by this kernel cannot be in its bounding set.
 * Never hide errors querying an implemented capability or dropping any bit.
 */
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <unistd.h>

extern int cap_get_bound(int capability);

static int kernel_last_capability(void) {
    char text[16];
    int fd = open("/proc/sys/kernel/cap_last_cap", O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    ssize_t n;
    do { n = read(fd, text, sizeof(text)); } while (n < 0 && errno == EINTR);
    if (n < 2 || n >= (ssize_t)sizeof(text)) { close(fd); return -1; }
    char extra;
    ssize_t tail;
    do { tail = read(fd, &extra, 1); } while (tail < 0 && errno == EINTR);
    close(fd);
    if (tail != 0 || text[n - 1] != '\n') return -1;
    int value = 0;
    for (ssize_t i = 0; i < n - 1; ++i) {
        if (text[i] < '0' || text[i] > '9') return -1;
        value = value * 10 + text[i] - '0';
        if (value > 63) return -1;
    }
    return value;
}

__attribute__((visibility("default")))
int __unica_zygote_cap_get_bound(int capability) {
    int saved_errno = errno;
    int result = cap_get_bound(capability);
    int query_errno = errno;
    /* One UI 9's pinned Rust Capability enum stops at CHECKPOINT_RESTORE (40).
     * Out-of-contract and negative inputs retain the real native result.
     */
    if (result == -1 && query_errno == EINVAL && capability >= 0 && capability <= 40) {
        int last = kernel_last_capability();
        if (last >= 0 && capability > last) {
            errno = saved_errno;
            return 0;
        }
    }
    errno = query_errno;
    return result;
}
