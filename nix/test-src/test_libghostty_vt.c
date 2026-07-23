#include <xghostty/vt.h>
#include <stdio.h>
int main(void) {
    bool simd = false;
    XGhosttyResult r = xghostty_build_info(XGHOSTTY_BUILD_INFO_SIMD, &simd);
    if (r != XGHOSTTY_SUCCESS) return 1;
    printf("SIMD: %s\n", simd ? "yes" : "no");
    return 0;
}
