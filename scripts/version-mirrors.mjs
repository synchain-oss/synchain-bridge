// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

// =============================================================================
// version-mirrors.mjs —— 插件版本号的真源与镜像:定位、读取、改写(只用 node 内建模块)
//
// 版本号唯一真源 = 顶层 CMakeLists.txt 的 project(<名字> VERSION X.Y.Z)(CLAUDE.md §9)。镜像 4 个文件 5 处:
//   web-preview/mock-server.mjs    PLUGIN_VERSION 常量(mock server 把它当插件版本上报给网页)
//   web-preview/package.json       根 version
//   web-preview/package-lock.json  根 version 与 packages[""].version(依赖自己也有 "version",禁止全文替换)
//   BRIDGE_CONTRACT.md             §三 表格里单元格恰为 VERSION 的那一行(不是协议版本 BRIDGE_CONTRACT_VERSION)
//
// 本文件是这套规则的唯一实现,入口有三个:scripts/check-version-mirrors.mjs(compliance 的 CI 步骤与
// scripts/gates.ps1 的 gate 3e 都调用它)、scripts/bump-version.mjs(抬版本)、scripts/version-mirrors.test.mjs(夹具测试)。
// 本文件只导出函数,没有命令行入口。
// =============================================================================

import { readFileSync } from "node:fs";
import { join } from "node:path";

/** 读取时认的版本形态:与 gate 3e 原实现、release.yml 的 gate 同口径(三段数字)。 */
const VERSION_IN_FILE = "[0-9]+\\.[0-9]+\\.[0-9]+";

/** bump 时接受的新版本:X.Y.Z,无前导零、无后缀(CMake 的 project(VERSION) 不收 SemVer 预发布后缀)。 */
export const PLAIN_VERSION = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;

export class MirrorError extends Error {}

function regexSpans(text, re) {
  return [...text.matchAll(re)].map((m) => {
    const [start, end] = m.indices[1];
    return { start, end, value: m[1] };
  });
}

function spliceSpans(text, spans, version) {
  let out = text;
  for (const s of [...spans].sort((a, b) => b.start - a.start)) {
    out = out.slice(0, s.start) + version + out.slice(s.end);
  }
  return out;
}

/** 正则定位的镜像:读与写用同一组匹配位置,写时只替换捕获组的字节。 */
function regexMirror(makeRe, prepare = (t) => t) {
  const spans = (text) => regexSpans(prepare(text), makeRe());
  return {
    read: (text) => spans(text).map((s) => s.value),
    write: (text, version) => spliceSpans(text, spans(text), version),
  };
}

/**
 * npm 生成的 JSON:读走 JSON.parse 取指定字段;写时整体重新序列化。只在文件本来就是 npm 的标准序列化
 * (JSON.stringify(…, null, 2) + "\n")时才写:否则重新序列化会顺带改动版本行以外的字节。
 */
function npmJsonMirror(pick, put) {
  return {
    read: (text) => pick(JSON.parse(text)),
    write: (text, version) => {
      const obj = JSON.parse(text);
      if (JSON.stringify(obj, null, 2) + "\n" !== text) {
        throw new MirrorError(
          "不是 npm 的标准格式(2 空格缩进、LF 行尾、末尾一个换行),拒绝整体改写",
        );
      }
      put(obj, version);
      return JSON.stringify(obj, null, 2) + "\n";
    },
  };
}

/**
 * CMake 行注释(# 到行尾)换成等长空格:偏移不变,改写时可以按下标回填原文。注释里留着的旧
 * project(... VERSION x.y.z)(说明、示例、被注掉的旧行)因此不会被当成真源。与 gate 3e 原实现同口径,
 * 不识别 #[[ ]] 块注释。
 */
