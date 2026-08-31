import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync, mkdirSync, existsSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { after, test } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

const skillRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const scriptPath = join(skillRoot, "bin", "git-stage-lines.mjs");
const createdRepositories = [];

function runGit(repository, ...argumentsList) {
  const result = spawnSync("git", argumentsList, {
    cwd: repository,
    encoding: null,
    shell: false,
    windowsHide: true,
  });
  if (result.status !== 0) {
    throw new Error(`git ${argumentsList.join(" ")} failed: ${result.stderr.toString("utf8")}`);
  }
  return result;
}

function runGitAllowFailure(repository, ...argumentsList) {
  return spawnSync("git", argumentsList, {
    cwd: repository,
    encoding: null,
    shell: false,
    windowsHide: true,
  });
}

function createRepository() {
  const repository = mkdtempSync(join(tmpdir(), "git-stage-lines-test-"));
  createdRepositories.push(repository);
  runGit(repository, "init", "--quiet");
  runGit(repository, "config", "user.name", "Git Stage Lines Test");
  runGit(repository, "config", "user.email", "git-stage-lines@example.test");
  runGit(repository, "config", "core.autocrlf", "false");
  return repository;
}

function writeBytes(repository, relativePath, content) {
  const absolutePath = join(repository, ...relativePath.split("/"));
  mkdirSync(dirname(absolutePath), { recursive: true });
  writeFileSync(absolutePath, content);
}

function writeLines(repository, relativePath, lines) {
  writeBytes(repository, relativePath, Buffer.from(lines.join(""), "utf8"));
}

function commitAll(repository, message = "initial") {
  runGit(repository, "add", "--all", "--");
  runGit(repository, "commit", "--quiet", "-m", message);
}

function runTool(repository, ...argumentsList) {
  return spawnSync(process.execPath, [scriptPath, ...argumentsList], {
    cwd: repository,
    encoding: null,
    shell: false,
    windowsHide: true,
  });
}

function assertSuccess(result) {
  assert.equal(result.status, 0, result.stderr.toString("utf8"));
}

function fingerprintFromList(listResult) {
  const fingerprint = /diff-fingerprint=([0-9a-f]{64})/.exec(listResult.stderr.toString("utf8"))?.[1];
  assert.ok(fingerprint, listResult.stderr.toString("utf8"));
  return fingerprint;
}

function cachedDiff(repository, relativePath) {
  return runGit(repository, "diff", "--cached", "--unified=0", "--binary", "--no-ext-diff", "--no-renames", "--", relativePath).stdout;
}

function workingDiff(repository, relativePath) {
  return runGit(repository, "diff", "--unified=0", "--binary", "--no-ext-diff", "--no-renames", "--", relativePath).stdout;
}

function indexPath(repository) {
  const rawPath = runGit(repository, "rev-parse", "--git-path", "index").stdout.toString("utf8").trim();
  return resolve(repository, rawPath);
}

function createManyHunkFile(repository, relativePath = "source.txt") {
  const lines = Array.from({ length: 70 }, (_, index) => `base-${index + 1}\n`);
  writeLines(repository, relativePath, lines);
  commitAll(repository);
  return lines;
}

test("runs when launched through a directory junction or symlink", () => {
  const repository = createRepository();
  const lines = createManyHunkFile(repository);
  lines[9] = "selected-10\n";
  writeLines(repository, "source.txt", lines);

  const linkedSkillRoot = join(repository, "linked-skill");
  const linkType = process.platform === "win32" ? "junction" : "dir";
  symlinkSync(skillRoot, linkedSkillRoot, linkType);

  for (const nodeOptions of [[], ["--preserve-symlinks-main"]]) {
    const result = spawnSync(process.execPath, [
      ...nodeOptions,
      join(linkedSkillRoot, "bin", "git-stage-lines.mjs"),
      "--list",
      "--",
      "source.txt",
    ], {
      cwd: repository,
      encoding: null,
      shell: false,
      windowsHide: true,
    });
    assertSuccess(result);
    assert.deepEqual(result.stdout.toString("utf8").trim().split(/\r?\n/), ["1 L10/D10 (+1/-1)"]);
    assert.match(result.stderr.toString("utf8"), /diff-fingerprint=[0-9a-f]{64}/);
  }
});

