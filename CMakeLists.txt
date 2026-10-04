cmake_minimum_required(VERSION 3.22)

# Static CRT must be set BEFORE project() — ensures /MT over /MD
# (aligns with ixwebsocket x64-windows-static + WebView2 static loader)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- macOS 目标设定（必须在 project() 之前：参与编译器探测）---
# 非 Apple 平台完全忽略这两个变量 -> Windows 零影响。project() 前 if(APPLE) 未定义，故用 NOT DEFINED 守卫（命令行可覆盖）。
if(NOT DEFINED CMAKE_OSX_ARCHITECTURES)
  # v1 仅 Apple Silicon。Universal 不做：双架构让 juceaide 与全部 JUCE 模块编译量翻倍。
  set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "macOS target architecture")
endif()
if(NOT DEFINED CMAKE_OSX_DEPLOYMENT_TARGET)
  # 11.0 = arm64 Mac 物理下限（Big Sur 是首个支持 Apple Silicon 的系统）。
  # 不显式设则取构建机 SDK 版本，产物会在老系统上拒绝加载——mac 移植最常见的静默事故。
  set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "Minimum macOS version")
endif()

project(SynchainBridgeVST VERSION 1.5.3)

# Export compile_commands.json for clangd / clang-tidy (08 §3.2)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# --- JUCE Setup ---
# Point this to your local JUCE installation, or use FetchContent
set(JUCE_PATH "" CACHE PATH "Path to JUCE root directory")

if(NOT JUCE_PATH)
  message(FATAL_ERROR "JUCE_PATH must be set. Example: -DJUCE_PATH=/path/to/JUCE")
endif()

add_subdirectory(${JUCE_PATH} juce)

# ------------------------------------------------------------------
# WebView2 NuGet package (Windows only)
# JUCE's NEEDS_WEBVIEW2 only *searches + links* an already-present NuGet
# package (it does NOT download). We fetch it at configure time into a
# deterministic dir and point JUCE_WEBVIEW2_PACKAGE_LOCATION at it, so the
# build is reproducible locally and in CI (no dependency on %USERPROFILE%).
# ------------------------------------------------------------------
if(WIN32)
  set(WEBVIEW2_VERSION "1.0.2957.106" CACHE STRING "Microsoft.Web.WebView2 NuGet version")
  set(WEBVIEW2_PKG_DIR "${CMAKE_BINARY_DIR}/packages")

  # Skip download if the package is already present (offline / cached CI)
  file(GLOB _wv2_existing "${WEBVIEW2_PKG_DIR}/Microsoft.Web.WebView2*")
  if(NOT _wv2_existing)
    find_program(NUGET_EXE nuget) # windows runners ship nuget.exe
    if(NOT NUGET_EXE)
      message(FATAL_ERROR
        "nuget.exe not found. Install the NuGet CLI or pre-populate ${WEBVIEW2_PKG_DIR}.")
    endif()
    message(STATUS "Fetching Microsoft.Web.WebView2 ${WEBVIEW2_VERSION} via NuGet ...")
    execute_process(
      COMMAND "${NUGET_EXE}" install Microsoft.Web.WebView2
              -Version ${WEBVIEW2_VERSION}
              -OutputDirectory "${WEBVIEW2_PKG_DIR}"
              -ExcludeVersion # fixed dir name: Microsoft.Web.WebView2 (no version suffix)
      RESULT_VARIABLE _nuget_rc)
    if(NOT _nuget_rc EQUAL 0)
      message(FATAL_ERROR "nuget install Microsoft.Web.WebView2 failed (rc=${_nuget_rc}).")
    endif()
  endif()

  # Make JUCE's FindWebView2 look here (overrides the default %USERPROFILE% path)
  set(JUCE_WEBVIEW2_PACKAGE_LOCATION "${WEBVIEW2_PKG_DIR}" CACHE PATH "" FORCE)
endif()

