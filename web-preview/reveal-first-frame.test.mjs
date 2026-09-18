// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

// =============================================================================
// [SL-386] 开窗遮挡闸的跨语言同源判据(node:test + node:assert,零依赖,不需要 npm install)
// =============================================================================
// 钉五格「删一处就红」的事实(①②③ 来自 SL-386 各推,④ 来自 SL-386 第 2/3 推,
// ⑤ 来自 [SL-421],② 于 [SL-433] 大改;格数与下面的 test() 一一对应,改动时两边一起改):
//   ① 占位底三处同源:web/styles.css 的 --vb-card-surface(css token,卡片消费它)
//      == web/index.html <head> 内联 html 底(外链 css 未到时的第一层底)
//      == src/WebViewRevealGate.h kPlaceholderStops/kPlaceholderGradientDeg(C++ 占位色标)。
//      角度 + 全部色标(位置与色值)三处逐项相等;改任一处即红。
//   ② 首帧信号名两处同源:src/BridgeApi.h timing::FirstFrameSignal ==
//      web/index.html <head> 内联脚本的 eventId;并钉脚本的时序结构。
//      [SL-433] 时序结构已从「DOMContentLoaded 武装」改判为「**paint 记录到达**才武装」
//      (DCL 不保证页面画过任何一帧,详见 src/WebViewRevealGate.h),本格随之升级为六条:
//      (a) 事件名逐字同源;(b) 嵌套两层 rAF;(c) 武装**确实由 paint 记录接线过来**
//      (断生效不断在场:PerformanceObserver 在场 + buffered 落在 .observe 实参对象里 +
//      回调体里真的调 armOnce + DOMContentLoaded 全块恰好一次且在 catch 里);
//      (d) 回落路与保险定时器在场,且保险**排在 try 之前**、回调**直接发信号不绕 rAF**、
//      撤网落在 signal() 里、**且撤网与去重都排在 postMessage 之后**(第 1 轮复审:只断
//      「落在 signal() 里」时,排在 __JUCE__ 守卫之前的写法照样全绿,而那条路上信号一个字节
//      都没发出去、网却已经撤了);(e) 载荷诊断字段 timing::FirstFramePaintDeltaKey 逐字同源且
//      算式接上;(f) **C++ 那一侧**真的经该常量读了它并拼进诊断行(跨边界字面量双向对拍 ——
//      任一侧漂了都只会打 `(no paint record)`,而那与合法回落路在日志里逐字同形)。
//      外加原有的 __JUCE__ 在场守卫与 try 包裹两条。
//   ③ 接线删除式源钉(src/WebViewEditor.cpp):webView 的 setVisible(false) 只允许出现在
//      showFallback(兜底面板路径,SL-386 保留);遮挡闸放行链的调用点必须在场。
//   ④ 插件路径关掉卡片入场动画(layoutForMode 的 isPlugin 段 animation:"none"),
//      且它早于首帧信号生效。
//   ⑤ [SL-421] WebView2 的 DefaultBackgroundColor 那一层接上了(makeOptions 的
//      withBackgroundColour),取值经 placeholderMidArgb() 从 kPlaceholderStops 现算、
//      不另写色值字面量,且「这一层在不在」的诊断行打在 goToURL 之前。
//      ⚠ 这一层缺席是**静默**的:编译过、其余判据全绿,屏上却是白 —— 本格是它唯一的机检。
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

/**
 * [SL-421 第 2 推 · 裁定 7;SL-433 抽成公共件] 从 `at` 起,取其后第一个 `{` 到配平 `}` 的
 * **整块**(含首尾大括号)。
 *
 * 取代此前的「起点 + 魔法偏移」(`mkAt + 2600` / `blAt + 1600`):那种窗口一旦被注释写长
 * 或函数挪动就会滑出目标 ⇒ **假红**。大括号配对切出的正好是目标块,长度自适应、
 * 不依赖任何常数。
 *
 * ⚠ 只能喂**已剥掉字符串与注释**的源码(调用方负责):否则字符串/注释里的大括号会把配对带偏。
 * ⚠ **fail-closed 是本函数的硬性质**(裁定 7 明确要求保住):`{` 找不到、大括号到文件尾都
 *   没配平 —— 一律 assert 红,绝不 `return ""` 或跳过。调用方那一半(锚点找不到也要红)
 *   由 functionBodyAt / jsBodyAt 负责。
 *   「找不到就跳过」会让删掉被守对象的那一刻静默变绿,正是本格要防的事。
 */
