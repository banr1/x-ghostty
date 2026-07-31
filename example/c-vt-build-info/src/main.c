#include <stdio.h>
#include <xghostty/vt.h>

//! [build-info-query]
void query_build_info() {
  bool simd = false;
  bool kitty_graphics = false;
  bool tmux_control_mode = false;

  xghostty_build_info(XGHOSTTY_BUILD_INFO_SIMD, &simd);
  xghostty_build_info(XGHOSTTY_BUILD_INFO_KITTY_GRAPHICS, &kitty_graphics);
  xghostty_build_info(XGHOSTTY_BUILD_INFO_TMUX_CONTROL_MODE, &tmux_control_mode);

  printf("SIMD: %s\n", simd ? "enabled" : "disabled");
  printf("Kitty graphics: %s\n", kitty_graphics ? "enabled" : "disabled");
  printf("Tmux control mode: %s\n", tmux_control_mode ? "enabled" : "disabled");

  XGhosttyString version_string = {0};
  size_t version_major = 0;
  size_t version_minor = 0;
  size_t version_patch = 0;
  XGhosttyString version_pre = {0};
  XGhosttyString version_build = {0};

  xghostty_build_info(XGHOSTTY_BUILD_INFO_VERSION_STRING, &version_string);
  xghostty_build_info(XGHOSTTY_BUILD_INFO_VERSION_MAJOR, &version_major);
  xghostty_build_info(XGHOSTTY_BUILD_INFO_VERSION_MINOR, &version_minor);
  xghostty_build_info(XGHOSTTY_BUILD_INFO_VERSION_PATCH, &version_patch);
  xghostty_build_info(XGHOSTTY_BUILD_INFO_VERSION_PRE, &version_pre);
  xghostty_build_info(XGHOSTTY_BUILD_INFO_VERSION_BUILD, &version_build);

  printf("Version: %.*s\n", (int)version_string.len, version_string.ptr);
  printf("Version major: %zu\n", version_major);
  printf("Version minor: %zu\n", version_minor);
  printf("Version patch: %zu\n", version_patch);
  if (version_pre.len > 0) {
    printf("Version pre  : %.*s\n", (int)version_pre.len, version_pre.ptr);
  } else {
    printf("Version pre  : (none)\n");
  }
  if (version_build.len > 0) {
    printf("Version build: %.*s\n", (int)version_build.len, version_build.ptr);
  } else {
    printf("Version build: (none)\n");
  }
}
//! [build-info-query]

int main() {
  query_build_info();
  return 0;
}