# --- AAX（Avid Pro Tools）---
# JUCE 8.0.8 仅在「非 GCC 且 (Darwin 或 Windows x86_64)」生成 AAX 目标(JUCEModuleSupport.cmake
# _juce_get_platform_plugin_kinds)，其余平台静默滤掉。这里按同一条件现算，只为让 configure 日志
# 说真话 + 「该建却没建」时 fail-closed(升 JUCE 版本时的 tripwire)。SDK = JUCE 自带 AAX SDK 2.8.0
# (GPLv3 选项)，不引外部 SDK、CI 零 secret；不调 juce_set_aax_sdk_path(JUCE 已自动挂载自带 SDK，
# 再调一次直接 FATAL)。两平台默认 ON(macOS 仍 arm64-only)；-DSYNCHAIN_BRIDGE_AAX=OFF 可整体关掉。
# JUCE_TARGET_ARCHITECTURE 是 CACHE INTERNAL，上面 add_subdirectory(JUCE) 之后才读得到 —— 本段不能上移。
option(SYNCHAIN_BRIDGE_AAX "Build the AAX (Pro Tools) format where JUCE supports it" ON)

set(_bridge_aax_supported FALSE)
if(NOT CMAKE_CXX_COMPILER_ID STREQUAL "GNU"
   AND (CMAKE_SYSTEM_NAME STREQUAL "Darwin"
        OR (CMAKE_SYSTEM_NAME STREQUAL "Windows" AND JUCE_TARGET_ARCHITECTURE STREQUAL "x86_64")))
  set(_bridge_aax_supported TRUE)
endif()

set(SYNCHAIN_BRIDGE_FORMATS VST3 AU)   # AU 在非 Apple 被 JUCE 滤掉(见下方 juce_add_plugin 注释)
if(SYNCHAIN_BRIDGE_AAX AND _bridge_aax_supported)
  list(APPEND SYNCHAIN_BRIDGE_FORMATS AAX)
elseif(SYNCHAIN_BRIDGE_AAX)
  message(STATUS "AAX requested but unsupported by JUCE on "
                 "${CMAKE_SYSTEM_NAME}/${CMAKE_CXX_COMPILER_ID}/${JUCE_TARGET_ARCHITECTURE}; skipped")
endif()

# --- Plugin Target ---
juce_add_plugin(SynchainBridgeVST
  COMPANY_NAME        "Synchain"
  PLUGIN_MANUFACTURER_CODE Snch
  PLUGIN_CODE         Snb1
  # AU 在非 Apple 平台被 JUCE 静默过滤掉（机制上是 no-op），故无需按平台分支。
  # 该静默过滤行为按 JUCE 8.0.8（`.juce-version` 当前钉的版本）实证，并非 JUCE 的书面约定；
  # 升 JUCE 版本时需在 Windows 侧重验一次「带 AU 也不影响 VST3 产物」（见 PR #19 审查）。
  # AAX 在 JUCE 不支持的平台同样被静默过滤；由上方 AAX 段按同一条件现算，加下方 FATAL tripwire 兜底。
  FORMATS             ${SYNCHAIN_BRIDGE_FORMATS}
  PRODUCT_NAME        "Synchain Bridge"

  # "Fx" is added automatically by JUCE for VST3 audio effects.
  # Only specify sub-categories here to avoid duplicate "Fx" in moduleinfo.json.
  VST3_CATEGORIES     "Analyzer"

  # --- AU 专属 ---
  # 显式写死 AU 类型（当前默认推导也是 Effect；写死是防将来加 NEEDS_MIDI_INPUT 时
  # componentType 从 aufx 漂成 aumf——那等于换插件身份，用户工程里的 AU 实例全部丢失）。
  AU_MAIN_TYPE        kAudioUnitType_Effect
  # AU_SANDBOX_SAFE 保持 JUCE 默认 FALSE，绝对不要设 TRUE：本插件 bind 127.0.0.1 监听
  # socket + 起 WKWebView，两者在 AU sandbox 里都会被拒。代价：GarageBand（只收
  # sandboxSafe AU）可能拒载，Logic 以非沙箱方式加载。v1 接受，已写入 README 已知限制。

  # Bundle identifier
  BUNDLE_ID           "com.synchain.bridge"

  # --- AAX 专属（FORMATS 不含 AAX 时只是几个不被读的 JucePlugin_AAX* 宏）---
  # 会话身份 = ManufacturerID(Snch) + ProductID(Snb1) + 每个 stem 组合的 PlugIn ID(JUCE
  # AAXClientExtensions 按主总线 in/out 现算：mono→mono 'jcbb'、stereo→stereo 'jccc')；后者由
  # PluginProcessor::isBusesLayoutSupported 决定 —— 发版后只许加、不许删。
  AAX_IDENTIFIER         com.synchain.bridge
  # 推流旁路不改音频：SDK 无 Analyzer/Utility 类；None = PT 按类别组织菜单时进 "Other"。
  # 类别不进会话身份，日后可改(PT 重扫缓存即可)。
  AAX_CATEGORY           AAX_ePlugInCategory_None
  # 禁 multi-mono：否则 PT 会在立体声/环绕轨按声道各开一个 mono 实例 → 各起一个 WS 服务。
  DISABLE_AAX_MULTI_MONO TRUE
  # 不设 COPY_PLUGIN_AFTER_BUILD(会往系统 Avid 插件目录写)；DISABLE_AAX_BYPASS 保持默认 FALSE
  # (宿主旁路走 processBlockBypassed：音频直通、推流暂停，与 VST3 一致)。

  # Windows: link the WebView2 loader (macOS/Linux ignore this). See NuGet block above.
  NEEDS_WEBVIEW2      TRUE
)

