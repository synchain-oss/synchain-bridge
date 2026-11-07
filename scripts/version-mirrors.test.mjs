// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

// =============================================================================
// version-mirrors.test.mjs —— scripts/version-mirrors.mjs 的夹具测试(node:test + node:assert,零依赖)
//
//   node --test scripts/version-mirrors.test.mjs
//
// 夹具 = 把本仓真实的 6 个文件(CMakeLists.txt、四个镜像文件、CHANGELOG.md)拷到临时目录再改:
// 这些文件的结构一变(lockfile 挪了字段、§三换了表格写法),这里先红,bump-version 不会在发版那天才失灵。
// 测试只写临时目录,不碰工作区。
// =============================================================================

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  cpSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  ALL_FILES,
  MirrorError,
  changedLines,
  cutChangelog,
  fileReader,
  inspect,
  planBump,
} from "./version-mirrors.mjs";

const REPO = fileURLToPath(new URL("..", import.meta.url));
const FILES = [...ALL_FILES.map((e) => e.file), "CHANGELOG.md"];

function fixture(t) {
  const dir = mkdtempSync(join(tmpdir(), "bridge-version-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  for (const rel of FILES) cpSync(join(REPO, rel), join(dir, rel));
  const read = (rel) => readFileSync(join(dir, rel), "utf8");
  const write = (rel, text) => writeFileSync(join(dir, rel), text);
  const edit = (rel, fn) => write(rel, fn(read(rel)));
  return { dir, read, write, edit, reader: fileReader(dir) };
}

function nextMinor(v) {
  const [major, minor] = v.split(".").map(Number);
  return `${major}.${minor + 1}.0`;
}

function json(text) {
  return JSON.parse(text);
}

function canonical(obj) {
  return JSON.stringify(obj, null, 2) + "\n";
}

test("镜像漂移:报出是哪个文件、哪个值", (t) => {
  const f = fixture(t);
  f.edit("web-preview/package.json", (s) =>
    canonical({ ...json(s), version: "0.0.1" }),
  );
  const r = inspect(f.reader);
  assert.equal(r.problems.length, 1);
  assert.match(r.problems[0], /web-preview\/package\.json .*0\.0\.1/);
});

test("结构变化:字段没了要报错,不能静默少比一处", (t) => {
  const f = fixture(t);
  f.edit("web-preview/package-lock.json", (s) => {
    const j = json(s);
    delete j.packages[""].version;
    return canonical(j);
  });
  f.edit("BRIDGE_CONTRACT.md", (s) =>
    s.replace(/^\| VERSION \|/m, "| PLUGIN VERSION |"),
  );
  const r = inspect(f.reader);
  assert.equal(r.problems.length, 2);
  assert.match(
    r.problems.join("\n"),
    /package-lock\.json 结构变化.*期望 2 处,实际 1 处/,
  );
  assert.match(
    r.problems.join("\n"),
    /BRIDGE_CONTRACT\.md 结构变化.*期望 1 处,实际 0 处/,
  );
});

test("CMake:注释里的旧 project(VERSION) 不算真源,第二处真 project(VERSION) 算歧义", (t) => {
  const f = fixture(t);
  f.edit("CMakeLists.txt", (s) => "# project(Old VERSION 0.0.1)\n" + s);
  assert.deepEqual(inspect(f.reader).problems, []);
  f.edit("CMakeLists.txt", (s) => s + "\nproject(Other VERSION 0.0.2)\n");
  assert.match(
    inspect(f.reader).problems.join("\n"),
    /CMakeLists\.txt 结构变化.*实际 2 处/,
  );
});

test("bump:只改版本字段所在的 6 行,依赖里同号的 version 不动,CHANGELOG 切版", (t) => {
  const f = fixture(t);
  const old = inspect(f.reader).source;
  const next = nextMinor(old);
  // 依赖版本号故意与插件版本相同:全文替换会把它一起改掉
  f.edit("web-preview/package-lock.json", (s) => {
    const j = json(s);
    const dep = Object.keys(j.packages).find((k) =>
      k.startsWith("node_modules/"),
    );
    assert.ok(dep, "夹具前提:lockfile 里至少有一个 node_modules/ 依赖");
    j.packages[dep].version = old;
    return canonical(j);
  });
  f.edit("CHANGELOG.md", (s) =>
    s.replace("## [未发布]\n", "## [未发布]\n\n### 修复\n\n- 夹具条目\n"),
  );
  const before = new Map(FILES.map((rel) => [rel, f.read(rel)]));

  const plan = planBump(f.reader, next, "2001-02-03");
  assert.equal(plan.previous, old);
  assert.equal(plan.movedEntries, true);
  assert.deepEqual([...plan.files.keys()].sort(), [...FILES].sort());

  let total = 0;
  for (const e of ALL_FILES) {
    const n = changedLines(before.get(e.file), plan.files.get(e.file));
    assert.equal(n, e.count, e.file);
    total += n;
  }
  assert.equal(total, 6);

  const lock = json(plan.files.get("web-preview/package-lock.json"));
  const dep = Object.keys(lock.packages).find((k) =>
    k.startsWith("node_modules/"),
  );
  assert.equal(lock.packages[dep].version, old);
  assert.equal(lock.version, next);
  assert.equal(lock.packages[""].version, next);

  const log = plan.files.get("CHANGELOG.md");
  const iUnreleased = log.indexOf(
    "## [未发布]\n\n## [" + next + "] — 2001-02-03\n",
  );
  const iEntry = log.indexOf("- 夹具条目");
  const iOld = log.indexOf(`## [${old}]`);
  assert.ok(iUnreleased >= 0, "空的 [未发布] 后面紧跟新版本节");
  assert.ok(
    iUnreleased < iEntry && iEntry < iOld,
    "原 [未发布] 的条目移到新版本节下、旧版本节之上",
  );
  assert.match(
    log,
    new RegExp(`版本号由 ${old.replaceAll(".", "\\.")} 升至 \\*\\*${next}`),
  );
  assert.equal(log.split("\n## [未发布]").length, 2, "仍只有一个 [未发布]");

  // planBump 不写盘
  for (const rel of FILES) assert.equal(f.read(rel), before.get(rel), rel);
});

test("bump 拒绝:不递增、带后缀、前导零、镜像本来就不一致、CHANGELOG 已有该版本节", (t) => {
  const f = fixture(t);
  const old = inspect(f.reader).source;
  const next = nextMinor(old);
  assert.throws(
    () => planBump(f.reader, old, "2001-02-03"),
    /必须大于当前版本/,
  );
  assert.throws(
    () => planBump(f.reader, `${next}-rc.1`, "2001-02-03"),
    /不是 X\.Y\.Z/,
  );
  assert.throws(
    () => planBump(f.reader, "01.2.3", "2001-02-03"),
    /不是 X\.Y\.Z/,
  );

  f.edit("CHANGELOG.md", (s) =>
    s.replace("## [未发布]\n", `## [未发布]\n\n## [${next}] — 2001-01-01\n`),
  );
  assert.throws(() => planBump(f.reader, next, "2001-02-03"), /已经有 ## \[/);

  f.edit("web-preview/mock-server.mjs", (s) =>
    s.replace(/PLUGIN_VERSION = "[^"]+"/, 'PLUGIN_VERSION = "0.0.1"'),
  );
  assert.throws(
    () => planBump(f.reader, next, "2001-02-03"),
    (e) => e instanceof MirrorError && /先修好/.test(e.message),
  );
});

test("bump 拒绝改写非 npm 标准格式的 JSON(否则 diff 不止版本行)", (t) => {
  const f = fixture(t);
  f.edit(
    "web-preview/package.json",
    (s) => JSON.stringify(json(s), null, 4) + "\n",
  );
  const next = nextMinor(inspect(f.reader).source);
  assert.throws(
    () => planBump(f.reader, next, "2001-02-03"),
    /package\.json.*不是 npm 的标准格式/,
  );
});

test("cutChangelog:[未发布] 为空时只生成头注;[未发布] 不是恰好一处时报错", () => {
  const base = "# Changelog\n\n## [未发布]\n\n## [1.0.0] — 2000-01-01\n\n- a\n";
  const r = cutChangelog(base, {
    version: "1.1.0",
    previous: "1.0.0",
    date: "2000-02-02",
  });
  assert.equal(r.movedEntries, false);
  assert.match(
    r.text,
    /^## \[未发布\]\n\n## \[1\.1\.0\] — 2000-02-02\n\n> 版本号由 1\.0\.0 升至/m,
  );
  assert.match(r.text, /写完删掉本行 -->\n\n## \[1\.0\.0\] — 2000-01-01\n/);
  assert.throws(
    () =>
      cutChangelog(base.replace("## [未发布]\n", ""), {
        version: "1.1.0",
        previous: "1.0.0",
        date: "2000-02-02",
      }),
    /恰好一处,实际 0 处/,
  );
});
