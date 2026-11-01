/* Reviewed One UI 9 init-only Prophide adapter; no new dynamic dependency.
 * Linked into unused tail padding of the ORIGINAL init RX PT_LOAD.
 * Only the already-permission-checked HandlePropertySet call is redirected.
 * All non-approved calls keep the original PropertySet(..., false) path.
 */
typedef unsigned long u64;
typedef unsigned int u32;
typedef unsigned char u8;
struct string { u8 data[24]; };
struct creds { int pid; u32 uid, gid; };
extern u64 stock_property_set(const struct string *, const struct string *, void *, void *, int);
extern const void *stock_property_find(const char *);
extern int stock_property_update(const void *, const char *, unsigned);
extern int stock_property_add(const char *, unsigned, const char *, unsigned);

static u64 size(const struct string *s) {
    return (s->data[0] & 1) ? ((const u64 *)s)[1] : (s->data[0] >> 1);
}
static const char *chars(const struct string *s) {
    return (s->data[0] & 1) ? ((const char *const *)s)[2] : (const char *)s + 1;
}
__attribute__((noinline)) static int same(const struct string *s, const char *literal) {
    u64 n = size(s); const char *p = chars(s);
    for (u64 i = 0; i < n; ++i) if (!literal[i] || p[i] != literal[i]) return 0;
    return literal[n] == 0;
}
static int digest(const struct string *s) {
    if (size(s) != 64) return 0;
    const char *p = chars(s);
    for (unsigned i = 0; i < 64; ++i)
        if (!((p[i] >= '0' && p[i] <= '9') || (p[i] >= 'a' && p[i] <= 'f'))) return 0;
    return 1;
}
__attribute__((noinline)) static int allowed(const struct string *n, const struct string *v) {
    if (same(n, "ro.boot.flash.locked")) return same(v, "1");
    if (same(n, "ro.boot.vbmeta.avb_version")) return same(v, "1.3");
    if (same(n, "ro.boot.vbmeta.device_state")) return same(v, "locked");
    if (same(n, "ro.boot.vbmeta.digest")) return digest(v);
    if (same(n, "ro.boot.vbmeta.hash_alg")) return same(v, "sha256");
    if (same(n, "ro.boot.vbmeta.invalidate_on_error")) return same(v, "yes");
    if (same(n, "ro.boot.vbmeta.public_key_digest")) return digest(v);
    if (same(n, "ro.boot.vbmeta.size")) return same(v, "9344");
    if (same(n, "ro.boot.warranty_bit")) return same(v, "0");
    if (same(n, "ro.boot.verifiedbootstate")) return same(v, "green");
    if (same(n, "ro.boot.veritymode")) return same(v, "enforcing");
    if (same(n, "ro.vendor.boot.warranty_bit")) return same(v, "0");
    if (same(n, "ro.vendor.build.security_patch")) return same(v, "2026-10-05");
    return 0;
}
__attribute__((section(".text.entry"), visibility("hidden")))
u64 prophide_property_set(const struct string *name, const struct string *value,
                         void *socket, void *error, const struct creds *peer) {
    /* Kernel-supplied SO_PEERCRED, not an IPC string or an executable label.
     * Require the real init process and its ordinary, permission-checked socket
     * path. Boot-default/no-socket calls and all external callers stay stock.
     */
    if (!peer || peer->pid != 1 || peer->uid || peer->gid || !socket || !allowed(name, value))
        return stock_property_set(name, value, socket, error, 0);
    const char *n = chars(name), *v = chars(value);
    const void *pi = stock_property_find(n);
    /* Bionic Update only supports short property records. Never pass an
     * existing long ro.* record to it: its separate long-value storage and
     * cached pointer contract cannot be replaced by an inline-value update.
     * The verified One UI 9 prop_info serial is its first 32-bit word, and
     * bit 16 (not the length byte) identifies separately stored long values.
     */
    if (pi) {
        u32 serial = *(const volatile u32 *)pi;
        if ((serial & (1U << 16)) || (serial >> 24) > 91)
            return stock_property_set(name, value, socket, error, 0);
    }
    int result = pi ? stock_property_update(pi, v, (unsigned)size(value)) :
                      stock_property_add(n, (unsigned)size(name), v, (unsigned)size(value));
    /* Exact -n behavior: Bionic updates/creates the real shared property area,
     * with no PropertyChanged/persistence call. std::optional<uint32_t> ABI:
     * present=1 in bit 32; PROP_SUCCESS=0 / PROP_ERROR_SET_FAILED=0x24.
     */
    return (1UL << 32) | (result < 0 ? 0x24UL : 0UL);
}
