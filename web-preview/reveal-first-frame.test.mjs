// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

// =============================================================================
// [SL-386] 开窗遮挡闸的跨语言同源判据(node:test + node:assert,零依赖,不需要 npm install)
// =============================================================================
// 钉三类「删一处就红」的事实:
//   ① 占位底三处同源:web/styles.css 的 --vb-card-surface(css token,卡片消费它)
//      == web/index.html <head> 内联 html 底(外链 css 未到时的第一层底)
//      == src/WebViewRevealGate.h kPlaceholderStops/kPlaceholderGradientDeg(C++ 占位色标)。
//      角度 + 全部色标(位置与色值)三处逐项相等;改任一处即红。
//   ② 首帧信号名两处同源:src/BridgeApi.h timing::FirstFrameSignal ==
//      web/index.html <head> 内联脚本的 eventId;并钉脚本的时序结构
//      (DOMContentLoaded 武装 + 嵌套两层 rAF + __JUCE__ 在场守卫)。
//   ③ 接线删除式源钉(src/WebViewEditor.cpp):webView 的 setVisible(false) 只允许出现在
//      showFallback(兜底面板路径,SL-386 保留);遮挡闸放行链的调用点必须在场。
//      纯文本断言钉不住运行期行为(那半边由 tests/reveal_gate_selftest.cpp 与真机
//      pluginval 数表兜),这里钉的是「同源与接线」这一层。
//
// 运行:node --test web-preview/reveal-first-frame.test.mjs(仓库根)
//      或 cd web-preview && npm test(node --test 会拾取本目录 *.test.mjs)。
// =============================================================================

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const read = (rel) => readFileSync(root + rel, "utf8");

/** 解析 `linear-gradient(<N>deg, #hex P%, ...)` → { deg, stops: [{hex, pos}] }(对空白稳健)。 */
function parseGradient(css) {
  const m = css.match(/linear-gradient\(\s*([\d.]+)deg\s*,([^)]*)\)/);
  assert.ok(m, "应能解析出 linear-gradient(...deg, ...):" + css.slice(0, 120));
  const stops = [...m[2].matchAll(/#([0-9a-fA-F]{6})\s+([\d.]+)%/g)].map(
    (s) => ({
      hex: s[1].toLowerCase(),
      pos: Number(s[2]) / 100,
    }),
  );
  assert.ok(stops.length > 0, "应能解析出至少一个色标");
  return { deg: Number(m[1]), stops };
}

/** 从源码常量区解析 C++ 侧 kPlaceholderGradientDeg 与 kPlaceholderStops。 */
function parseCppPlaceholder(src) {
  const deg = src.match(/kPlaceholderGradientDeg\s*=\s*([\d.]+)/);
  assert.ok(deg, "WebViewRevealGate.h 应有 kPlaceholderGradientDeg");
  const stops = [
    ...src.matchAll(/\{\s*([\d.]+),\s*0x([0-9a-fA-F]{8})u?\s*\}/g),
  ].map((s) => ({
    pos: Number(s[1]),
    hex: s[2].slice(2).toLowerCase(), // 0xAARRGGBB → 取 RRGGBB,与 CSS #RRGGBB 同域
  }));
  assert.ok(stops.length > 0, "应能解析出 kPlaceholderStops 色标");
  return { deg: Number(deg[1]), stops };
}

function assertSameGradient(a, b, label) {
  assert.equal(a.deg, b.deg, `${label}: 渐变角度不一致`);
  assert.equal(a.stops.length, b.stops.length, `${label}: 色标个数不一致`);
  a.stops.forEach((s, i) => {
    assert.equal(s.hex, b.stops[i].hex, `${label}: 第 ${i} 个色标色值不一致`);
    assert.ok(
      Math.abs(s.pos - b.stops[i].pos) < 1e-9,
      `${label}: 第 ${i} 个色标位置不一致(${s.pos} vs ${b.stops[i].pos})`,
    );
  });
}

test("① 占位底三处同源:css token == 内联 html 底 == C++ 色标", () => {
  const css = read("web/styles.css");
  const token = css.match(/--vb-card-surface:\s*([^;]+);/);
  assert.ok(
    token,
    "styles.css 应定义 --vb-card-surface(成品可见底的 css 真源)",
  );
  const fromToken = parseGradient(token[1]);

  const html = read("web/index.html");
  // <head> 内联的 html 底:第一个 <style> 块(必须排在 <link rel="stylesheet"> 之前)。
  const inlineStyle = html.match(/<style>([\s\S]*?)<\/style>/);
  assert.ok(inlineStyle, "index.html <head> 应有内联 html 底 <style> 块");
  const htmlBg = inlineStyle[1].match(/html\s*\{[^}]*background:\s*([^;}]+)/);
  assert.ok(htmlBg, "内联 <style> 应给 html 铺 background(取代浏览器默认白)");
  const fromInline = parseGradient(htmlBg[1]);

  const linkAt = html.indexOf('<link rel="stylesheet" href="./styles.css"');
  const styleAt = html.indexOf("<style>");
  assert.ok(
    styleAt >= 0 && linkAt > styleAt,
    "内联 html 底必须排在外链 styles.css 之前",
  );

  assert.ok(
    /background:\s*var\(--vb-card-surface\)/.test(html),
    "成品卡片 [data-card] 应消费 --vb-card-surface(token = 成品可见底真源)",
  );

  const fromCpp = parseCppPlaceholder(read("src/WebViewRevealGate.h"));

  assertSameGradient(fromToken, fromInline, "css token ↔ 内联 html 底");
  assertSameGradient(fromToken, fromCpp, "css token ↔ C++ 色标");
});

