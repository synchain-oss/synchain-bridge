// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "WebViewEditor.h"
#include "BinaryData.h" // 由 juce_add_binary_data(SynchainBridgeWebAssets) 生成

#include <cmath>
#include <functional>
#include <vector>

#if JUCE_WINDOWS
// WebView2 静态 loader（JUCE NEEDS_WEBVIEW2 + 静态链接）导出；ole32 提供 CoTaskMemFree。
// 直接前置声明，免引 <WebView2.h>/<windows.h>（避开 include 路径与宏污染）。
extern "C" {
long __stdcall GetAvailableCoreWebView2BrowserVersionString(const wchar_t* browserExecutableFolder,
                                                            wchar_t** versionInfo);
void __stdcall CoTaskMemFree(void* pv);
}
#endif

namespace synchain {

using WBC = juce::WebBrowserComponent;

namespace {

// 100% 设计基准尺寸：编辑器窗口 = DESIGN × uiScale；web 侧 zoom = innerWidth/kDesignW 精确铺满。
// 卡片按 space-between 铺满该盒；改这两个数即整体改窗口比例（web 常量需同步，见 index.html DESIGN_W/H）。
constexpr int kDesignW = 460;
constexpr int kDesignH = 560;

// -----------------------------------------------------------------------------
// FallbackPanel — WebView2 运行时缺失时的最小原生兜底面板。
// 仅提供 Start/Stop + 端口 + 状态，保证在锁定的 Windows 环境仍可控制桥 #2。
// -----------------------------------------------------------------------------
class FallbackPanel final : public juce::Component, private juce::Timer {
public:
  FallbackPanel(SynchainBridgeAudioProcessor& p, bool missingRuntime,
                std::function<void()> onInstall, std::function<void()> onRetry)
      : mProcessor(p),
        mMissingRuntime(missingRuntime),
        mOnInstall(std::move(onInstall)),
        mOnRetry(std::move(onRetry)) {
    mTitle.setText("Synchain Bridge", juce::dontSendNotification);
    mTitle.setJustificationType(juce::Justification::centred);
    mTitle.setFont(juce::Font(juce::FontOptions(20.0f, juce::Font::bold)));
    mTitle.setColour(juce::Label::textColourId, juce::Colours::white);
    addAndMakeVisible(mTitle);

    mMessage.setText(
      missingRuntime
        ? "Microsoft Edge WebView2 Runtime was not found, so the full UI cannot load.\n"
          "This plugin needs an internet connection to work anyway - install the runtime "
          "once, then reopen this plugin window."
        : "The WebView is taking too long to load (possibly a first-time cold start).\n"
          "Click Retry, or close and reopen this plugin window.",
      juce::dontSendNotification);
    mMessage.setJustificationType(juce::Justification::centredTop);
    mMessage.setColour(juce::Label::textColourId, juce::Colour(0xffb8b8c4));
    addAndMakeVisible(mMessage);

    if (mMissingRuntime) {
      mInstall.setButtonText("Download WebView2 Runtime");
      mInstall.onClick = [this] { if (mOnInstall) mOnInstall(); };
      addAndMakeVisible(mInstall);
    }
    mRetry.setButtonText("Retry");
    mRetry.onClick = [this] { if (mOnRetry) mOnRetry(); };
    addAndMakeVisible(mRetry);

    mPort.setText(juce::String(mProcessor.getPort()), juce::dontSendNotification);
    mPort.setInputRestrictions(5, "0123456789");
    mPort.setJustification(juce::Justification::centred);
    addAndMakeVisible(mPort);

    mToggle.onClick = [this] {
      auto& server = mProcessor.getBridgeServer();
      if (server.isRunning()) {
        server.stop();
      } else {
        const int port = mPort.getText().getIntValue();
        if (port >= plugin::MinPort && port <= plugin::MaxPort)
          mProcessor.setPort(port);
        server.start(mProcessor.getPort());
      }
      refresh();
    };
    addAndMakeVisible(mToggle);

    mStatus.setJustificationType(juce::Justification::centred);
    mStatus.setColour(juce::Label::textColourId, juce::Colour(0xffd0d0da));
    addAndMakeVisible(mStatus);

    refresh();
    startTimerHz(4);
  }