function braceBodyFrom(code, at, label) {
  const open = code.indexOf("{", at);
  assert.ok(open >= 0, `${label} 之后应有 '{'`);
  let depth = 0;
  for (let i = open; i < code.length; i++) {
    if (code[i] === "{") depth++;
    else if (code[i] === "}") {
      depth--;
      if (depth === 0) return code.slice(open, i + 1);
    }
  }
  assert.fail(`${label} 的大括号到文件尾都没配平(源钉不许在这里静默放过)`);
}

/**
 * [SL-433 第 1 轮复审 · A3] 剥掉 C++ 注释,**保留字符串字面量**。
 *
 * ③ ⑤ 那一套是「先把字符串整体占位成 `""`、再剥注释」——它要的是代码骨架,而占位之后
 * **任何字面量断言都会永远绿**,所以「不许另写这个字段名的字面量」那条不能用它。
 * 反过来,直接对原文跑「行注释正则」又会吃掉字符串里的 `//`(如 `"https://..."`),
 * 把那一行从截点起整段删掉 —— 方向是 **fail-open**(真有字面量藏在同一行后半段就扫不到)。
 * (这里不写出那条正则的字面形态:它含有 `*` 加 `/` 的相邻组合,写进块注释会把注释提前收尾 ——
 *  本卡实测踩过一次。)
 *
 * 所以这里按字符走一遍,只在**字符串外**认注释:两个坑各避各的,不靠正则碰运气。
 * 已知边界(写明):不处理原始字符串字面量 `R"(...)"`;本仓 C++ 里没有,真出现时它的内容
 * 会被当普通代码扫,方向是**更严**(判负),不是更松。
 */
function stripCppCommentsKeepStrings(src) {
  let out = "";
  let i = 0;
  while (i < src.length) {
    const c = src[i];
    const d = src[i + 1];
    if (c === '"' || c === "'") {
      const quote = c;
      out += c;
      i++;
      while (i < src.length) {
        out += src[i];
        if (src[i] === "\\") {
          // 转义对:整对照抄,免得 \" 被当成收尾引号。
          if (i + 1 < src.length) out += src[i + 1];
          i += 2;
          continue;
        }
        if (src[i] === quote) {
          i++;
          break;
        }
        i++;
      }
      continue;
    }
    if (c === "/" && d === "/") {
      while (i < src.length && src[i] !== "\n") i++;
      continue;
    }
    if (c === "/" && d === "*") {
      i += 2;
      while (i < src.length && !(src[i] === "*" && src[i + 1] === "/")) i++;
      i += 2;
      continue;
    }
    out += c;
    i++;
  }
  return out;
}