if(TARGET SynchainBridgeVST_AAX)
  # 关 AudioSuite(离线处理)注册：本插件不改音频，离线跑一遍无意义。JUCEUtils 无对应关键字，宏只在
  # juce_audio_plugin_client_AAX.cpp `#if ! JucePlugin_AAXDisableAudioSuite` 处被读(未定义 = 注册)；
  # wrapper TU 是 INTERFACE 源、编在本目标里，PRIVATE 即达且不污染共享代码编译参数。
  target_compile_definitions(SynchainBridgeVST_AAX PRIVATE JucePlugin_AAXDisableAudioSuite=1)
elseif(SYNCHAIN_BRIDGE_AAX AND _bridge_aax_supported)
  message(FATAL_ERROR "SYNCHAIN_BRIDGE_AAX=ON and JUCE should support AAX here, "
                      "but SynchainBridgeVST_AAX was not created (JUCE format filtering changed?)")
endif()

# --- Embedded web UI assets (offline, no external deps) ---
# Compiled into a static lib exposing BinaryData::* (index.html/styles.css/bridge.js/
# i18n.js/index.js). WebViewEditor's resource provider serves them by original filename.
juce_add_binary_data(SynchainBridgeWebAssets SOURCES
  web/index.html
  web/styles.css
  web/bridge.js
  web/i18n.js
  web/js/juce/index.js
  web/js/juce/check_native_interop.js  # sibling side-effect import of index.js
  # Offline text-subset WOFF2 (Google Fonts, subset to used glyphs only ~73KB total)
  # Bridge Sans/Mono = renamed subsets: file name, CSS family AND the woff2 `name` table are
  # all free of the upstream Reserved Font Name (OFL-1.1 §3; details in THIRD-PARTY-NOTICES.md)
  web/fonts/SpaceGrotesk.woff2
  web/fonts/BridgeSans.woff2
  web/fonts/BridgeMono.woff2
  web/fonts/NotoSansSC.woff2
)

# --- Dependencies ---
# Windows: vcpkg x64-windows-static（全静态），manifest 模式——版本由仓库根 vcpkg.json 的 builtin-baseline
#   （40 位 commit）+ overrides 钉死，configure 期经 vcpkg toolchain 自动装进 <build>/vcpkg_installed。
# macOS: FetchContent，commit 钉死（下方 IXWEBSOCKET_TAG），不引入包管理器。两侧升版本必须同一 PR 一起动。