test("stages one of multiple hunks", () => {
  const repository = createRepository();
  const lines = createManyHunkFile(repository);
  lines[9] = "selected-10\n";
  lines[29] = "not-selected-30\n";
  writeLines(repository, "source.txt", lines);

  const listed = runTool(repository, "--list", "--", "source.txt");
  assertSuccess(listed);
  assert.deepEqual(listed.stdout.toString("utf8").trim().split(/\r?\n/), ["1 L10/D10 (+1/-1)", "2 L30/D30 (+1/-1)"]);
  assert.match(listed.stderr.toString("utf8"), /diff-fingerprint=[0-9a-f]{64}/);

  const staged = runTool(repository, "--", "source.txt", "10");
  assertSuccess(staged);
  const cached = cachedDiff(repository, "source.txt");
  const working = workingDiff(repository, "source.txt");
  assert.ok(cached.includes(Buffer.from("+selected-10")));
  assert.ok(!cached.includes(Buffer.from("+not-selected-30")));
  assert.ok(working.includes(Buffer.from("+not-selected-30")));
  assert.ok(!working.includes(Buffer.from("+selected-10")));
});

test("stages multiple hunks by change numbers", () => {
  const repository = createRepository();
  const lines = createManyHunkFile(repository);
  lines[9] = "selected-10\n";
  lines[29] = "not-selected-30\n";
  lines[49] = "selected-50\n";
  writeLines(repository, "source.txt", lines);

  const listed = runTool(repository, "--list", "--", "source.txt");
  assertSuccess(listed);
  const staged = runTool(repository, "--changes", "1,3", "--fingerprint", fingerprintFromList(listed), "--", "source.txt");
  assertSuccess(staged);
  const cached = cachedDiff(repository, "source.txt");
  const working = workingDiff(repository, "source.txt");
  assert.ok(cached.includes(Buffer.from("+selected-10")));
  assert.ok(cached.includes(Buffer.from("+selected-50")));
  assert.ok(!cached.includes(Buffer.from("+not-selected-30")));
  assert.ok(working.includes(Buffer.from("+not-selected-30")));
});

test("requires a fingerprint for change-number selection", () => {
  const repository = createRepository();
  const lines = createManyHunkFile(repository);
  lines[9] = "selected-10\n";
  writeLines(repository, "source.txt", lines);

  const result = runTool(repository, "--changes", "1", "--", "source.txt");
  assert.equal(result.status, 2);
  assert.match(result.stderr.toString("utf8"), /requires --fingerprint/);
  assert.equal(cachedDiff(repository, "source.txt").length, 0);
});

test("rejects a malformed fingerprint as an input error", () => {
  const repository = createRepository();
  const lines = createManyHunkFile(repository);
  lines[9] = "selected-10\n";
  writeLines(repository, "source.txt", lines);

  const result = runTool(repository, "--changes", "1", "--fingerprint=", "--", "source.txt");
  assert.equal(result.status, 2);
  assert.match(result.stderr.toString("utf8"), /64-character lowercase hexadecimal/);
  assert.equal(cachedDiff(repository, "source.txt").length, 0);
});

test("preserves an existing staged change when staging another hunk", () => {
  const repository = createRepository();
  const lines = createManyHunkFile(repository);
  lines[9] = "already-staged-10\n";
  writeLines(repository, "source.txt", lines);
  assertSuccess(runTool(repository, "--", "source.txt", "10"));

  lines[29] = "newly-staged-30\n";
  writeLines(repository, "source.txt", lines);
  assertSuccess(runTool(repository, "--", "source.txt", "30"));
  const cached = cachedDiff(repository, "source.txt");
  assert.ok(cached.includes(Buffer.from("+already-staged-10")));
  assert.ok(cached.includes(Buffer.from("+newly-staged-30")));
  assert.equal(workingDiff(repository, "source.txt").length, 0);
});

