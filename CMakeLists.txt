cmake_minimum_required(VERSION 3.22)

# Static CRT must be set BEFORE project() — ensures /MT over /MD
# (aligns with ixwebsocket x64-windows-static + WebView2 static loader)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

project(SynchainBridgeVST VERSION 1.4.0)

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

# --- Plugin Target ---
juce_add_plugin(SynchainBridgeVST
  COMPANY_NAME        "Synchain"
  PLUGIN_MANUFACTURER_CODE Snch
  PLUGIN_CODE         Snb1
  FORMATS             VST3
  PRODUCT_NAME        "Synchain Bridge"

  # "Fx" is added automatically by JUCE for VST3 audio effects.
  # Only specify sub-categories here to avoid duplicate "Fx" in moduleinfo.json.
  VST3_CATEGORIES     "Analyzer"

  # Bundle identifier
  BUNDLE_ID           "com.synchain.bridge"

  # Windows: link the WebView2 loader (macOS/Linux ignore this). See NuGet block above.
  NEEDS_WEBVIEW2      TRUE
)

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
  # Offline text-subset WOFF2 (Google Fonts, subset to used glyphs only ~60KB total)
  # Bridge Sans/Mono = renamed-family subsets (OFL-1.1 §3 RFN; upstream families in THIRD-PARTY-NOTICES.md)
  web/fonts/SpaceGrotesk.woff2
  web/fonts/BridgeSans.woff2
  web/fonts/BridgeMono.woff2
  web/fonts/NotoSansSC.woff2
)

# --- Dependencies (all static via x64-windows-static triplet) ---

# ixwebsocket (static, bundles mbedtls for TLS — no separate OpenSSL needed)
find_package(ixwebsocket CONFIG REQUIRED)
find_path(IXWEBSOCKET_INCLUDE_DIR ixwebsocket/IXWebSocketServer.h REQUIRED)

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
target_include_directories(SynchainBridgeVST PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/src
  ${IXWEBSOCKET_INCLUDE_DIR}
)

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
#   cmake -S . -B build -DBRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS="example-git-*-example-team.vercel.app;preview.example.com"
#
# ';' or ',' separated host patterns, at most ONE '*' wildcard segment per pattern
# (the wildcard must expand to a non-empty segment; https is still required). Empty by
# default -> the macro is NOT defined -> a default build allows no extra origin at all.
set(BRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS "" CACHE STRING
  "Extra Origin host patterns to allow (';' or ',' separated; at most one '*' per pattern)")
if(BRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS)
  # CMake lists are ';' separated and the ';' does not survive a command line / generator
  # round-trip inside a string define — normalise to ',' first, which is what the C++ side splits on.
  string(REPLACE ";" "," _bridge_extra_origin_hosts "${BRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS}")
  target_compile_definitions(SynchainBridgeVST PRIVATE
    BRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS="${_bridge_extra_origin_hosts}")
  # Deliberately not echoing the values: build logs of a public CI should not carry them.
  message(STATUS "Origin allow-list: extra host patterns injected at build time")
endif()

# --- Platform-Specific ---
if(WIN32)
  message(STATUS "Building Synchain VST3 for Windows (static, WebView2)")
elseif(APPLE)
  message(STATUS "Building Synchain VST3 for macOS (WKWebView)")
endif()
