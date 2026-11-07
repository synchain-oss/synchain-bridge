// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

// =============================================================================
// bump-version.mjs —— 抬插件版本号:一次改齐真源与 5 处镜像,并把 CHANGELOG 的 [未发布] 切成新版本节
//
//   node scripts/bump-version.mjs X.Y.Z [--date YYYY-MM-DD] [--dry-run] [--root <仓库根>]
//
// 改 6 个文件(docs/release.md §1):
//   CMakeLists.txt                 project(... VERSION)(真源)
//   web-preview/mock-server.mjs    PLUGIN_VERSION
//   web-preview/package.json       根 version
//   web-preview/package-lock.json  根 version 与 packages[""].version(依赖自己的 "version" 不动)
//   BRIDGE_CONTRACT.md             §三 VERSION 行
//   CHANGELOG.md                   [未发布] 下的条目移到 ## [X.Y.Z] — <日期>(默认今天的 UTC 日期),上面留空的 [未发布]
//
// 只改工作区,不提交、不打 tag、不推送。先算出全部新内容并复验(版本字段以外一个字节都不动、改完五处都等于新版本),
// 任何一步不满足就整体放弃,一个文件都不写。新版本必须是 X.Y.Z 且大于当前版本;预发布 tag(vX.Y.Z-<后缀>)
// 打在同一个 VERSION 上,不需要也不能写进这些文件。
// =============================================================================

import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  MirrorError,
  fileReader,
  inspect,
  planBump,
} from "./version-mirrors.mjs";

const USAGE =
  "用法: node scripts/bump-version.mjs X.Y.Z [--date YYYY-MM-DD] [--dry-run] [--root <仓库根>]";

function isRealDate(s) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
}

function parseArgs(argv) {
  const out = {
    root: fileURLToPath(new URL("..", import.meta.url)),
    date: new Date().toISOString().slice(0, 10),
    dryRun: false,
    version: undefined,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--dry-run") out.dryRun = true;
    else if (a === "--date" && i + 1 < argv.length) out.date = argv[++i];
    else if (a === "--root" && i + 1 < argv.length)
      out.root = resolve(argv[++i]);
    else if (!a.startsWith("-") && out.version === undefined) out.version = a;
    else return { error: `未知参数「${a}」\n${USAGE}` };
  }
  if (out.version === undefined) return { error: USAGE };
  if (!isRealDate(out.date))
    return { error: `--date「${out.date}」不是 YYYY-MM-DD 格式的日期` };
  return out;
}

const args = parseArgs(process.argv.slice(2));
if (args.error) {
  console.error(args.error);
  process.exit(2);
}

const readText = fileReader(args.root);
let plan;
try {
  plan = planBump(readText, args.version, args.date);
} catch (e) {
  if (!(e instanceof MirrorError)) throw e;
  console.error(`没有改动任何文件:${e.message}`);
  process.exit(1);
}

const { previous, files, movedEntries } = plan;
console.log(
  `${args.dryRun ? "[dry-run] 将要改写" : "已改写"}(${previous} → ${args.version}):`,
);
for (const rel of files.keys()) console.log(`  ${rel}`);

if (args.dryRun) {
  console.log("[dry-run] 没有写盘。");
  process.exit(0);
}

for (const [rel, text] of files) writeFileSync(join(args.root, rel), text);

// 写盘后从磁盘再读一遍:防的是写入本身出了岔子(只写了一部分、被别的进程改了)
const after = inspect(readText);
if (after.problems.length > 0 || after.source !== args.version) {
  console.error(
    "写盘后复读不一致,请用 git diff 检查并手工修正:\n  " +
      after.problems.join("\n  "),
  );
  process.exit(1);
}

const v = args.version;
console.log(`
CMake 与 5 处镜像都已是 ${v};CHANGELOG 已切出 ## [${v}] — ${args.date}。没有提交、没有打 tag。
${movedEntries ? "" : "注意:[未发布] 下原本没有条目,新版本节目前只有头注。\n"}
下一步(docs/release.md §1、§5):
  1. 编辑 CHANGELOG.md 的 [${v}] 头注:补契约变更与跳过的版本号,删掉 bump-version 注释行;核对条目
  2. git diff --stat                      # 应只有上面 6 个文件
  3. pwsh scripts/gates.ps1 -PluginOnly   # 发 AAX 的版本加 -IncludeAax
  4. 在 feat/* 分支上 git commit -s,开 PR 进 dev;本次改了 BRIDGE_CONTRACT.md §三的登记快照,
     PR 正文写 contract-impact: none(branch-gate 的冻结契约守卫会读它)
  5. 合入 dev 后开 dev → prod 的 PR,用 merge commit 合并,在 prod 的合并提交上打 v${v}(docs/release.md §5)
  6. Release 正文照 docs/release-notes-template.md 写`);