  ~FallbackPanel() override { stopTimer(); }

  void paint(juce::Graphics& g) override { g.fillAll(juce::Colour(0xff18161d)); }

  void resized() override {
    auto b = getLocalBounds().reduced(24);
    mTitle.setBounds(b.removeFromTop(34));
    mMessage.setBounds(b.removeFromTop(76));
    b.removeFromTop(10);
    if (mMissingRuntime) {
      mInstall.setBounds(b.removeFromTop(38).reduced(24, 0));
      b.removeFromTop(8);
    }
    mRetry.setBounds(b.removeFromTop(34).reduced(96, 0));
    b.removeFromTop(16);
    mPort.setBounds(b.removeFromTop(34).reduced(70, 0));
    b.removeFromTop(10);
    mToggle.setBounds(b.removeFromTop(40).reduced(50, 0));
    b.removeFromTop(12);
    mStatus.setBounds(b.removeFromTop(28));
  }

private:
  void timerCallback() override { refresh(); }

  void refresh() {
    auto& server = mProcessor.getBridgeServer();
    const bool running = server.isRunning();
    mToggle.setButtonText(running ? "Stop Bridge" : "Start Bridge");
    mStatus.setText(running
      ? "Running - port " + juce::String(server.getPort())
          + " - clients " + juce::String(mProcessor.clientCount())
      : "Idle",
      juce::dontSendNotification);
  }

  SynchainBridgeAudioProcessor& mProcessor;
  bool mMissingRuntime;
  std::function<void()> mOnInstall, mOnRetry;
  juce::Label mTitle, mMessage, mStatus;
  juce::TextEditor mPort;
  juce::TextButton mToggle, mInstall, mRetry;

  JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(FallbackPanel)
};

} // namespace

// =============================================================================
// SynchainBridgeWebEditor
// =============================================================================

SynchainBridgeWebEditor::SynchainBridgeWebEditor(SynchainBridgeAudioProcessor& p)
    : juce::AudioProcessorEditor(&p),
      mProcessor(p),
      mWebView(makeOptions()) {
  addAndMakeVisible(mWebView);

  setResizable(false, false); // 仅经缩放档位下拉（setUiScale）编程改尺寸，不开自由拖角
  {
    const float s = mProcessor.getUiScale();
    setSize(juce::roundToInt(kDesignW * s), juce::roundToInt(kDesignH * s));
  }

  // 先探测 WebView2 运行时：有则正常加载（看门狗容忍冷启动）；无则直接给可操作的兜底面板，
  // 并引导一次性安装，不做无意义等待。
  if (webView2RuntimeAvailable()) {
    // 必须在任何 emit 之前完成首个 goToURL（前端脚本随后加载并注册监听）。
    mWebView.goToURL(WBC::getResourceProviderRoot());
    mStartMs = juce::Time::getMillisecondCounter();
    startTimerHz(25);
  } else {
    mWebView.setVisible(false);
    showFallback(FallbackReason::MissingRuntime);
  }
}

SynchainBridgeWebEditor::~SynchainBridgeWebEditor() { stopTimer(); }

bool SynchainBridgeWebEditor::webView2RuntimeAvailable() {
#if JUCE_WINDOWS
  wchar_t* version = nullptr;
  const long hr = GetAvailableCoreWebView2BrowserVersionString(nullptr, &version);
  const bool ok = hr >= 0 && version != nullptr && version[0] != L'\0';
  if (version != nullptr)
    CoTaskMemFree(version);
  return ok;
#else
  return true; // macOS(WKWebView)/Linux(WebKitGTK)：系统 WebView 恒可用
#endif
}

void SynchainBridgeWebEditor::showFallback(FallbackReason reason) {
  if (mFallback != nullptr)
    return;
  mWebView.setVisible(false);
  const bool missing = (reason == FallbackReason::MissingRuntime);
  mFallback = std::make_unique<FallbackPanel>(
      mProcessor, missing,
      [] {
        juce::URL("https://go.microsoft.com/fwlink/p/?LinkId=2124703").launchInDefaultBrowser();
      },
      [this] { retryWebView(); });
  addAndMakeVisible(*mFallback);
  // 兜底面板是固定像素布局（~388px 高），不随 uiScale 缩放。小缩放档位（如 33%）下窗口会过小、
  // 挤压/裁掉 Start/Stop/端口/状态等最小控制面，故切兜底时把窗口放大到至少基准设计尺寸以保证可用
  // （更大的缩放窗口保持不变）。retryWebView 成功回到 WebView 时再按 uiScale 恢复。
  if (getWidth() < kDesignW || getHeight() < kDesignH)
    setSize(juce::jmax(getWidth(), kDesignW), juce::jmax(getHeight(), kDesignH));
  resized();
}

void SynchainBridgeWebEditor::retryWebView() {
  mFallback.reset();
  if (! webView2RuntimeAvailable()) {
    mWebView.setVisible(false);
    showFallback(FallbackReason::MissingRuntime);
    return;
  }
  mBridgeReady = false;
  // 回到 WebView：恢复按 uiScale 的窗口尺寸（切兜底时可能已把窗口放大到基准尺寸）。
  {
    const float s = mProcessor.getUiScale();
    setSize(juce::roundToInt(kDesignW * s), juce::roundToInt(kDesignH * s));
  }
  mWebView.setVisible(true);
  mWebView.goToURL(WBC::getResourceProviderRoot());
  mStartMs = juce::Time::getMillisecondCounter();
  if (! isTimerRunning())
    startTimerHz(25);
  resized();
}

void SynchainBridgeWebEditor::resized() {
  mWebView.setBounds(getLocalBounds());
  if (mFallback != nullptr)
    mFallback->setBounds(getLocalBounds());
}

// -----------------------------------------------------------------------------
// WebView 装配
// -----------------------------------------------------------------------------
juce::WebBrowserComponent::Options SynchainBridgeWebEditor::makeOptions() {
  WBC::Options options;

#if JUCE_WINDOWS
  // Windows：给 WebView2 一个可写的 user-data 目录，避免 DAW 安装目录只读导致初始化失败。
  WBC::Options::WinWebView2 wv2;
  wv2 = wv2.withUserDataFolder(
    juce::File::getSpecialLocation(juce::File::tempDirectory)
      .getChildFile("SynchainBridgeWV2"));

  // 关键：Windows 上必须显式选 WebView2 后端。否则 getBackend()==defaultBackend，
  // JUCE 回退到旧 IE ActiveX 控件（Win32WebView），它不支持 resource provider /
  // native 集成，会把 https://juce.backend/ 当真实网址导航 → "无法打开此页"。
  // 编译宏 JUCE_USE_WIN_WEBVIEW2 / NEEDS_WEBVIEW2 只让 WebView2 代码路径存在 + 链接
  // loader，并不切换后端。参见 JUCE examples/Plugins/WebViewPluginDemo.h。
  // 仅在 Windows 上设 webview2 后端 / WinWebView2 选项：非 Windows（Mac WKWebView /
  // Linux WebKitGTK）走系统默认后端，强设 webview2 会让 WebBrowserComponent 无法初始化。
  options = options
    .withBackend(WBC::Options::Backend::webview2)
    .withWinWebView2Options(wv2);
#endif

  return options
    .withNativeIntegrationEnabled()
    .withResourceProvider(
      [this](const juce::String& url) { return provideResource(url); },
      juce::URL(WBC::getResourceProviderRoot()).getOrigin())
    // 首帧同步 seed（window.__JUCE__.initialisationData 可直接读）
    .withInitialisationData(bridge::Init::Version, juce::var(juce::String(JucePlugin_VersionString)))
    .withInitialisationData(bridge::Init::Port, juce::var(mProcessor.getPort()))
    .withInitialisationData(bridge::Init::Volume, juce::var(mProcessor.getVolumePct()))
    .withInitialisationData(bridge::Init::Lang, juce::var(mProcessor.getLang()))
    // JS -> C++
    .withNativeFunction(juce::Identifier(bridge::Fn::RequestInitialState),
      [this](const juce::Array<juce::var>& a, WBC::NativeFunctionCompletion c) {
        handleRequestInitialState(a, std::move(c));
      })
    .withNativeFunction(juce::Identifier(bridge::Fn::ToggleRun),
      [this](const juce::Array<juce::var>& a, WBC::NativeFunctionCompletion c) {
        handleToggleRun(a, std::move(c));
      })
    .withNativeFunction(juce::Identifier(bridge::Fn::SetPort),
      [this](const juce::Array<juce::var>& a, WBC::NativeFunctionCompletion c) {
        handleSetPort(a, std::move(c));
      })
    .withNativeFunction(juce::Identifier(bridge::Fn::SetMasterGain),
      [this](const juce::Array<juce::var>& a, WBC::NativeFunctionCompletion c) {
        handleSetMasterGain(a, std::move(c));
      })
    .withNativeFunction(juce::Identifier(bridge::Fn::SetLang),
      [this](const juce::Array<juce::var>& a, WBC::NativeFunctionCompletion c) {
        handleSetLang(a, std::move(c));
      })
    .withNativeFunction(juce::Identifier(bridge::Fn::SetUiScale),
      [this](const juce::Array<juce::var>& a, WBC::NativeFunctionCompletion c) {
        handleSetUiScale(a, std::move(c));
      })
    .withNativeFunction(juce::Identifier(bridge::Fn::CommitUiScale),
      [this](const juce::Array<juce::var>& a, WBC::NativeFunctionCompletion c) {
        handleCommitUiScale(a, std::move(c));
      });
}

std::optional<juce::WebBrowserComponent::Resource>
SynchainBridgeWebEditor::provideResource(const juce::String& url) const {
  // url 形如 "/" 或 "/index.html" 或 "/js/juce/index.js"（root-relative 路径）
  const auto path = (url == "/" || url.isEmpty())
    ? juce::String("index.html")
    : url.fromFirstOccurrenceOf("/", false, false);
  const auto baseName = path.fromLastOccurrenceOf("/", false, false);

  // 用 BinaryData 的原始文件名匹配（避免手工复刻 JUCE 的符号名 mangling）
  for (int i = 0; i < BinaryData::namedResourceListSize; ++i) {
    if (juce::String(BinaryData::originalFilenames[i]) == baseName) {
      int size = 0;
      if (const char* data = BinaryData::getNamedResource(BinaryData::namedResourceList[i], size)) {
        std::vector<std::byte> bytes(
          reinterpret_cast<const std::byte*>(data),
          reinterpret_cast<const std::byte*>(data) + size);
        const auto ext = baseName.fromLastOccurrenceOf(".", false, false);
        return WBC::Resource{std::move(bytes), juce::String(mimeForExtension(ext))};
      }
    }
  }
  return std::nullopt;
}

const char* SynchainBridgeWebEditor::mimeForExtension(const juce::String& ext) {
  const auto e = ext.toLowerCase();
  if (e == "html" || e == "htm") return "text/html";
  if (e == "css") return "text/css";
  if (e == "js" || e == "mjs") return "text/javascript"; // ES module 必须是 JS MIME
  if (e == "json") return "application/json";
  if (e == "svg") return "image/svg+xml";
  if (e == "woff2") return "font/woff2";
  if (e == "woff") return "font/woff";
  if (e == "ttf") return "font/ttf";
  if (e == "png") return "image/png";
  return "application/octet-stream";
}

// -----------------------------------------------------------------------------
// 原生函数处理（message 线程）
// -----------------------------------------------------------------------------
void SynchainBridgeWebEditor::handleRequestInitialState(
    const juce::Array<juce::var>&, WBC::NativeFunctionCompletion complete) {
  mBridgeReady = true; // 前端确认就绪 -> 此后 timer 才允许 emit
  complete(buildSnapshot());
}

void SynchainBridgeWebEditor::handleToggleRun(
    const juce::Array<juce::var>& args, WBC::NativeFunctionCompletion complete) {
  const bool shouldRun = args.size() > 0 && static_cast<bool>(args[0]);
  auto& server = mProcessor.getBridgeServer();
  auto* obj = new juce::DynamicObject();

  if (shouldRun) {
    const int bound = server.start(mProcessor.getPort()); // 尝试 port..port+9
    if (bound < 0) {
      obj->setProperty("running", false);
      obj->setProperty("port", mProcessor.getPort());
      obj->setProperty("error", "PORT_IN_USE");
    } else {
      obj->setProperty("running", true);
      obj->setProperty("port", bound);
    }
  } else {
    server.stop();
    obj->setProperty("running", false);
    obj->setProperty("port", mProcessor.getPort());
  }
  complete(juce::var(obj));
}

void SynchainBridgeWebEditor::handleSetPort(
    const juce::Array<juce::var>& args, WBC::NativeFunctionCompletion complete) {
  const int port = args.size() > 0 ? static_cast<int>(args[0]) : plugin::DefaultPort;
  const bool ok = port >= plugin::MinPort && port <= plugin::MaxPort;
  if (ok)
    mProcessor.setPort(port);

  auto* obj = new juce::DynamicObject();
  obj->setProperty("ok", ok);
  obj->setProperty("port", mProcessor.getPort());
  complete(juce::var(obj));
}

void SynchainBridgeWebEditor::handleSetMasterGain(
    const juce::Array<juce::var>& args, WBC::NativeFunctionCompletion complete) {
  const int pct = args.size() > 0 ? juce::jlimit(0, 200, static_cast<int>(args[0])) : 100;
  mProcessor.setVolumePct(pct);

  auto* obj = new juce::DynamicObject();
  obj->setProperty("ok", true);
  complete(juce::var(obj));
}

void SynchainBridgeWebEditor::handleSetLang(
    const juce::Array<juce::var>& args, WBC::NativeFunctionCompletion complete) {
  const juce::String code = args.size() > 0 ? args[0].toString() : juce::String("zh");
  mProcessor.setLang(code);

  auto* obj = new juce::DynamicObject();
  obj->setProperty("ok", true);
  complete(juce::var(obj));
}

void SynchainBridgeWebEditor::handleSetUiScale(
    const juce::Array<juce::var>& args, WBC::NativeFunctionCompletion complete) {
  const double f = args.size() > 0 ? static_cast<double>(args[0]) : 1.0;
  mProcessor.setUiScale(static_cast<float>(f)); // clamp 到 [MinUiScale, MaxUiScale]
  const float s = mProcessor.getUiScale();
  // 仅缩放编辑器窗口为 DESIGN×s（实时预览）；web 侧卡片用 (100/s)%+zoom:s 相对窗口自适应铺满（DPI 无关）。
  // 注意：这里**不**写全局默认——防呆确认「保持」时才经 commitUiScale 落盘，避免未确认的极端档位
  // 在用户 10s 内关窗（revert 定时器随 WebView 销毁而失效）时污染全局、导致新实例仍开大（v1.2.5 修）。
  setSize(juce::roundToInt(kDesignW * s), juce::roundToInt(kDesignH * s));

  auto* obj = new juce::DynamicObject();
  obj->setProperty("ok", true);
  obj->setProperty("scale", s);
  obj->setProperty("w", getWidth());
  obj->setProperty("h", getHeight());
  complete(juce::var(obj));
}

void SynchainBridgeWebEditor::handleCommitUiScale(
    const juce::Array<juce::var>& args, WBC::NativeFunctionCompletion complete) {
  juce::ignoreUnused(args);
  // 防呆确认「保持」后调用：把当前（已确认）uiScale 写入全局默认，新实例/新工程沿用。
  mProcessor.persistUiScaleAsDefault();
  auto* obj = new juce::DynamicObject();
  obj->setProperty("ok", true);
  obj->setProperty("scale", mProcessor.getUiScale());
  complete(juce::var(obj));
}

juce::var SynchainBridgeWebEditor::buildSnapshot() const {
  auto& server = mProcessor.getBridgeServer();
  const bool running = server.isRunning();

  auto* obj = new juce::DynamicObject();
  obj->setProperty("running", running);
  obj->setProperty("clients", mProcessor.clientCount());
  obj->setProperty("port", running && server.getPort() > 0 ? server.getPort()
                                                            : mProcessor.getPort());
  obj->setProperty("volume", mProcessor.getVolumePct());
  obj->setProperty("lang", mProcessor.getLang());
  obj->setProperty("uiScale", mProcessor.getUiScale());
  obj->setProperty("version", juce::String(JucePlugin_VersionString));
  obj->setProperty("sampleRate", mProcessor.currentSampleRate());
  obj->setProperty("channels", mProcessor.currentChannels());
  obj->setProperty("latencyMs", mProcessor.latencyMs());
  return juce::var(obj);
}

// -----------------------------------------------------------------------------
// 25Hz Timer（message 线程）：读 processor 原子量 -> 变化时 emit
// -----------------------------------------------------------------------------
void SynchainBridgeWebEditor::timerCallback() {
  // WebView2 看门狗：5s。后端选对（withBackend webview2）后前端确实走 WebView2 加载，
  // 正常冷启动远快于此；超时即判定加载失败，切兜底面板（可重试 / 重开窗口），文案不误报"运行时缺失"。
  if (!mBridgeReady && mFallback == nullptr
      && juce::Time::getMillisecondCounter() - mStartMs > 5000) {
    showFallback(FallbackReason::LoadTimeout);
    return;
  }
  if (!mBridgeReady)
    return;

  // --- 应用 web 下发的主控音量（v1.2.10 修 web→VST 不生效）---
  // onVolumeChange 在 WS 线程只存原子；此处是 message 线程，可安全 setVolumePct（setValueNotifyingHost
  // 须在 message 线程）。取代不可靠的 callAsync。应用后下方 volume 广播块会把新值回传网页（echo）。
  if (const int webVol = mProcessor.consumePendingWebVolume(); webVol >= 0)
    mProcessor.setVolumePct(webVol);

  auto& server = mProcessor.getBridgeServer();
  const bool running = server.isRunning();

  // --- meter（运行中 + 变化超阈值才发）---
  const float ldb = mProcessor.meterLdb();
  const float rdb = mProcessor.meterRdb();
  const float peak = mProcessor.meterPeak();
  if (running
      && (std::abs(ldb - mLastLdb) > 0.3f || std::abs(rdb - mLastRdb) > 0.3f)) {
    auto* m = new juce::DynamicObject();
    m->setProperty("l", juce::Decibels::decibelsToGain(ldb));
    m->setProperty("r", juce::Decibels::decibelsToGain(rdb));
    m->setProperty("ldb", ldb);
    m->setProperty("rdb", rdb);
    m->setProperty("peak", peak);
    mWebView.emitEventIfBrowserIsVisible(juce::Identifier(bridge::Event::Meter),
                                         juce::var(m));
    mLastLdb = ldb;
    mLastRdb = rdb;
  }

  // --- state（变化时发）---
  const int clients = mProcessor.clientCount();
  if (running != mLastRunning || clients != mLastClients) {
    auto* s = new juce::DynamicObject();
    s->setProperty("running", running);
    s->setProperty("clients", clients);
    s->setProperty("port", running && server.getPort() > 0 ? server.getPort()
                                                           : mProcessor.getPort());
    mWebView.emitEventIfBrowserIsVisible(juce::Identifier(bridge::Event::State),
                                         juce::var(s));
    mLastRunning = running;
    mLastClients = clients;
  }

  // --- audio info（变化时发）---
  const int sampleRate = mProcessor.currentSampleRate();
  const int channels = mProcessor.currentChannels();
  if (sampleRate != mLastSampleRate || channels != mLastChannels) {
    auto* a = new juce::DynamicObject();
    a->setProperty("sampleRate", sampleRate);
    a->setProperty("channels", channels);
    a->setProperty("latencyMs", mProcessor.latencyMs());
    mWebView.emitEventIfBrowserIsVisible(juce::Identifier(bridge::Event::Audio),
                                         juce::var(a));
    mLastSampleRate = sampleRate;
    mLastChannels = channels;
  }

  // --- volume（主控音量变化时广播给浏览器 WS 客户端 → VST↔网页音量条实时双向同步；桥 #2）---
  // 插件 UI（或宿主）改主控音量 → 这里广播 {type:"volume"}；网页仅更新音量条显示、不回送，避免回环。
  const int volume = mProcessor.getVolumePct();
  if (volume != mLastVolume) {
    if (running && clients > 0) server.sendVolume(volume);
    mLastVolume = volume;
  }
}

} // namespace synchain