test("dry-run does not change the index", () => {
  const repository = createRepository();
  const lines = createManyHunkFile(repository);
  lines[9] = "dry-run-change\n";
  writeLines(repository, "source.txt", lines);
  const repositoryIndexPath = indexPath(repository);
  const beforeIndex = readFileSync(repositoryIndexPath);

  const dryRun = runTool(repository, "--dry-run", "--", "source.txt", "10");
  assertSuccess(dryRun);
  assert.ok(dryRun.stdout.includes(Buffer.from("+dry-run-change")));
  assert.deepEqual(readFileSync(repositoryIndexPath), beforeIndex);
  assert.equal(cachedDiff(repository, "source.txt").length, 0);
});

test("stages a new file without mutating the real index during preparation", () => {
  const repository = createRepository();
  writeLines(repository, "new file.txt", ["one\n", "two\n", "three\n"]);
  const beforeIndexExists = existsSync(indexPath(repository));
  const listed = runTool(repository, "--list", "--", "new file.txt");
  assertSuccess(listed);
  assert.deepEqual(listed.stdout.toString("utf8").trim().split(/\r?\n/), ["1 L1-3 (+3/-0)"]);
  assert.equal(existsSync(indexPath(repository)), beforeIndexExists);

  const staged = runTool(repository, "--changes", "1", "--fingerprint", fingerprintFromList(listed), "--", "new file.txt");
  assertSuccess(staged);
  assert.ok(cachedDiff(repository, "new file.txt").includes(Buffer.from("new file mode")));
  assert.equal(workingDiff(repository, "new file.txt").length, 0);
});

test("dry-run new file leaves no intent-to-add entry", () => {
  const repository = createRepository();
  const relativePath = "dry-run-new.txt";
  writeLines(repository, relativePath, ["one\n", "two\n"]);
  const beforeIndexExists = existsSync(indexPath(repository));
  const listed = runTool(repository, "--list", "--", relativePath);
  assertSuccess(listed);
  const dryRun = runTool(repository, "--dry-run", "--changes", "1", "--fingerprint", fingerprintFromList(listed), "--", relativePath);
  assertSuccess(dryRun);
  assert.equal(runGit(repository, "ls-files", "--stage", "-z").stdout.length, 0);
  assert.equal(cachedDiff(repository, relativePath).length, 0);
  assert.equal(existsSync(indexPath(repository)), beforeIndexExists);
});

test("stages a deletion by explicit change number", () => {
  const repository = createRepository();
  writeLines(repository, "delete.txt", ["one\n", "two\n", "three\n"]);
  commitAll(repository);
  rmSync(join(repository, "delete.txt"));
  const listed = runTool(repository, "--list", "--", "delete.txt");
  assertSuccess(listed);
  assert.deepEqual(listed.stdout.toString("utf8").trim().split(/\r?\n/), ["1 D1-3 (+0/-3)"]);
  assertSuccess(runTool(repository, "--changes", "1", "--fingerprint", fingerprintFromList(listed), "--", "delete.txt"));
  assert.ok(cachedDiff(repository, "delete.txt").includes(Buffer.from("deleted file mode")));
  assert.equal(workingDiff(repository, "delete.txt").length, 0);
});

test("lists both sides of a replacement hunk", () => {
  const repository = createRepository();
  const originalLines = Array.from({ length: 100 }, (_, index) => `base-${index + 1}\n`);
  writeLines(repository, "replacement.txt", originalLines);
  commitAll(repository);
  const changedLines = [
    ...originalLines.slice(0, 19),
    "replacement-20\n",
    ...originalLines.slice(80),
  ];
  writeLines(repository, "replacement.txt", changedLines);

  const listed = runTool(repository, "--list", "--", "replacement.txt");
  assertSuccess(listed);
  assert.deepEqual(listed.stdout.toString("utf8").trim().split(/\r?\n/), ["1 L20/D20-80 (+1/-61)"]);
  assertSuccess(runTool(repository, "--", "replacement.txt", "20"));
  const cached = cachedDiff(repository, "replacement.txt");
  assert.ok(cached.includes(Buffer.from("-base-20\n")));
  assert.ok(cached.includes(Buffer.from("-base-80\n")));
  assert.ok(cached.includes(Buffer.from("+replacement-20\n")));
});

