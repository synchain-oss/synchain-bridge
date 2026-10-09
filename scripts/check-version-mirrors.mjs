// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

// =============================================================================
// check-version-mirrors.mjs —— 断言插件版本号的 4 个镜像文件(5 处)与真源 CMakeLists.txt 一致
//
//   node scripts/check-version-mirrors.mjs [--root <仓库根>]
//
// 退出码:0 = 一致;1 = 不一致 / 结构变化 / 读不到;2 = 参数错误。
// 调用方:compliance.yml 的「Plugin version mirrors」步骤(dev 的必需检查,无路径过滤)与 scripts/gates.ps1 的 gate 3e,
// 两边跑的是同一个脚本。release.yml 的 gate 只在打 tag 时比 tag ↔ CMake,不看这些镜像(PR #19 评审时漂过一次)。
// 镜像清单与读取规则在 scripts/version-mirrors.mjs;只用 node 内建模块,不需要 npm install。
// =============================================================================

import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import { fileReader, inspect } from "./version-mirrors.mjs";

const USAGE = "用法: node scripts/check-version-mirrors.mjs [--root <仓库根>]";

function parseArgs(argv) {
  let root = fileURLToPath(new URL("..", import.meta.url));
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--root" && i + 1 < argv.length) {
      root = resolve(argv[++i]);
    } else {
      return { error: `未知参数「${argv[i]}」\n${USAGE}` };
    }
  }
  return { root };
}

const args = parseArgs(process.argv.slice(2));
if (args.error) {
  console.error(args.error);
  process.exit(2);
}

const inActions = process.env.GITHUB_ACTIONS === "true";
const { source, mirrors, problems } = inspect(fileReader(args.root));

if (source !== undefined) {
  console.log(`真源 CMakeLists.txt project(... VERSION) = ${source}`);
}
for (const m of mirrors) {
  const mark = m.values.every((v) => v === source) ? "ok  " : "DIFF";
  console.log(`  ${mark} ${m.file}  ${m.label} = ${m.values.join(", ")}`);
}

if (problems.length > 0) {
  for (const p of problems) {
    console.log(inActions ? `::error::${p}` : `  FAIL ${p}`);
  }
  console.log(
    `版本镜像不一致(${problems.length} 处问题);抬版本用 node scripts/bump-version.mjs X.Y.Z,它会一次改齐五处`,
  );
  process.exit(1);
}
console.log(
  `版本镜像一致:CMake ${source} == ${mirrors.length} 个文件里的 5 处镜像`,
);