function blankCmakeComments(text) {
  return text.replace(/#[^\n]*/g, (m) => " ".repeat(m.length));
}

/** 真源:恰好一处(多于一处说明真源本身有歧义,报错比静默取第一处安全)。 */
export const SOURCE = {
  file: "CMakeLists.txt",
  label: "project(... VERSION)",
  count: 1,
  ...regexMirror(
    () =>
      new RegExp(
        `project\\s*\\(\\s*\\S+\\s+VERSION\\s+(${VERSION_IN_FILE})`,
        "dg",
      ),
    blankCmakeComments,
  ),
};

/** 镜像:count = 该文件里应取到的版本字段个数,少一个、多一个都算结构变化。 */
export const MIRRORS = [
  {
    file: "web-preview/mock-server.mjs",
    label: "PLUGIN_VERSION",
    count: 1,
    ...regexMirror(() => /\bPLUGIN_VERSION\s*=\s*"([^"]+)"/dg),
  },
  {
    file: "web-preview/package.json",
    label: "version",
    count: 1,
    ...npmJsonMirror(
      (j) => [j?.version],
      (j, v) => {
        j.version = v;
      },
    ),
  },
  {
    file: "web-preview/package-lock.json",
    label: 'version、packages[""].version',
    count: 2,
    ...npmJsonMirror(
      (j) => [j?.version, j?.packages?.[""]?.version],
      (j, v) => {
        j.version = v;
        j.packages[""].version = v;
      },
    ),
  },
  {
    file: "BRIDGE_CONTRACT.md",
    label: "§三 VERSION 行",
    count: 1,
    // 锚定行首竖线 + 单元格恰为 VERSION,避开同表的 BRIDGE_CONTRACT_VERSION 行
    ...regexMirror(
      () =>
        new RegExp(`^\\|\\s*VERSION\\s*\\|\\s*\`(${VERSION_IN_FILE})\``, "dgm"),
    ),
  },
];

/** 真源 + 镜像,改写时按这个顺序处理。 */
export const ALL_FILES = [SOURCE, ...MIRRORS];

export function fileReader(root) {
  return (rel) => readFileSync(join(root, rel), "utf8");
}

/**
 * 读一处:返回 { values } 或 { error }。读取失败、解析失败、取到的个数不等于 count 都算 error ——
 * 结构变化可能不抛异常而是取到 undefined,不断言个数就会静默少比一处。
 */
function readOne(entry, readText) {
  let text;
  try {
    text = readText(entry.file);
  } catch (e) {
    return { error: `${entry.file} 读不到(${e.code ?? e.message})` };
  }
  let values;
  try {
    values = entry.read(text).filter((v) => typeof v === "string" && v !== "");
  } catch (e) {
    return { error: `${entry.file} 解析失败(${e.message})` };
  }
  if (values.length !== entry.count) {
    return {
      error: `${entry.file} 结构变化:${entry.label} 期望 ${entry.count} 处,实际 ${values.length} 处`,
    };
  }
  return { values };
}

/**
 * 读真源与全部镜像,返回 { source, mirrors, problems }。source 为真源版本(读不到时为 undefined);
 * mirrors 为 [{ file, label, values }];problems 为人能读懂的问题列表,空数组 = 一致。
 */
export function inspect(readText) {
  const problems = [];
  const src = readOne(SOURCE, readText);
  if (src.error) problems.push(src.error);
  const source = src.values?.[0];
  const mirrors = [];
  for (const m of MIRRORS) {
    const r = readOne(m, readText);
    if (r.error) {
      problems.push(r.error);
      continue;
    }
    mirrors.push({ file: m.file, label: m.label, values: r.values });
    if (source !== undefined) {
      for (const v of r.values) {
        if (v !== source) {
          problems.push(
            `${m.file} 的 ${m.label} = ${v},与 CMake ${source} 不一致`,
          );
        }
      }
    }
  }
  return { source, mirrors, problems };
}

/** 三段数字比较:a > b 返回正数。 */
export function compareVersions(a, b) {
  const pa = a.split(".").map(Number);
  const pb = b.split(".").map(Number);
  for (let i = 0; i < 3; i++) {
    if (pa[i] !== pb[i]) return pa[i] - pb[i];
  }
  return 0;
}

/** 新旧全文逐行比较,返回改动的行数;行数变了直接报错(版本改写不该增删行)。 */
export function changedLines(before, after) {
  const a = before.split("\n");
  const b = after.split("\n");
  if (a.length !== b.length) {
    throw new MirrorError(`改写后行数从 ${a.length} 变成 ${b.length}`);
  }
  return a.reduce((n, line, i) => n + (line !== b[i] ? 1 : 0), 0);
}

const UNRELEASED_HEADING = /^## \[未发布\][ \t]*$/gm;

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * 把 CHANGELOG 的「## [未发布]」切成新版本节:原来 [未发布] 下的条目原样移到「## [X.Y.Z] — <日期>」下,
 * 上面留一个空的 [未发布];版本节开头写版本号来源,另留一行注释提醒发版者补「契约变更」与「跳过的版本号」
 * (照 1.5.3 / 1.6.0 的头注)。返回 { text, movedEntries }。
 */