test("rejects a staged rename in the repository root", () => {
  const repository = createRepository();
  writeLines(repository, "old-name.txt", ["before\n"]);
  commitAll(repository);
  runGit(repository, "mv", "--", "old-name.txt", "new-name.txt");
  writeLines(repository, "new-name.txt", ["after\n"]);
  const beforeCached = runGit(repository, "diff", "--cached", "--find-renames", "--binary").stdout;
  const result = runTool(repository, "--", "new-name.txt", "1");
  assert.notEqual(result.status, 0);
  assert.match(result.stderr.toString("utf8").toLowerCase(), /rename/);
  assert.deepEqual(runGit(repository, "diff", "--cached", "--find-renames", "--binary").stdout, beforeCached);
});

test("rejects a staged rename in a subdirectory", () => {
  const repository = createRepository();
  writeLines(repository, "dir/alpha.txt", ["before\n"]);
  commitAll(repository);
  runGit(repository, "mv", "--", "dir/alpha.txt", "dir/beta.txt");
  writeLines(repository, "dir/beta.txt", ["after\n"]);
  const result = runTool(repository, "--", "dir/beta.txt", "1");
  assert.notEqual(result.status, 0);
  assert.match(result.stderr.toString("utf8").toLowerCase(), /rename/);
});

test("stages a whitespace-only change", () => {
  const repository = createRepository();
  writeLines(repository, "whitespace.txt", ["value\n"]);
  commitAll(repository);
  writeLines(repository, "whitespace.txt", ["value  \n"]);
  assertSuccess(runTool(repository, "--", "whitespace.txt", "1"));
  assert.ok(cachedDiff(repository, "whitespace.txt").includes(Buffer.from("+value  ")));
});

test("stages a multibyte content change", () => {
  const repository = createRepository();
  writeLines(repository, "multibyte.txt", ["一行目\n", "変更前\n", "三行目\n"]);
  commitAll(repository);
  writeLines(repository, "multibyte.txt", ["一行目\n", "変更後\n", "三行目\n"]);
  assertSuccess(runTool(repository, "--", "multibyte.txt", "2"));
  assert.ok(cachedDiff(repository, "multibyte.txt").includes(Buffer.from("+変更後", "utf8")));
});

test("stages a change in a multibyte filename", () => {
  const repository = createRepository();
  const relativePath = "日本語.txt";
  writeLines(repository, relativePath, ["before\n"]);
  commitAll(repository);
  writeLines(repository, relativePath, ["after\n"]);
  assertSuccess(runTool(repository, "--", relativePath, "1"));
  assert.ok(cachedDiff(repository, relativePath).includes(Buffer.from("+after")));
});

test("stages CRLF content without normalizing bytes", () => {
  const repository = createRepository();
  const relativePath = "crlf.txt";
  writeBytes(repository, relativePath, Buffer.from("one\r\ntwo\r\nthree\r\n"));
  commitAll(repository);
  writeBytes(repository, relativePath, Buffer.from("one\r\nchanged\r\nthree\r\n"));
  assertSuccess(runTool(repository, "--", relativePath, "2"));
  assert.ok(cachedDiff(repository, relativePath).includes(Buffer.from("+changed\r\n")));
  assert.equal(workingDiff(repository, relativePath).length, 0);
});