if(APPLE)
  # 版本号对齐 Windows 侧 vcpkg port 实际安装的 ixwebsocket 12.0.1：permessage-deflate 协商 /
  # close code / handshake header 解析这些 wire 层行为跨平台不漂移，才谈得上单一契约（CLAUDE.md §5 §7）。
  # 注意口径是「版本号对齐」而非字节级同源：vcpkg port 可能带 vcpkg 侧补丁，这里 FetchContent 拉的是
  # 上游裸 tag。两侧真出现行为差异时以本注释为排查起点（见 PR #19 审查）。
  # 钉 40 位 commit SHA 而不是 tag 名(CLAUDE.md §0 铁律 3 的同源要求:tag 是可变 ref,上游重指后
  # 静态链进 .vst3/.component 的依赖会静默换掉,且没有任何机器检查能发现;采纳 PR #24 review)。
  # 该 SHA = 上游 tag v12.0.1 当时指向的 commit(git ls-remote --tags 核对),注释保留 tag 名便于升级。
  set(IXWEBSOCKET_TAG "64fae7676bd8fe31f7cb4bcde7a6841892dad65e" CACHE STRING "IXWebSocket pinned commit SHA (= tag v12.0.1)")
  # 桥 #2 只在 127.0.0.1 上服务明文 ws://（见 VstBridgeServer::start），无 TLS 需求；
  # 关 TLS 即不需要 mbedtls/Security.framework。CMP0077=NEW 下 set 可压过 option，CACHE FORCE 双保险。
  set(USE_TLS             OFF CACHE BOOL "" FORCE)
  # USE_WS / USE_TEST 在上游不是 option()，只是被 if() 读的普通变量：置 ON 会 add_subdirectory(ws|test)
  # 并顺带 FetchContent 一个 spdlog。显式写死 OFF，免得父作用域里已有的同名变量把它们带进来。
  set(USE_WS              OFF CACHE BOOL "" FORCE)
  set(USE_TEST            OFF CACHE BOOL "" FORCE)
  set(BUILD_DEMO          OFF CACHE BOOL "" FORCE)
  # 上游 option 默认 OFF，但外层只要带 -DBUILD_SHARED_LIBS=ON（superbuild，或复用了别的 build 目录的
  # cache），ixwebsocket 就会变成 dylib：它不会被拷进 .vst3/.component 的 Frameworks，也没有任何 rpath
  # 处理，装到 ~/Library 后换台机器直接加载失败。mac 侧产物必须自包含，故与上面五个变量同样写死。
  set(BUILD_SHARED_LIBS   OFF CACHE BOOL "" FORCE)
  # 上游默认 TRUE：不关掉会把 ixwebsocket 的 install 规则挂进本工程的 INSTALL 目标。
  set(IXWEBSOCKET_INSTALL OFF CACHE BOOL "" FORCE)
  # USE_ZLIB 保持上游默认 ON（与 vcpkg port 一致，permessage-deflate 行为跨平台不漂移）；macOS SDK 自带 libz。
  include(FetchContent)
  # 不能再 GIT_SHALLOW:浅克隆是 `git fetch --depth 1 <ref>`,只对分支名/tag 名成立,给裸 commit SHA
  # 会 fetch 失败、配置期直接炸。代价是 mac 侧配置期多克隆一份完整历史(上游仓很小)。
  FetchContent_Declare(ixwebsocket
    GIT_REPOSITORY https://github.com/machinezone/IXWebSocket.git
    GIT_TAG        ${IXWEBSOCKET_TAG})   # v12.0.1
  FetchContent_MakeAvailable(ixwebsocket)
  # 上游自带 ALIAS ixwebsocket::ixwebsocket 且 include 目录 PUBLIC，link 行无需分支。
else()
  # ixwebsocket (static, bundles mbedtls for TLS — no separate OpenSSL needed)
  find_package(ixwebsocket CONFIG REQUIRED)
  find_path(IXWEBSOCKET_INCLUDE_DIR ixwebsocket/IXWebSocketServer.h REQUIRED)
endif()

# --- Source Files ---
target_sources(SynchainBridgeVST PRIVATE
  src/PluginProcessor.h
  src/PluginProcessor.cpp
  src/WebViewEditor.h
  src/WebViewEditor.cpp
  src/BridgeApi.h
  src/VstBridgeServer.h
  src/VstBridgeServer.cpp
  src/AudioMeter.h
  src/AudioMeter.cpp
  src/WebSocketProtocol.h
  src/WebSocketProtocol.cpp
)

