// Minimal compat shim: taiko's real mitee KeyMint/Gatekeeper HAL binaries
// (bundled from retail firmware built with a newer libc++/NDK than this
// AOSP-13 TWRP tree ships) reference std::__libcpp_verbose_abort, added in
// a newer libc++ than the one built here. That function is only invoked on
// the abort/assertion-failure diagnostic path (never during normal
// successful operation), so a minimal drop-in replacement - not a full
// libc++ upgrade - is sufficient to satisfy the dynamic linker.
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

namespace std {
inline namespace __1 {

[[noreturn]] void __libcpp_verbose_abort(const char* format, ...) {
    va_list args;
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);
    fputc('\n', stderr);
    abort();
}

}  // namespace __1
}  // namespace std

// Second gap hit after fixing __libcpp_verbose_abort above: newer AIDL-
// compiler-generated interface stubs (android.hardware.security.rkp-V3-
// ndk.so among them) unconditionally call this at static-init/class-
// registration time to register human-readable transaction code names for
// bugreports/systrace - it's a debug-labeling side channel only, never
// consulted for actual RPC dispatch, so a no-op that ignores its arguments
// is functionally safe (real signature, per AOSP's binder_ibinder.h circa
// API 33, not present in this tree's older libbinder_ndk headers, hence
// the raw C types below instead of the real AIBinder_Class*).
extern "C" void AIBinder_Class_setTransactionCodeToFunctionNameMap(
        void* /*clazz*/, const char* const* /*transactionCodeToFunction*/, size_t /*length*/) {
}

// Third gap: libkeymaster_portable_mitee.so/libkeymint_mitee.so/
// libcppbor_external_mitee.so were built against a BoringSSL vintage that
// renamed the generic OPENSSL_STACK helpers from the classic unprefixed
// sk_* names to OPENSSL_sk_* (part of aligning with upstream OpenSSL's
// naming). This tree's own libcrypto.so still only exports the old
// unprefixed names (confirmed via nm -D) - same struct, same ABI, purely a
// naming-convention rename upstream, so - unlike the two stubs above -
// these are real forwarding wrappers to the equivalent already-linked
// libcrypto.so functions, not no-ops. OPENSSL_free needed no wrapper: this
// tree's libcrypto.so already exports it under that exact name.
typedef struct stack_st OPENSSL_STACK;

extern "C" {
OPENSSL_STACK* sk_new_null(void);
size_t sk_num(const OPENSSL_STACK* sk);
void* sk_value(const OPENSSL_STACK* sk, size_t i);
int sk_push(OPENSSL_STACK* sk, void* p);
}

extern "C" OPENSSL_STACK* OPENSSL_sk_new_null(void) {
    return sk_new_null();
}

extern "C" size_t OPENSSL_sk_num(const OPENSSL_STACK* sk) {
    return sk_num(sk);
}

extern "C" void* OPENSSL_sk_value(const OPENSSL_STACK* sk, size_t i) {
    return sk_value(sk, i);
}

extern "C" int OPENSSL_sk_push(OPENSSL_STACK* sk, void* p) {
    return sk_push(sk, p);
}
