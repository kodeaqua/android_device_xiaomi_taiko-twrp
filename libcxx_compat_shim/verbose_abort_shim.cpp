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