test("② 首帧信号名同源 + 内联脚本时序结构(DOMContentLoaded + 两层 rAF + __JUCE__ 守卫)", () => {
  const api = read("src/BridgeApi.h");
  const fnName = api.match(/FirstFrameSignal\s*=\s*"([^"]+)"/);
  assert.ok(fnName, "BridgeApi.h 应有 timing::FirstFrameSignal(唯一真源)");
  const eventId = fnName[1];

  const html = read("web/index.html");
  assert.ok(
    html.includes(`eventId: "${eventId}"`),
    "内联脚本应逐字引用 BridgeApi.h 的信号名",
  );

  // 抽出内联信号脚本(<head> 里引用 eventId 的那个 <script> 块)。
  const script = html.match(/<script>([\s\S]*?eventId:[\s\S]*?)<\/script>/);
  assert.ok(script, "index.html <head> 应有首帧信号内联脚本");
  const body = script[1];

  assert.ok(
    /document\.addEventListener\(\s*"DOMContentLoaded",\s*arm\s*\)/.test(
      body,
    ) ||
      /document\.addEventListener\(\s*'DOMContentLoaded',\s*arm\s*\)/.test(
        body,
      ),
    "信号必须等 DOMContentLoaded 才武装(此前页面还没构建)",
  );
  // 嵌套两层 rAF:单层 rAF 的回调跑在这一帧提交之前,发信号会早于首帧 —— 那正是要治的病。
  assert.match(
    body,
    /requestAnimationFrame\(\s*function\s*\(\s*\)\s*\{\s*window\.requestAnimationFrame\(\s*signal\s*\)/,
    "信号必须嵌套两层 requestAnimationFrame(前一帧确已合成)",
  );
  assert.match(
    body,
    /window\.__JUCE__/,
    "脚本必须有 __JUCE__ 在场守卫(浏览器预览下静默返回)",
  );
  assert.match(
    body,
    /try\s*\{/,
    "postMessage 必须 try 包裹(发不出去也不许卡住,还有 3s 兜底)",
  );
});

test("③ 接线源钉:webView 的 setVisible(false) 只许在 showFallback(兜底路径)", () => {
  const src = read("src/WebViewEditor.cpp");

  // 先剥注释再分析:注释里可能提到 setVisible(false) 等字面量,不应参与源钉。
  const code = src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");

  // 按成员函数定义切分,找出每个 setVisible(false) 的宿主函数。
  const fnRe = /void\s+SynchainBridgeWebEditor::(\w+)\s*\(/g;
  const marks = [];
  let m;
  while ((m = fnRe.exec(code)) !== null)
    marks.push({ name: m[1], at: m.index });

  const hideRe = /setVisible\(\s*false\s*\)/g;
  const owners = [];
  while ((m = hideRe.exec(code)) !== null) {
    let owner = "(ctor/其他)";
    for (const mark of marks) if (mark.at < m.index) owner = mark.name;
    owners.push(owner);
  }
  assert.ok(
    owners.length >= 1,
    "showFallback 应保留 setVisible(false)(兜底面板逻辑不变)",
  );
  for (const o of owners)
    assert.equal(
      o,
      "showFallback",
      `setVisible(false) 只允许出现在 showFallback,发现在 ${o} —— 遮挡闸不许隐藏 WebView` +
        `(keepPageLoadedWhenBrowserIsHidden 默认 false,隐藏会把页面顶成 about:blank)`,
    );

  // 放行链调用点在场(删接线即红;行为那半边由 reveal_gate_selftest + pluginval 数表兜)。
  assert.match(
    src,
    /mRevealGate\.onNavigationStarted\(/,
    "导航开始要通知闸门(挪窗的唯一触发点)",
  );
  assert.match(
    src,
    /mRevealGate\.onFirstFrame\(/,
    "首帧信号要通知闸门(唯一的正常放行路)",
  );
  assert.match(
    src,
    /mRevealGate\.onNavigationFinished\(\)/,
    "navFinished 要记账(只记账,不放行)",
  );
  assert.match(
    src,
    /mRevealGate\.onTick\(/,
    "25Hz tick 要喂闸门(settle 与 3s 兜底都在这里结算)",
  );
  assert.match(
    src,
    /mRevealGate\.onFallbackShown\(\)/,
    "切兜底面板要通知闸门放手",
  );
  assert.match(
    src,
    /parkedBounds\(/,
    "遮挡期要把 WebView 挪出可视区(parkedBounds)",
  );
  assert.match(
    src,
    /static_assert\([\s\S]*?BridgeWebView::paint/,
    "删除式判据:paint 覆写的编译期 static_assert 必须在场(fallbackPaint 白底回归即编译红)",
  );
  assert.match(
    src,
    /timing::FirstFrameSignal/,
    "事件监听应按 BridgeApi.h timing::FirstFrameSignal 注册(不占 Fn:: 契约名表)",
  );
});