# --- Include Directories ---
target_include_directories(SynchainBridgeVST PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
if(NOT APPLE)
  # APPLE 下 include 目录由 FetchContent 的 ixwebsocket target 以 PUBLIC 传递，无此变量。
  target_include_directories(SynchainBridgeVST PRIVATE ${IXWEBSOCKET_INCLUDE_DIR})
endif()

# --- Link Libraries ---
target_link_libraries(SynchainBridgeVST PRIVATE
  juce::juce_audio_plugin_client
  juce::juce_gui_extra            # WebBrowserComponent lives here
  ixwebsocket::ixwebsocket
  SynchainBridgeWebAssets         # generated BinaryData
)

# mbedtls (bundled with ixwebsocket) requires bcrypt for BCryptGenRandom on Windows
if(WIN32)
  target_link_libraries(SynchainBridgeVST PRIVATE bcrypt)
endif()

# --- Compiler Options ---
if(MSVC)
  target_compile_options(SynchainBridgeVST PRIVATE /W4 /utf-8)
else()
  target_compile_options(SynchainBridgeVST PRIVATE -Wall -Wextra -Wpedantic)
endif()

# --- Compile Definitions ---
# PUBLIC so the flags reach the JUCE module sources compiled into the format wrappers.
target_compile_definitions(SynchainBridgeVST PUBLIC
  JUCE_VST3_CAN_REPLACE_VST2=0
  JUCE_WEB_BROWSER=1              # enable WebBrowserComponent
)
if(WIN32)
  target_compile_definitions(SynchainBridgeVST PUBLIC
    JUCE_USE_WIN_WEBVIEW2=1
    JUCE_USE_WIN_WEBVIEW2_WITH_STATIC_LINKING=1  # static loader -> no WebView2Loader.dll at runtime
  )
endif()

# --- Origin allow-list: extra hosts injected at build time (decision U4) ---
# The repository source only carries the synchain.ca/.cn defaults (see isAllowedOrigin()
# in src/VstBridgeServer.cpp). Deployment-platform preview domains and any other extra
# origins are NOT stored in the repo: pass them at configure time instead.
#
#   cmake -S . -B build -DBRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS="example-git-*-example-team.example.app;preview.example.com"
#
# ';' or ',' separated host patterns, at most ONE '*' per pattern. The '*' matches a
# non-empty run of characters within a SINGLE DNS label (it never crosses a '.'), it must
# sit inside the LEFTMOST label, and what follows the first '.' must still be a 2+ segment
# domain anchor whose last segment is an all-alphabetic TLD of 2+ chars. So '*', '*.',
# '-*', '*.com' and '*example.app' are all dropped fail-closed — none of them may turn into
# a blanket wildcard. https is still required. Empty by default -> the macro is NOT defined
# -> a default build allows no extra origin at all. Rules live in src/OriginAllowlist.h and
# are asserted by tests/origin_allowlist_selftest.cpp (-DBRIDGE_BUILD_SELFTESTS=ON).
set(BRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS "" CACHE STRING
  "Extra Origin host patterns to allow (';' or ',' separated; at most one '*' per pattern)")

# The value ends up inside a C string literal in the generated header, so quotes and
# backslashes would break out of it — reject them instead of emitting a broken header.
# Literal string(FIND) rather than a regex: no bracket-expression escaping to get wrong.
string(FIND "${BRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS}" "\"" _bridge_origin_quote_at)
string(FIND "${BRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS}" "\\" _bridge_origin_backslash_at)
if(NOT _bridge_origin_quote_at EQUAL -1 OR NOT _bridge_origin_backslash_at EQUAL -1)
  message(FATAL_ERROR
    "BRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS must not contain quotes or backslashes.")
endif()

if(BRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS)
  # CMake lists are ';' separated — normalise to ',', which is what the C++ side splits on.
  string(REPLACE ";" "," _bridge_extra_origin_hosts "${BRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS}")
  set(BRIDGE_EXTRA_ORIGIN_DEFINE
    "#define BRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS \"${_bridge_extra_origin_hosts}\"")
  # Deliberately not echoing the values: build logs of a public CI should not carry them.
  message(STATUS "Origin allow-list: extra host patterns injected at build time")
else()
  set(BRIDGE_EXTRA_ORIGIN_DEFINE
    "// no extra origins configured -> BRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS stays undefined")
endif()

# Generated header rather than target_compile_definitions: a quoted string define is
# escaped differently by the Visual Studio and Ninja/Makefile generators, while a header
# is byte-identical everywhere. Always generated (empty when nothing is injected) so the
# unconditional #include in VstBridgeServer.cpp always resolves.
configure_file(cmake/BridgeOriginConfig.h.in
  "${CMAKE_CURRENT_BINARY_DIR}/generated/BridgeOriginConfig.h" @ONLY)
target_include_directories(SynchainBridgeVST PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")

# --- Optional: pure-logic selftests ---
# Three dependency-free executables, one per pure header under src/:
#   origin_allowlist_selftest — src/OriginAllowlist.h (normalisation, injected-pattern
#                               usability, pattern matching);
#   pcm_frame_selftest        — src/PcmFrame.h (12-byte PCM frame header, golden bytes per
#                               BRIDGE_CONTRACT.md §二 1; the legacy synchronous path and
#                               the sender-thread path in src/VstBridgeServer.cpp both
#                               encode through it);
#   reveal_gate_selftest      — src/WebViewRevealGate.h (SL-386 reveal gate: first-frame-only
#                               release, navFinished bookkeeping only, settle ticks ∧ 32 ms
#                               floor with wrap safety, 3s timeout, parked geometry, placeholder
#                               gradient golden).
# Standard library only: no JUCE, no ixwebsocket, no link against the plugin target — so
# they build and run in seconds. OFF by default; the local gate script (scripts/gates.ps1)
# and both ci.yml build jobs configure with -DBRIDGE_BUILD_SELFTESTS=ON and run all three, so
# the /W4 and clang -Wall -Wextra -Wpedantic zero-warning gates cover the selftests too;
# the compliance workflow compiles the same sources with plain g++ on ubuntu.
option(BRIDGE_BUILD_SELFTESTS "Build pure-logic selftests (origin allowlist + PCM frame + reveal gate)" OFF)
if(BRIDGE_BUILD_SELFTESTS)
  foreach(_selftest IN ITEMS origin_allowlist_selftest pcm_frame_selftest reveal_gate_selftest)
    add_executable(${_selftest} tests/${_selftest}.cpp)
    target_compile_features(${_selftest} PRIVATE cxx_std_17)
    target_include_directories(${_selftest} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    if(MSVC)
      target_compile_options(${_selftest} PRIVATE /W4 /utf-8)
    else()
      target_compile_options(${_selftest} PRIVATE -Wall -Wextra -Wpedantic)
    endif()
  endforeach()
endif()

# --- Platform-Specific ---
# 状态行按「实际建出的目标」拼格式表，不按开关推断。macOS 行在 AAX 关闭时与旧文案逐字相同
# (docs/build-macos.md 引用了这行输出)。
set(_bridge_fmt_win "VST3")
set(_bridge_fmt_mac "VST3 + AU")
if(TARGET SynchainBridgeVST_AAX)
  string(APPEND _bridge_fmt_win " + AAX")
  string(APPEND _bridge_fmt_mac " + AAX")
  message(STATUS "AAX: JUCE-bundled SDK (GPLv3 option), unsigned -> loads in Pro Tools Developer only until PACE-signed")
endif()
if(WIN32)
  message(STATUS "Building Synchain Bridge for Windows: ${_bridge_fmt_win} (static CRT, WebView2)")
elseif(APPLE)
  message(STATUS "Building Synchain Bridge for macOS: ${_bridge_fmt_mac}, "
                 "arch=${CMAKE_OSX_ARCHITECTURES}, min=${CMAKE_OSX_DEPLOYMENT_TARGET}, WKWebView")
endif()