test("stages a path with spaces", () => {
  const repository = createRepository();
  const relativePath = "directory/space name.txt";
  writeLines(repository, relativePath, ["before\n"]);
  commitAll(repository);
  writeLines(repository, relativePath, ["after\n"]);
  assertSuccess(runTool(repository, "--", relativePath, "1"));
  assert.ok(cachedDiff(repository, relativePath).includes(Buffer.from("+after")));
});

test("stages a path beginning with a dash after the option terminator", () => {
  const repository = createRepository();
  const relativePath = "-danger.txt";
  writeLines(repository, relativePath, ["before\n"]);
  commitAll(repository);
  writeLines(repository, relativePath, ["after\n"]);
  assertSuccess(runTool(repository, "--", relativePath, "1"));
  assert.ok(cachedDiff(repository, relativePath).includes(Buffer.from("+after")));
});

test("rejects a range that crosses a hunk boundary", () => {
  const repository = createRepository();
  const lines = Array.from({ length: 7 }, (_, index) => `base-${index + 1}\n`);
  writeLines(repository, "boundary.txt", lines);
  commitAll(repository);
  lines[1] = "changed-two\n";
  lines[2] = "changed-three\n";
  writeLines(repository, "boundary.txt", lines);
  const result = runTool(repository, "--", "boundary.txt", "2");
  assert.notEqual(result.status, 0);
  assert.match(result.stderr.toString("utf8"), /cuts through/);
  assert.equal(cachedDiff(repository, "boundary.txt").length, 0);
  assert.ok(workingDiff(repository, "boundary.txt").includes(Buffer.from("+changed-two")));
});

test("accepts adjacent line ranges", () => {
  const repository = createRepository();
  const lines = Array.from({ length: 10 }, (_, index) => `base-${index + 1}\n`);
  writeLines(repository, "adjacent.txt", lines);
  commitAll(repository);
  lines[4] = "changed-five\n";
  lines[5] = "changed-six\n";
  writeLines(repository, "adjacent.txt", lines);

  assertSuccess(runTool(repository, "--", "adjacent.txt", "5,6"));
  const cached = cachedDiff(repository, "adjacent.txt");
  assert.ok(cached.includes(Buffer.from("+changed-five\n")));
  assert.ok(cached.includes(Buffer.from("+changed-six\n")));
});

test("does not reject literal Subproject commit text", () => {
  const repository = createRepository();
  writeLines(repository, "subproject-text.txt", ["before\n"]);
  commitAll(repository);
  writeLines(repository, "subproject-text.txt", ["before\n", "Subproject commit deadbeefdeadbeef\n"]);

  assertSuccess(runTool(repository, "--", "subproject-text.txt", "2"));
  assert.ok(cachedDiff(repository, "subproject-text.txt").includes(Buffer.from("+Subproject commit")));
});

test("treats glob characters in a filename literally", () => {
  const repository = createRepository();
  const literalPath = "a[b].txt";
  const decoyPath = "ab.txt";
  writeLines(repository, literalPath, ["before\n"]);
  writeLines(repository, decoyPath, ["decoy\n"]);
  commitAll(repository);
  writeLines(repository, literalPath, ["after\n"]);

  assertSuccess(runTool(repository, "--", literalPath, "1"));
  const stagedPaths = runGit(repository, "--literal-pathspecs", "diff", "--cached", "--name-only", "--", literalPath).stdout.toString("utf8");
  assert.equal(stagedPaths, `${literalPath}\n`);
  assert.deepEqual(readFileSync(join(repository, decoyPath)), Buffer.from("decoy\n"));
});

test("rejects a binary change", () => {
  const repository = createRepository();
  writeBytes(repository, "binary.dat", Buffer.from("header\0before\n"));
  commitAll(repository);
  writeBytes(repository, "binary.dat", Buffer.from("header\0after\n"));
  const result = runTool(repository, "--list", "--", "binary.dat");
  assert.notEqual(result.status, 0);
  assert.match(result.stderr.toString("utf8").toLowerCase(), /binary/);
  assert.equal(cachedDiff(repository, "binary.dat").length, 0);
});