function functionBodyAt(code, headRe, label) {
  const at = code.search(headRe);
  assert.ok(
    at >= 0,
    `src/WebViewEditor.cpp 应有 ${label} 定义(源钉找不到函数头即判红)`,
  );
  return braceBodyFrom(code, at, `${label} 的函数头`);
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

/**
 * [SL-433] 在**剥完 JS 注释**的信号脚本块里,按 `re` 找到一处、切出其后第一个大括号配对块。
 * fail-closed 同 functionBodyAt:锚点找不到即 assert 红,绝不 `return ""`。
 *
 * ⚠ 已知边界(第 1 轮复审 B5,写明、**不再加正则去兜**):调用方把锚点写成 `function` 形态时,
 *   改成箭头函数(`setTimeout(() => {...})`)会落进本函数的 fail-closed ⇒ **判负**。
 *   这是**有意的方向**:配对一旦滑到无关的块上,红就会落在别的断言上(本卡实测过一次,
 *   见 D6/D6b)。要换写法就连同锚点一起改。
 */
function jsBodyAt(code, re, label) {
  const at = code.search(re);
  assert.ok(
    at >= 0,
    `web/index.html 的首帧信号脚本里应有 ${label}(源钉找不到即判红)`,
  );
  return braceBodyFrom(code, at, label);
}

test("② 信号名/载荷字段名两处同源 + 内联脚本由 paint 记录触发(两层 rAF + 回落 + 保险)+ C++ 侧真的读了那个字段", () => {
  const api = read("src/BridgeApi.h");
  const fnName = api.match(/FirstFrameSignal\s*=\s*"([^"]+)"/);
  assert.ok(fnName, "BridgeApi.h 应有 timing::FirstFrameSignal(唯一真源)");
  const eventId = fnName[1];
  // [SL-433] 载荷里那个诊断字段名的真源同样在 BridgeApi.h,取法与事件名**逐字同源**。
  const keyName = api.match(/FirstFramePaintDeltaKey\s*=\s*"([^"]+)"/);
  assert.ok(
    keyName,
    "BridgeApi.h 应有 timing::FirstFramePaintDeltaKey([SL-433] 载荷诊断字段名的唯一真源)",
  );
  const paintDeltaKey = keyName[1];

  const html = read("web/index.html");

  // 抽出内联信号脚本(<head> 里引用 eventId 的那个 <script> 块)。
  const script = html.match(/<script>([\s\S]*?eventId:[\s\S]*?)<\/script>/);
  assert.ok(script, "index.html <head> 应有首帧信号内联脚本");
  // ⚠ [SL-433] **必须先剥掉块里的 JS 注释**:下面几条断言的关键词(PerformanceObserver /
  // buffered / DOMContentLoaded / setTimeout / signal)在这段脚本的说明注释里逐字出现过,
  // 不剥的话**注释自己就替实现发了合格证** —— SCVB 同族卡实测过:删掉 `buffered: true` 这个
  // 实参,判据照样全绿。行尾 `//` 也要剥(把关键词挪进行尾注释是同一个洞的另一侧)。
  // ⚠ 已知边界两条(写明,**不再加正则去兜** —— 判例 SL-431):
  //   · 字符串字面量里的裸 `//`(如 `"a//b"`)会被误剥。本块里没有这种写法;真要有,后果是
  //     **判据更严**(实现文本被剥掉 ⇒ 判负),方向是 fail-closed;
  //   · 行尾那条用「`//` 前必须有一个字符且不是 `:`」避开 `https://`,代价是 `x: //注释`
  //     这种形态剥不掉(第 1 轮复审 B5)。方向是 fail-open,但本块里没有这种写法,而且
  //     下面 (c) 的 buffered 断言另外还要求它落在 `.observe({...})` 的**实参对象**里 ——
  //     两道各自独立,任一道单独失效都不会让那一格空过。
  const body = script[1]
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^[ \t]*\/\/.*$/gm, "")
    .replace(/([^:])\/\/.*$/gm, "$1");

  // --- (a) 事件名逐字同源 ---
  assert.ok(
    body.includes(`eventId: "${eventId}"`),
    "内联脚本应逐字引用 BridgeApi.h 的信号名",
  );

  // --- (b) 嵌套两层 rAF ---
  // 单层 rAF 的回调跑在这一帧提交**之前**,比嵌套两层更早,信号更不可能落在已绘之后。
  assert.match(
    body,
    /requestAnimationFrame\(\s*function\s*\(\s*\)\s*\{\s*window\.requestAnimationFrame\(\s*signal\s*\)/,
    "信号必须嵌套两层 requestAnimationFrame",
  );

  // --- (c) [SL-433] 武装**确实由 paint 记录接线过来** —— 断的是**生效**,不是在场 ---
  // 绕法很自然:把武装改回 DOMContentLoaded、同时把 PerformanceObserver 留成死代码
  // (「怕某些浏览器不报 paint 记录,两边都挂上」)⇒ 片段全在、判据全绿、病照旧。所以四条一起断:
  //   · `new PerformanceObserver` 在场;
  //   · `buffered: true` 必须落在 `.observe({...})` 的**实参对象**里(不是块里任意位置);
  //   · **paint 回调体里真的调了 armOnce**(死代码那条路死在这一条上)。这里用**大括号配对**
  //     切出回调体来判,不用字符距离窗口 —— 窗口是「今天不漏」,不是结构;
  //   · `DOMContentLoaded` 在整块里**恰好出现一次,且在 catch 里** —— 多出来的那一次正是
  //     「把武装改回 DCL」的形态,回落路只许待在 catch 那条兜底路上。
  const poCallback = jsBodyAt(
    body,
    /new\s+PerformanceObserver\s*\(/,
    "PerformanceObserver 的回调",
  );
  assert.match(
    poCallback,
    /armOnce\s*\(/,
    "paint 回调体里必须真的调 armOnce(片段在场但不接线 = 武装仍由 DOMContentLoaded 驱动)",
  );
  assert.match(
    body,
    /\.observe\s*\(\s*\{[^}]*type\s*:\s*"paint"[^}]*buffered\s*:\s*true[^}]*\}\s*\)/,
    'buffered: true 必须落在 .observe({ type: "paint", ... }) 的实参对象里(paint 记录可能早于本脚本产生)',
  );
  assert.equal(
    (body.match(/DOMContentLoaded/g) || []).length,
    1,
    "DOMContentLoaded 在整块里必须恰好出现一次(多出来的那一次 = 把武装改回了 DCL)",
  );
  assert.match(
    body,
    /catch\s*(\([^)]*\)\s*)?\{[^}]*DOMContentLoaded/,
    "唯一那次 DOMContentLoaded 必须在 catch 里(它只是「压根没有 PerformanceObserver」时的回落路)",
  );

  // --- (d) [SL-433] 回落路 + 保险定时器,以及保险本身的三条形态 ---
  // 这三条每一条都是 SCVB 同族卡在复审里现场栽出来的,且栽的时候「片段在场」那几条全绿:
  //   · 保险**排在 try 之前** —— 排在 po.observe() 之后的话,`new PerformanceObserver` 抛错时
  //     那一行根本没执行过 ⇒ **回落路压根没有保险**;
  //   · 保险的回调**直接发信号、不绕两层 rAF** —— 「paint 不来」最可能的成因是 BeginFrame
  //     停摆,那时 rAF 也不回调 ⇒ 绕过去等于把绳子拴在同一根断掉的柱子上;
  //   · **撤网(clearTimeout)落在 signal() 里** —— 落在 armOnce() 里的话,网在信号真发出去
  //     之前就没了,而撤网后剩下的恰恰是上一条说的那两层 rAF。
  assert.match(
    body,
    /readyState/,
    "回落路必须读 readyState(脚本晚于 DOMContentLoaded 执行时也要武装)",
  );
  assert.equal(
    (body.match(/setTimeout\s*\(/g) || []).length,
    1,
    "保险定时器必须恰好一个(多一个就有第二条时限,读日志时分不出是哪条发的)",
  );
  const guardAt = body.search(/setTimeout\s*\(/);
  const poAt = body.search(/new\s+PerformanceObserver\s*\(/);
  const tryAt = body.lastIndexOf("try", poAt);
  assert.ok(
    tryAt >= 0 && tryAt < poAt,
    "new PerformanceObserver 必须包在 try 里(没有 PerformanceObserver 的浏览器要走回落路)",
  );
  assert.ok(
    guardAt >= 0 && guardAt < tryAt,
    "保险定时器必须排在那个 try **之前**:排在 po.observe() 之后的话," +
      "new PerformanceObserver 抛错时它根本没执行过 —— 回落路就没有保险了",
  );
  // ⚠ 顺序有意如此:先断「不许把 arm/armOnce 直接当回调」,再去切回调体。反过来的话
  // `setTimeout(armOnce, 2500)` 这一注入会先把下面的大括号配对**滑到紧随其后的 try 块上**
  // (实测过),红是红了却红在别的断言上 —— 「红在设计接住它的那条断言上」就不成立了。
  assert.doesNotMatch(
    body,
    /setTimeout\s*\(\s*(arm|armOnce)\s*[,)]/,
    "保险不许把 arm/armOnce 当回调(那条路还要过两层 rAF,BeginFrame 停摆那一档下根本不回调)",
  );
  // 锚点带上 `function`:回调不是**就地写的函数**时,配对同样会滑到无关的块上 ⇒ 这里让
  // jsBodyAt 的 fail-closed 在锚点这一步就判红,而不是让后面那条断言去背这口锅。
  const guardCallback = jsBodyAt(
    body,
    /setTimeout\s*\(\s*function/,
    "保险定时器的**就地**回调 setTimeout(function () {...})",
  );
  assert.match(
    guardCallback,
    /signal\s*\(\s*\)/,
    "保险的回调必须**直接发信号**:绕 arm() 的两层 rAF 时,BeginFrame 停摆那一档下 rAF 根本不回调," +
      "保险等于不存在",
  );
  assert.equal(
    (body.match(/clearTimeout\s*\(/g) || []).length,
    1,
    "撤网必须恰好一处",
  );
  const signalBody = jsBodyAt(body, /function\s+signal\s*\(/, "signal()");
  assert.match(
    signalBody,
    /clearTimeout\s*\(/,
    "撤网必须落在 signal() 里:落在 armOnce() 里的话,网在信号真发出去之前就撤了," +
      "而撤网后剩下的正是两层 rAF",
  );
  // [SL-433 第 1 轮复审] 「落在 signal() 里」还不够 —— 上一版就是落在 signal() 里、却排在
  // `try` 之前,也就是排在「__JUCE__ 在不在」那道守卫之前:守卫命中 return(或 postMessage
  // 抛异常)时信号一个字节没发出去,网却已经撤了。**注释宣称的保证,代码给不到** —— 而上面
  // 那两条断言当时全是绿的。所以这里按**位置**钉死那句不变式的两半:撤网与去重都必须排在
  // `postMessage` 之后。用下标比较而不是再加正则(判据面别再长胖,判例 SL-431)。
  const postAt = signalBody.search(/postMessage\s*\(/);
  assert.ok(
    postAt >= 0,
    "signal() 里必须有 postMessage((源钉找不到发送点即判红)",
  );
  assert.ok(
    signalBody.search(/clearTimeout\s*\(/) > postAt,
    "撤网(clearTimeout)必须排在 postMessage **之后**:排在前面时,__JUCE__ 不在场或 postMessage" +
      " 抛异常这两条路上信号根本没发出去,网却已经撤了 —— 保险就白挂了",
  );
  assert.ok(
    signalBody.search(/sent\s*=\s*true/) > postAt,
    "去重置位(sent = true)必须排在 postMessage **之后**:排在前面时,一次没发出去的尝试" +
      "会把后面那次真能发出去的短路掉",
  );

  // --- (e) [SL-433] 载荷里的诊断字段:字段名逐字同源 + 算式真的接上了 ---
  // 两条各守一件:①`p.<字段名> = Math.round(performance.now() - paintStartMs)` 的算式形态
  // (顺带把「减号写反 / 拿别的当基线」变成源码可判);② 基线真的取自 paint 记录的 startTime。
  assert.match(
    body,
    new RegExp(
      "p\\." +
        paintDeltaKey +
        "\\s*=\\s*Math\\.round\\(\\s*performance\\.now\\(\\)\\s*-\\s*paintStartMs",
    ),
    `载荷里必须带 p.${paintDeltaKey} = Math.round(performance.now() - paintStartMs)` +
      "(字段名取自 BridgeApi.h 的 timing::FirstFramePaintDeltaKey,逐字一致)",
  );
  assert.match(
    body,
    /paintStartMs\s*=\s*list\.getEntries\(\)\[0\]\.startTime/,
    "差值的基线必须取自 paint 记录的 startTime",
  );

  // --- 原有两条守卫不变 ---
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

  // --- (f) [SL-433] 跨边界字面量的**另一侧**:C++ 真的读了那个字段 ---
  // 为什么非要两侧都断:任一侧漂了,失败形态都是 C++ 打 `(no paint record)` —— 而那与
  // 「页面确实走了回落路 / 保险路」在日志里**逐字同形**,贴 log 回来的人分不出是哪一种,
  // 这个诊断字段就失去存在意义。上面 (e) 守页面那一侧,这里守 C++ 那一侧。
  const src = read("src/WebViewEditor.cpp");
  // 与 ③ ⑤ 同一套词法近似:先把字符串字面量整体换成占位、**再**剥注释(顺序不能反,
  // 理由见 ③ 处注释)。
  const code = src
    .replace(/"(?:[^"\\]|\\.)*"/g, '""')
    .replace(/'(?:[^'\\]|\\.)*'/g, "''")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/\/\/[^\n]*/g, "");
  const hfBody = functionBodyAt(
    code,
    /void\s+SynchainBridgeWebEditor::handleFirstFrame\s*\(/,
    "handleFirstFrame()",
  );
  assert.match(
    hfBody,
    /getProperty\([^;]*FirstFramePaintDeltaKey/,
    "handleFirstFrame 必须经 timing::FirstFramePaintDeltaKey 取那个字段(不许另写字面量)",
  );
  assert.match(
    code,
    /handleFirstFrame\(\s*\w+\s*\)/,
    "事件监听必须把载荷**传下去**:不传的话上面那句永远读到空 var,而编译照过、日志恒打 (no paint record)",
  );
  // 这一条**绑了 paintNote 这个变量名**,有意如此:不绑名字就只能去比字符串字面量,而字符串在
  // 上一步已被整体占位掉。删除式:删掉 logDiag 那句里的 `+ paintNote` ⇒ 本格红;改名时连同
  // 本断言一起改。
  assert.match(
    hfBody,
    /logDiag\([^;]*paintNote/,
    "差值必须真的拼进那行诊断(算出来却不打 = 用户那份日志里什么都没多)",
  );
  // ⚠ [SL-433 第 1 轮复审 · A3] 这一条**不能**扫上面那份 `code`:它把字符串整体占位成 `""`,
  // 字面量断言会**永远绿**(判据自己给自己发合格证)。也不能直接扫原文 `src`:
  // `handleFirstFrame` 上面那段注释本来就在逐字讨论这个字段名(现在写的是反引号才没红),
  // 哪天有人改成双引号就是一条**假红**。所以扫「只剥注释、保留字符串」的那一份。
  assert.ok(
    !new RegExp('"' + paintDeltaKey + '"').test(
      stripCppCommentsKeepStrings(src),
    ),
    `src/WebViewEditor.cpp 里不许出现 "${paintDeltaKey}" 字面量(字段名只有 BridgeApi.h 一个真源)`,
  );
});

test("③ 接线源钉:webView 的 setVisible(false) 只许在 showFallback(兜底路径)", () => {
  const src = read("src/WebViewEditor.cpp");

  // 先把字符串字面量整体换成占位、**再**剥注释(第 2 推 R6):反过来的话,代码字符串里的
  // `//`(如 "https://...")会被剥注释正则吃掉,把该行截成两半 —— 截点之后的
  // setVisible(false) 就逃出源钉,判据假绿。
  // ⚠ 残余局限(第 3 推):这仍是**词法近似** —— 若将来注释/字符串里出现落单的引号,
  // 占位正则可能与真实代码的引号错误配对,把中间段落(连同其中的 setVisible(false))整体
  // 吞掉,本格静默假绿。该方向由下方的**独立原始源码绷线**(不经词法器,逐字计数)兜住。
  const code = src
    .replace(/"(?:[^"\\]|\\.)*"/g, '""')
    .replace(/'(?:[^'\\]|\\.)*'/g, "''")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/\/\/[^\n]*/g, "");

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

  // [第 3 推 R2 独立绷线] 不经词法器,直接数**原始源码**:带成员访问前缀的
  // setVisible(false) 必须恰好一处(showFallback)。注释里的两处提及都是裸
  // setVisible(false)、无 mWebView-> 前缀,不会误计;上方词法近似(字符串占位)的
  // 残余假绿方向由这条独立兜住。删除式:任意位置加一行 mWebView->setVisible(false); ⇒ 红。
  assert.equal(
    (src.match(/mWebView\s*->\s*setVisible\(\s*false\s*\)/g) ?? []).length,
    1,
    "原始源码里 mWebView->setVisible(false) 必须恰好一处(showFallback 之外不许隐藏 WebView)",
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

  // [第 1 推 R2 源钉] 宿主 paint 必须在场且经共享实现铺占位。
  // 遮挡窗口内 BridgeWebView 被挪到 x=2W、与可视区零交集,JUCE 整个跳过它的 paint ——
  // 没有宿主这一层,屏上就是 wrapper 残留像素(bot 第 1 轮【重要】)。
  // 删除式:删掉宿主 paint() ⇒ 本格红;复原 ⇒ 绿。
  const paintAt = code.search(/void\s+SynchainBridgeWebEditor::paint\s*\(/);
  assert.ok(
    paintAt >= 0,
    "SynchainBridgeWebEditor::paint 必须在场:它是遮挡窗口内唯一会跑的占位层(宿主层)",
  );
  const paintBody = code.slice(paintAt, paintAt + 900);
  assert.match(
    paintBody,
    /paintPlaceholderGradient\(/,
    "宿主 paint 必须经 paintPlaceholderGradient 铺占位(与 BridgeWebView 共用唯一实现)",
  );
});

test("④ 插件路径关掉卡片入场动画,且早于首帧信号生效(源钉,fail-closed)", () => {
  const html = read("web/index.html");

  // 主脚本必须是 type="module":整条时序保证依赖它 —— module 脚本在文档解析完
  // (readyState === "interactive")时求值,早于 DOMContentLoaded 派发。删除式:去掉
  // type="module" ⇒ 本格红(module 求值点变了,boot() 的执行时机不再由构造保证)。
  const moduleAt = html.search(/<script\s+type="module">/);
  assert.ok(
    moduleAt >= 0,
    "主脚本必须 type=" +
      '"module"' +
      "(boot() 在模块求值时执行,早于 DOMContentLoaded 派发)",
  );
  // [第 4 推 R2] 含 boot() 的脚本必须是那个 module 脚本(boot 定义在 module 开标签之后)。
  assert.ok(
    html.search(/function\s+boot\s*\(/) > moduleAt,
    "boot() 必须定义在 type=module 脚本内(时序保证的前半句)",
  );

  // [第 3 推 R1 改准] 时序:boot() 在**模块求值时**(readyState === "interactive")已执行、
  // 早于 DOMContentLoaded 派发 —— 不是「DOMContentLoaded 派发中同步执行」(module 脚本在
  // 解析完、DOMContentLoaded 事件之前求值,此刻 readyState 已是 interactive,走的是
  // readyState !== "loading" 的立即分支)。首帧信号则在 DOMContentLoaded 之后等两层 rAF,
  // 故「先关动画、后发信号」由构造保证。删除式双向:
  //   · 去掉 isPlugin 段里的 animation: "none" ⇒ 本格红;
  //   · 把那句搬到 else(预览)分支 ⇒ 本格红(第 1/2 推的整函数断言对搬家假绿,已实测)。
  const fnAt = html.search(/function\s+layoutForMode\s*\(/);
  assert.ok(fnAt >= 0, "index.html 应有 layoutForMode()(模式布局入口)");
  const ifAt = html.indexOf("if (isPlugin)", fnAt);
  assert.ok(ifAt >= 0, "layoutForMode() 应有 isPlugin 分支");
  const elseAt = html.indexOf("} else {", ifAt);
  assert.ok(elseAt > ifAt, "layoutForMode() 应有 else(预览)分支");
  // [第 4 推 R2] pluginSeg 匹配前先剥 `//` 行注释:否则 isPlugin 段注释里写出
  // animation: "none" 字面量、真句删掉,本格照样绿(改前绿已实测)。
  const pluginSeg = html.slice(ifAt, elseAt).replace(/\/\/[^\n]*/g, "");
  assert.match(
    pluginSeg,
    /animation:\s*"none"/,
    "layoutForMode() 的 **isPlugin 段**必须关掉卡片入场动画(挪去 else、删掉、或只写在注释里 ⇒ 红)",
  );
});

test("⑤ WebView2 DefaultBackgroundColor 那一层必须接上,且取值不许另写字面量(源钉)", () => {
  const src = read("src/WebViewEditor.cpp");

  // 与 ③ 同一套词法近似:先把字符串字面量整体换成占位、再剥注释。本格尤其需要它 ——
  // 下面几处的名字在注释里都出现过,不剥注释的话「把真句删掉只留注释」照样绿。
  const code = src
    .replace(/"(?:[^"\\]|\\.)*"/g, '""')
    .replace(/'(?:[^'\\]|\\.)*'/g, "''")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/\/\/[^\n]*/g, "");

  // --- (a) makeOptions 里必须有 withBackgroundColour,**且把结果赋值回去** ---
  // 删除式两格:删掉整句 ⇒ 本格红;**只删 `wv2 = ` 半句、保留调用 ⇒ 本格同样红**。
  // 后一格是第 3 推补的:JUCE 的 Options::WinWebView2::withXxx 是 **by-value 返回的
  // builder**(它返回一份改过的副本,不改原对象)—— 少写 `wv2 = ` 在语义上就是**这一层
  // 根本没设**,而屏上照样是白。第 2 推为了「不绑死 wv2 这个变量名」把断言放宽成
  // /\.withBackgroundColour\(/ 时,顺手把赋值这一半也丢了,实测「只删赋值」⑤ 仍然全绿 ——
  // 那正是本仓 CTRL 对照格描述的形态(屏上是白、判据面一片绿),所以这里必须把赋值钉回来。
  // ⚠ 不要指望 [[nodiscard]] 兜底:那是 MSVC C4834 **警告不是错误**,而 gates 对
  // `warning C` 是**计数不判红**。
  // 变量名仍然不绑死(两侧都用 \w+),改名不会假红。
  const mkBody = functionBodyAt(
    code,
    /juce::WebBrowserComponent::Options\s+SynchainBridgeWebEditor::makeOptions\s*\(/,
    "makeOptions()",
  );
  assert.match(
    mkBody,
    /\w+\s*=\s*\w+\.withBackgroundColour\(/,
    "makeOptions() 必须给 WinWebView2 选项设 withBackgroundColour**并把结果赋值回去**" +
      "(withXxx 是 by-value builder,不赋值 = 这一层没设)—— 不设的话 JUCE 把默认构造的" +
      " juce::Colour(ARGB 0x00000000,全透明)原样 put 进 put_DefaultBackgroundColor,控制器建好到" +
      "页面画出来之间那一层什么都不挡,露的是窗口的白(遮挡闸与 <head> 内联底都盖不到这一段)",
  );

  // --- (b) 取值必须现算,不许另写一个色值字面量 ---
  // 删除式:把参数换成 juce::Colour(0xffd9cadb) 之类的字面量 ⇒ 本格红(那就成了占位色的
  // 第二个真源,改 kPlaceholderStops 时它不会跟着变,而没有任何东西会红)。
  const arg = mkBody.match(/withBackgroundColour\(([^;]*?)\)\s*;/);
  assert.ok(arg, "应能取到 withBackgroundColour 的实参");
  assert.match(
    arg[1],
    /webview::placeholderMidArgb\(\s*\)/,
    "withBackgroundColour 的取值必须经 webview::placeholderMidArgb() 从 kPlaceholderStops 现算",
  );
  assert.doesNotMatch(
    arg[1],
    /0x[0-9a-fA-F]{6,8}/,
    "withBackgroundColour 的实参里不许出现色值字面量(占位色只有 kPlaceholderStops 一个真源)",
  );

  // --- (c) 「这一层在不在」的诊断行必须接上,且打在 goToURL 之前 ---
  // JUCE 对 QueryInterface(ICoreWebView2Controller2) 取不到是静默跳过(没有 else、没有日志、
  // 不看 HRESULT),不打这行就分不出「设了没生效」与「压根没设」。
  // 删除式:删掉 beginLoadAttempt 里那次调用 ⇒ 本格红;把它挪到 goToURL 之后 ⇒ 也红。
  const blBody = functionBodyAt(
    code,
    /void\s+SynchainBridgeWebEditor::beginLoadAttempt\s*\(/,
    "beginLoadAttempt()",
  );
  const logAt = blBody.search(/logDefaultBackgroundSupport\(/);
  const navAt = blBody.search(/goToURL\(/);
  assert.ok(
    logAt >= 0,
    "beginLoadAttempt() 必须调 logDefaultBackgroundSupport()(否则这一层在不在完全不可观测)",
  );
  assert.ok(navAt >= 0, "beginLoadAttempt() 应有 goToURL()");
  assert.ok(
    logAt < navAt,
    "诊断行必须打在 goToURL() 之前:控制器一建好 JUCE 就 put 那个颜色,打在后面会让读表的人分不清先后",
  );
});
