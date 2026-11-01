/* SPDX-License-Identifier: Apache-2.0 */
/* Additional QPR2 entry points beside the retained Samsung Bionic provider. */
#include <stddef.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <stdlib.h>

__attribute__((visibility("default")))
int membarrier(int command, unsigned int flags, int cpu_id)
{
    return (int)syscall(__NR_membarrier, command, flags, cpu_id);
}

__attribute__((visibility("default")))
int execveat(int directory_fd, const char *pathname, char *const argv[],
             char *const environment[], int flags)
{
    return (int)syscall(__NR_execveat, directory_fd, pathname, argv, environment, flags);
}

/* C23 size/alignment arguments are hints; the original allocator owns checks. */
__attribute__((visibility("default")))
void free_sized(void *pointer, size_t size)
{
    (void)size;
    free(pointer);
}

__attribute__((visibility("default")))
void free_aligned_sized(void *pointer, size_t alignment, size_t size)
{
    (void)alignment;
    (void)size;
    free(pointer);
}