test("rejects a stale list fingerprint", () => {
  const repository = createRepository();
  const lines = createManyHunkFile(repository);
  lines[9] = "first\n";
  writeLines(repository, "source.txt", lines);
  const listed = runTool(repository, "--list", "--", "source.txt");
  assertSuccess(listed);
  const fingerprint = /diff-fingerprint=([0-9a-f]{64})/.exec(listed.stderr.toString("utf8"))?.[1];
  assert.ok(fingerprint);
  lines[9] = "changed-after-list\n";
  writeLines(repository, "source.txt", lines);
  const result = runTool(repository, "--changes", "1", "--fingerprint", fingerprint, "--", "source.txt");
  assert.equal(result.status, 4);
  assert.match(result.stderr.toString("utf8"), /fingerprint/);
  assert.equal(cachedDiff(repository, "source.txt").length, 0);
});

test("range selection rejects an ambiguous deletion coordinate", () => {
  const repository = createRepository();
  const originalLines = Array.from({ length: 30 }, (_, index) => `base-${index + 1}\n`);
  writeLines(repository, "coordinates.txt", originalLines);
  commitAll(repository);
  const changedLines = [...originalLines.slice(0, 20), ...Array.from({ length: 10 }, (_, index) => `inserted-${index + 1}\n`), ...originalLines.slice(20)];
  changedLines.splice(24 + 10, 1);
  writeLines(repository, "coordinates.txt", changedLines);
  const listed = runTool(repository, "--list", "--", "coordinates.txt");
  assertSuccess(listed);
  assert.match(listed.stdout.toString("utf8"), /L21-30/);
  assert.match(listed.stdout.toString("utf8"), /1 L21-30/);
  assert.match(listed.stdout.toString("utf8"), /2 D25/);
  const result = runTool(repository, "--", "coordinates.txt", "21-30");
  assert.notEqual(result.status, 0);
  assert.match(result.stderr.toString("utf8"), /explicit --changes/);
  assert.equal(cachedDiff(repository, "coordinates.txt").length, 0);
});

test("preserves the working-tree bytes after applying a patch", () => {
  const repository = createRepository();
  const relativePath = "bytes.txt";
  const beforeCommit = Buffer.from("一行目\r\n二行目\r\n", "utf8");
  const afterEdit = Buffer.from("一行目\r\n変更後\r\n", "utf8");
  writeBytes(repository, relativePath, beforeCommit);
  commitAll(repository);
  writeBytes(repository, relativePath, afterEdit);
  const beforeApply = readFileSync(join(repository, relativePath));
  assertSuccess(runTool(repository, "--", relativePath, "2"));
  assert.deepEqual(readFileSync(join(repository, relativePath)), beforeApply);
});

test("preserves the index when patch checking fails", async () => {
  const repository = createRepository();
  writeLines(repository, "failure.txt", ["base\n"]);
  commitAll(repository);
  const module = await import(pathToFileURL(scriptPath).href);
  const invalidPatch = Buffer.from([
    "diff --git a/failure.txt b/failure.txt\n",
    "--- a/failure.txt\n",
    "+++ b/failure.txt\n",
    "@@ -99,1 +99,1 @@\n",
    "-missing\n",
    "+replacement\n",
  ].join(""));
  const beforeCached = cachedDiff(repository, "failure.txt");
  assert.throws(
    () => module.applyPatchSafely(repository, join(repository, "failure.txt"), "failure.txt", invalidPatch, workingDiff(repository, "failure.txt")),
    module.GitCommandError,
  );
  assert.deepEqual(cachedDiff(repository, "failure.txt"), beforeCached);
  assert.deepEqual(readFileSync(join(repository, "failure.txt")), Buffer.from("base\n"));
});

after(() => {
  for (const repository of createdRepositories) {
    try {
      rmSync(repository, { recursive: true, force: true, maxRetries: 3, retryDelay: 100 });
    } catch {
      // Windows may still hold a transient Git file handle during shutdown.
    }
  }
});
