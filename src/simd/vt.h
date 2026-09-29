#if defined(XGHOSTTY_SIMD_VT_H_) == defined(HWY_TARGET_TOGGLE)
#ifdef XGHOSTTY_SIMD_VT_H_
#undef XGHOSTTY_SIMD_VT_H_
#else
#define XGHOSTTY_SIMD_VT_H_
#endif

#include <hwy/highway.h>

HWY_BEFORE_NAMESPACE();
namespace xghostty {
namespace HWY_NAMESPACE {

namespace hn = hwy::HWY_NAMESPACE;

}  // namespace HWY_NAMESPACE
}  // namespace xghostty
HWY_AFTER_NAMESPACE();

#if HWY_ONCE

namespace xghostty {

typedef void (*PrintFunc)(const char32_t* chars, size_t count);

}  // namespace xghostty

#endif  // HWY_ONCE

#endif  // XGHOSTTY_SIMD_VT_H_