export function cutChangelog(
  text,
  { version, previous, date, contractVersion },
) {
  const headings = [...text.matchAll(UNRELEASED_HEADING)];
  if (headings.length !== 1) {
    throw new MirrorError(
      `CHANGELOG.md 里「## [未发布]」应恰好一处,实际 ${headings.length} 处`,
    );
  }
  if (new RegExp(`^## \\[${escapeRegExp(version)}\\]`, "m").test(text)) {
    throw new MirrorError(`CHANGELOG.md 已经有 ## [${version}] 一节`);
  }
  const head = headings[0];
  const bodyStart = head.index + head[0].length;
  const next = /^## \[/m.exec(text.slice(bodyStart));
  const bodyEnd = next ? bodyStart + next.index : text.length;
  const body = text
    .slice(bodyStart, bodyEnd)
    .replace(/^\s*\n/, "")
    .trimEnd();
  const contract = contractVersion
    ? `\`BRIDGE_CONTRACT_VERSION\` 仍为 \`${contractVersion}\``
    : "`BRIDGE_CONTRACT_VERSION` 见 BRIDGE_CONTRACT.md §三";
  const section = [
    `## [${version}] — ${date}`,
    "",
    `> 版本号由 ${previous} 升至 **${version}**(唯一真源 \`CMakeLists.txt\` 的 \`project(... VERSION)\`,四镜像同步:`,
    "> web-preview 的 mock-server.mjs / package.json / package-lock.json 与 `BRIDGE_CONTRACT.md` §三)。",
    `> <!-- bump-version:在这里补契约变更(没有就写「**不涉及契约变更**(wire 协议零改动,${contract})」)与跳过的版本号(如有),写完删掉本行 -->`,
  ];
  if (body) section.push("", body);
  const rest = text.slice(bodyEnd);
  const out =
    text.slice(0, bodyStart) +
    "\n\n" +
    section.join("\n") +
    "\n" +
    (rest ? "\n" + rest : "");
  return { text: out, movedEntries: body !== "" };
}

/** BRIDGE_CONTRACT.md §三的协议版本(只用于 CHANGELOG 头注的提示文字,读不到返回 undefined)。 */
export function readContractVersion(text) {
  const m = /^\|\s*BRIDGE_CONTRACT_VERSION\s*\|\s*`([^`]+)`/m.exec(text);
  return m?.[1];
}

/**
 * 计算一次抬版本要写的全部内容(不写盘)。返回 { previous, files: Map<相对路径, 新全文>, movedEntries }。
 * 前置条件:真源与镜像当前一致;新版本是 X.Y.Z 且大于当前版本;CHANGELOG 有且只有一个 [未发布]。
 * 后置条件(不满足即抛错,一个字节都不写):每个文件改动的行数恰好等于它的版本字段个数(合计 6 行),
 * 改完再读一遍,五处都等于新版本。
 */
export function planBump(readText, version, date) {
  if (!PLAIN_VERSION.test(version)) {
    throw new MirrorError(
      `新版本「${version}」不是 X.Y.Z(无前导零、无后缀;预发布 tag 用 vX.Y.Z-<后缀> 打在同一个 VERSION 上)`,
    );
  }
  const before = inspect(readText);
  if (before.problems.length > 0) {
    throw new MirrorError(
      "当前真源与镜像不一致,先修好再抬版本:\n  " + before.problems.join("\n  "),
    );
  }
  const previous = before.source;
  if (compareVersions(version, previous) <= 0) {
    throw new MirrorError(`新版本 ${version} 必须大于当前版本 ${previous}`);
  }

  const files = new Map();
  for (const entry of ALL_FILES) {
    const old = readText(entry.file);
    let next;
    try {
      next = entry.write(old, version);
    } catch (e) {
      throw new MirrorError(`${entry.file}:${e.message}`);
    }
    const n = changedLines(old, next);
    if (n !== entry.count) {
      throw new MirrorError(
        `${entry.file} 改动了 ${n} 行,应恰好 ${entry.count} 行`,
      );
    }
    files.set(entry.file, next);
  }

  const after = inspect((rel) =>
    files.has(rel) ? files.get(rel) : readText(rel),
  );
  if (after.problems.length > 0 || after.source !== version) {
    throw new MirrorError(
      "改写后复读不一致:\n  " + after.problems.join("\n  "),
    );
  }

  const contractVersion = readContractVersion(readText("BRIDGE_CONTRACT.md"));
  const cut = cutChangelog(readText("CHANGELOG.md"), {
    version,
    previous,
    date,
    contractVersion,
  });
  files.set("CHANGELOG.md", cut.text);
  return { previous, files, movedEntries: cut.movedEntries };
}
