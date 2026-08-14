#!/usr/bin/env node
// Deterministically stage selected working-tree Git diff hunks.

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, lstatSync, mkdtempSync, readFileSync, readlinkSync, rmSync, copyFileSync } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const HUNK_HEADER_PATTERN = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/;
const RANGE_TOKEN_PATTERN = /^(\d+)(?:-(\d+))?$/;
const FORBIDDEN_PATH_CHARACTERS = new Set(["\0", "\r", "\n", "\t"]);
const CHECK_PATCH_ARGUMENTS = ["apply", "--cached", "--check", "--unidiff-zero", "--whitespace=nowarn"];
const APPLY_PATCH_ARGUMENTS = ["apply", "--cached", "--unidiff-zero", "--whitespace=nowarn"];

export class UserInputError extends Error {}
export class SpecialGitCaseError extends Error {}
export class SafetyError extends Error {}

export class GitCommandError extends Error {
  constructor(argumentsList, result) {
    const commandText = ["git", ...argumentsList].join(" ");
    const errorText = decodeBytes(result.stderr).trim() || `exit code ${result.status}`;
    super(`${commandText}: ${errorText}`);
    this.name = "GitCommandError";
    this.argumentsList = [...argumentsList];
    this.result = result;
  }
}

function decodeBytes(value) {
  return Buffer.isBuffer(value) ? value.toString("utf8") : String(value ?? "");
}

function buildGitEnvironment(overrides = {}) {
  const environment = { ...process.env };
  delete environment.GIT_EXTERNAL_DIFF;
  delete environment.GIT_DIFF_OPTS;
  Object.assign(environment, overrides);
  return environment;
}

export function executeGit(repositoryRoot, argumentsList, environment = {}, inputData = null) {
  const result = spawnSync("git", argumentsList, {
    cwd: repositoryRoot,
    env: buildGitEnvironment(environment),
    input: inputData,
    encoding: null,
    shell: false,
    windowsHide: true,
  });
  if (result.error) {
    return {
      status: typeof result.status === "number" ? result.status : 1,
      stdout: Buffer.isBuffer(result.stdout) ? result.stdout : Buffer.alloc(0),
      stderr: Buffer.from(result.error.message, "utf8"),
    };
  }
  return {
    status: typeof result.status === "number" ? result.status : 1,
    stdout: Buffer.isBuffer(result.stdout) ? result.stdout : Buffer.alloc(0),
    stderr: Buffer.isBuffer(result.stderr) ? result.stderr : Buffer.alloc(0),
  };
}

export function executeGitChecked(repositoryRoot, argumentsList, environment = {}, inputData = null) {
  const result = executeGit(repositoryRoot, argumentsList, environment, inputData);
  if (result.status !== 0) {
    throw new GitCommandError(argumentsList, result);
  }
  return result.stdout;
}

function findRepositoryRoot() {
  const output = executeGitChecked(process.cwd(), ["rev-parse", "--show-toplevel"]);
  const repositoryRoot = resolve(decodeBytes(output).trim());
  if (!existsSync(repositoryRoot) || !lstatSync(repositoryRoot).isDirectory()) {
    throw new UserInputError("Git repository root does not exist");
  }
  return repositoryRoot;
}

function rejectUnmergedRepositoryState(repositoryRoot, environment = {}) {
  const unmergedEntries = executeGitChecked(repositoryRoot, ["ls-files", "-u", "-z"], environment);
  if (unmergedEntries.length > 0) {
    throw new SpecialGitCaseError("unmerged index entries are not supported");
  }
  for (const repositoryStateName of ["MERGE_HEAD", "REBASE_HEAD", "CHERRY_PICK_HEAD"]) {
    let statePath = decodeBytes(executeGitChecked(repositoryRoot, ["rev-parse", "--git-path", repositoryStateName], environment)).trim();
    if (!isAbsolute(statePath)) {
      statePath = resolve(repositoryRoot, statePath);
    }
    if (existsSync(statePath)) {
      throw new SpecialGitCaseError(`repository state ${repositoryStateName} is active; resolve it first`);
    }
  }
}

export function normalizeRepositoryPath(repositoryRoot, pathText) {
  for (const character of pathText) {
    if (FORBIDDEN_PATH_CHARACTERS.has(character)) {
      throw new UserInputError("path contains a forbidden control character");
    }
  }
  const absolutePath = resolve(process.cwd(), pathText);
  const relativePath = relative(repositoryRoot, absolutePath);
  if (!relativePath || relativePath === ".." || relativePath.startsWith(`..${sep}`) || isAbsolute(relativePath)) {
    throw new UserInputError("path must be inside the Git repository");
  }
  if (existsSync(absolutePath) && lstatSync(absolutePath).isDirectory()) {
    throw new UserInputError("a single file path is required, not a directory");
  }
  const relativeText = relativePath.split(sep).join("/");
  if (!relativeText) {
    throw new UserInputError("a file path is required");
  }
  return { absolutePath, relativePath: relativeText };
}

function pathIsTracked(repositoryRoot, relativePath, environment = {}) {
  const argumentsList = ["--literal-pathspecs", "ls-files", "-z", "--stage", "--", relativePath];
  const result = executeGit(repositoryRoot, argumentsList, environment);
  if (result.status !== 0) {
    throw new GitCommandError(argumentsList, result);
  }
  for (const entry of result.stdout.toString("binary").split("\0")) {
    if (!entry) {
      continue;
    }
    const metadata = entry.split("\t", 1)[0].trim().split(/\s+/);
    if (metadata.length >= 3 && metadata[2] !== "0") {
      throw new SpecialGitCaseError("unmerged index entries are not supported");
    }
    if (metadata[0] === "120000" || metadata[0] === "160000") {
      throw new SpecialGitCaseError("symlink and submodule entries are not supported");
    }
  }
  return result.stdout.length > 0;
}

function pathIsUntracked(repositoryRoot, relativePath, environment = {}) {
  const argumentsList = ["--literal-pathspecs", "ls-files", "-z", "--others", "--exclude-standard", "--", relativePath];
  const result = executeGit(repositoryRoot, argumentsList, environment);
  if (result.status !== 0) {
    throw new GitCommandError(argumentsList, result);
  }
  return result.stdout.length > 0;
}

function rejectCachedRename(repositoryRoot, relativePath, environment = {}) {
  const summary = executeGitChecked(repositoryRoot, ["diff", "--cached", "--find-renames", "--name-status", "-z", "--no-ext-diff", "--no-textconv"], environment);
  const fields = summary.toString("utf8").split("\0");
  for (let fieldIndex = 0; fieldIndex < fields.length; fieldIndex += 1) {
    const status = fields[fieldIndex];
    if (!status) {
      continue;
    }
    if (status.startsWith("R") || status.startsWith("C")) {
      const oldPath = fields[fieldIndex + 1];
      const newPath = fields[fieldIndex + 2];
      if (oldPath === relativePath || newPath === relativePath) {
        throw new SpecialGitCaseError("the selected path is part of an already staged rename/copy; handle that rename explicitly");
      }
      fieldIndex += 2;
    } else {
      fieldIndex += 1;
    }
  }
}

export function getWorkingTreeDiff(repositoryRoot, relativePath, environment = {}) {
  return executeGitChecked(repositoryRoot, [
    "--literal-pathspecs", "diff", "--no-ext-diff", "--no-textconv", "--no-renames",
    "--no-indent-heuristic", "--diff-algorithm=myers", "--binary", "--full-index",
    "--src-prefix=a/", "--dst-prefix=b/", "--unified=0", "--no-color", "--", relativePath,
  ], environment);
}

function getDiffForPath(repositoryRoot, absolutePath, relativePath, environment = {}) {
  if (pathIsTracked(repositoryRoot, relativePath, environment)) {
    const diffBytes = getWorkingTreeDiff(repositoryRoot, relativePath, environment);
    if (diffBytes.length === 0) {
      throw new UserInputError("the path has no unstaged working-tree changes");
    }
    return diffBytes;
  }
  if (pathIsUntracked(repositoryRoot, relativePath, environment)) {
    throw new UserInputError("untracked paths must be prepared with intent-to-add first");
  }
  if (existsSync(absolutePath)) {
    const ignoredResult = executeGit(repositoryRoot, ["--literal-pathspecs", "check-ignore", "--quiet", "--", relativePath], environment);
    if (ignoredResult.status === 0) {
      throw new UserInputError("the path is ignored and is not a stage candidate");
    }
  }
  throw new UserInputError("the path is neither tracked with unstaged changes nor an untracked file");
}

function rejectUnsupportedDiff(diffBytes) {
  const diffSections = diffBytes.toString("binary").split("\n").filter((line) => line.startsWith("diff --git "));
  if (diffSections.length !== 1) {
    throw new UserInputError("the path did not resolve to exactly one file diff");
  }
  if (diffBytes.includes(Buffer.from("diff --cc ")) || diffBytes.includes(Buffer.from("diff --combined "))) {
    throw new SpecialGitCaseError("combined conflict diffs are not supported");
  }
  const unsupportedMarkers = [
    "new file mode 120000", "deleted file mode 120000", "rename from ", "rename to ", "copy from ",
    "copy to ", "similarity index ", "old mode ", "new mode ", "Binary files ", "GIT binary patch",
  ];
  for (const line of diffBytes.toString("binary").split("\n")) {
    if (unsupportedMarkers.some((marker) => line.startsWith(marker))) {
      throw new SpecialGitCaseError("rename, copy, binary, submodule, and mode-only changes are not supported");
    }
  }
}

function splitBufferLines(buffer) {
  const lines = [];
  let startIndex = 0;
  while (startIndex < buffer.length) {
    const newlineIndex = buffer.indexOf(0x0a, startIndex);
    if (newlineIndex < 0) {
      lines.push(buffer.subarray(startIndex));
      break;
    }
    lines.push(buffer.subarray(startIndex, newlineIndex + 1));
    startIndex = newlineIndex + 1;
  }
  return lines;
}

function bufferStartsWith(buffer, text) {
  return buffer.subarray(0, text.length).equals(Buffer.from(text, "ascii"));
}

export class DiffHunk {
  constructor(number, rawPatch, addedLineNumbers, deletedLineNumbers) {
    this.number = number;
    this.rawPatch = rawPatch;
    this.addedLineNumbers = addedLineNumbers;
    this.deletedLineNumbers = deletedLineNumbers;
    this.changedLineNumbers = addedLineNumbers.length > 0 ? addedLineNumbers : deletedLineNumbers;
    this.addressKind = addedLineNumbers.length > 0 ? "L" : "D";
  }

  firstChangedLine() {
    return Math.min(...this.changedLineNumbers);
  }

  lastChangedLine() {
    return Math.max(...this.changedLineNumbers);
  }

  displayLabel() {
    const formatLineRange = (lineNumbers) => {
      const firstLine = Math.min(...lineNumbers);
      const lastLine = Math.max(...lineNumbers);
      return firstLine === lastLine ? `${firstLine}` : `${firstLine}-${lastLine}`;
    };
    const addressLabels = [];
    if (this.addedLineNumbers.length > 0) {
      addressLabels.push(`L${formatLineRange(this.addedLineNumbers)}`);
    }
    if (this.deletedLineNumbers.length > 0) {
      addressLabels.push(`D${formatLineRange(this.deletedLineNumbers)}`);
    }
    return `${addressLabels.join("/")} (+${this.addedLineNumbers.length}/-${this.deletedLineNumbers.length})`;
  }
}

export function parseHunks(diffBytes) {
  rejectUnsupportedDiff(diffBytes);
  const diffLines = splitBufferLines(diffBytes);
  const hunkIndexes = diffLines.map((line, index) => bufferStartsWith(line, "@@ ") ? index : -1).filter((index) => index >= 0);
  if (hunkIndexes.length === 0) {
    throw new SpecialGitCaseError("the diff has no selectable text hunk");
  }
  const prefix = Buffer.concat(diffLines.slice(0, hunkIndexes[0]));
  const hunks = [];
  for (let hunkIndex = 0; hunkIndex < hunkIndexes.length; hunkIndex += 1) {
    const startIndex = hunkIndexes[hunkIndex];
    const endIndex = hunkIndex + 1 < hunkIndexes.length ? hunkIndexes[hunkIndex + 1] : diffLines.length;
    const hunkLines = diffLines.slice(startIndex, endIndex);
    const headerMatch = HUNK_HEADER_PATTERN.exec(hunkLines[0].toString("ascii"));
    if (!headerMatch) {
      throw new SpecialGitCaseError("unrecognized unified diff hunk header");
    }
    const oldStart = Number(headerMatch[1]);
    const oldCount = Number(headerMatch[2] ?? "1");
    const newStart = Number(headerMatch[3]);
    const newCount = Number(headerMatch[4] ?? "1");
    let oldLineNumber = oldStart;
    let newLineNumber = newStart;
    const addedLineNumbers = [];
    const deletedLineNumbers = [];
    let consumedOldLines = 0;
    let consumedNewLines = 0;
    for (const contentLine of hunkLines.slice(1)) {
      if (contentLine[0] === 0x5c) {
        continue;
      }
      if (contentLine.length === 0) {
        throw new SpecialGitCaseError("diff hunk contains an empty malformed line");
      }
      const lineMarker = contentLine[0];
      if (lineMarker === 0x20) {
        oldLineNumber += 1;
        newLineNumber += 1;
        consumedOldLines += 1;
        consumedNewLines += 1;
      } else if (lineMarker === 0x2d) {
        deletedLineNumbers.push(oldLineNumber);
        oldLineNumber += 1;
        consumedOldLines += 1;
      } else if (lineMarker === 0x2b) {
        addedLineNumbers.push(newLineNumber);
        newLineNumber += 1;
        consumedNewLines += 1;
      } else {
        throw new SpecialGitCaseError("diff hunk contains an unsupported line marker");
      }
    }
    if (consumedOldLines !== oldCount || consumedNewLines !== newCount) {
      throw new SpecialGitCaseError("diff hunk line counts do not match its header");
    }
    if (addedLineNumbers.length > 0 || deletedLineNumbers.length > 0) {
      hunks.push(new DiffHunk(hunkIndex + 1, Buffer.concat(hunkLines), addedLineNumbers, deletedLineNumbers));
    } else {
      throw new SpecialGitCaseError("diff hunk has no changed lines");
    }
  }
  return { prefix, hunks };
}

export function parseLineRanges(rangeText) {
  if (!rangeText) {
    throw new UserInputError("a non-empty line range is required");
  }
  const parsedRanges = [];
  for (const rawToken of rangeText.split(",")) {
    const token = rawToken.trim();
    const match = RANGE_TOKEN_PATTERN.exec(token);
    if (!match) {
      throw new UserInputError(`invalid line range token: ${JSON.stringify(rawToken)}`);
    }
    const firstLine = Number(match[1]);
    const lastLine = Number(match[2] ?? match[1]);
    if (!Number.isSafeInteger(firstLine) || !Number.isSafeInteger(lastLine) || firstLine < 1 || lastLine < firstLine) {
      throw new UserInputError(`invalid line range token: ${JSON.stringify(rawToken)}`);
    }
    parsedRanges.push([firstLine, lastLine]);
  }
  parsedRanges.sort((left, right) => left[0] - right[0]);
  const mergedRanges = [];
  for (const currentRange of parsedRanges) {
    const previousRange = mergedRanges.at(-1);
    if (!previousRange || currentRange[0] > previousRange[1] + 1) {
      mergedRanges.push(currentRange);
      continue;
    }
    previousRange[1] = Math.max(previousRange[1], currentRange[1]);
  }
  return mergedRanges;
}

function lineIsInRanges(lineNumber, ranges) {
  return ranges.some(([firstLine, lastLine]) => firstLine <= lineNumber && lineNumber <= lastLine);
}

export function selectHunksByRanges(hunks, ranges) {
  const selectedHunks = [];
  for (const hunk of hunks) {
    const anyLineOverlaps = hunk.changedLineNumbers.some((lineNumber) => lineIsInRanges(lineNumber, ranges));
    if (hunk.addressKind === "D") {
      if (anyLineOverlaps) {
        throw new UserInputError(`deletion change ${hunk.number} (${hunk.displayLabel()}) requires explicit --changes selection`);
      }
      continue;
    }
    const allLinesAreContained = hunk.changedLineNumbers.every((lineNumber) => lineIsInRanges(lineNumber, ranges));
    if (anyLineOverlaps && !allLinesAreContained) {
      throw new UserInputError(`line range cuts through change ${hunk.number} (${hunk.displayLabel()}); select the complete hunk`);
    }
    if (allLinesAreContained) {
      selectedHunks.push(hunk);
    }
  }
  if (selectedHunks.length === 0) {
    throw new UserInputError("the requested line range contains no complete changed hunk");
  }
  return selectedHunks;
}

export function parseChangeNumbers(changeText, hunkCount) {
  if (!changeText) {
    throw new UserInputError("--changes requires at least one change number");
  }
  const changeNumbers = [];
  for (const rawToken of changeText.split(",")) {
    const token = rawToken.trim();
    if (!/^\d+$/.test(token) || Number(token) < 1) {
      throw new UserInputError(`invalid change number: ${JSON.stringify(rawToken)}`);
    }
    const changeNumber = Number(token);
    if (!Number.isSafeInteger(changeNumber) || changeNumber > hunkCount) {
      throw new UserInputError(`change ${changeNumber} is outside the available range 1-${hunkCount}`);
    }
    if (changeNumbers.includes(changeNumber)) {
      throw new UserInputError("--changes must not contain duplicate numbers");
    }
    changeNumbers.push(changeNumber);
  }
  return changeNumbers.sort((left, right) => left - right);
}

function buildSelectedPatch(prefix, hunks) {
  return Buffer.concat([prefix, ...hunks.map((hunk) => hunk.rawPatch)]);
}

export function getIndexPath(repositoryRoot, environment = {}) {
  let indexPath = decodeBytes(executeGitChecked(repositoryRoot, ["rev-parse", "--git-path", "index"], environment)).trim();
  if (!isAbsolute(indexPath)) {
    indexPath = resolve(repositoryRoot, indexPath);
  }
  return resolve(indexPath);
}

export function getIndexFingerprint(repositoryRoot, environment = {}) {
  const indexPath = getIndexPath(repositoryRoot, environment);
  if (!existsSync(indexPath)) {
    return null;
  }
  return createHash("sha256").update(readFileSync(indexPath)).digest("hex");
}

function createTemporaryIndex(repositoryRoot, environment = {}) {
  const actualIndexPath = getIndexPath(repositoryRoot, environment);
  const temporaryDirectory = mkdtempSync(join(dirname(actualIndexPath), "git-stage-lines-index-"));
  const temporaryIndexPath = join(temporaryDirectory, "index");
  if (existsSync(actualIndexPath)) {
    copyFileSync(actualIndexPath, temporaryIndexPath);
  }
  return {
    environment: { GIT_INDEX_FILE: temporaryIndexPath },
    cleanup() {
      rmSync(temporaryDirectory, { recursive: true, force: true });
    },
  };
}

function prepareUntrackedPath(repositoryRoot, absolutePath, relativePath, environment = {}) {
  if (!pathIsUntracked(repositoryRoot, relativePath, environment)) {
    return null;
  }
  try {
    if (lstatSync(absolutePath).isSymbolicLink()) {
      throw new SpecialGitCaseError("symbolic-link new files are not supported");
    }
  } catch (error) {
    if (error instanceof SpecialGitCaseError || error?.code !== "ENOENT") {
      throw error;
    }
  }
  const temporaryIndex = createTemporaryIndex(repositoryRoot, environment);
  try {
    executeGitChecked(repositoryRoot, ["--literal-pathspecs", "add", "--intent-to-add", "--", relativePath], temporaryIndex.environment);
  } catch (error) {
    temporaryIndex.cleanup();
    throw error;
  }
  return temporaryIndex;
}

function getCachedDiff(repositoryRoot, relativePath, environment = {}) {
  return executeGitChecked(repositoryRoot, [
    "--literal-pathspecs", "diff", "--cached", "--no-ext-diff", "--no-textconv", "--no-renames",
    "--binary", "--full-index", "--no-color", "--", relativePath,
  ], environment);
}

function assertWorkingTreeDiffUnchanged(repositoryRoot, relativePath, expectedDiff, environment = {}) {
  const currentDiff = getWorkingTreeDiff(repositoryRoot, relativePath, environment);
  if (!currentDiff.equals(expectedDiff)) {
    throw new SafetyError("the working-tree diff changed after selection; refusing to stage a stale patch");
  }
}

function getWorkingTreeState(absolutePath) {
  try {
    const fileStatus = lstatSync(absolutePath);
    if (fileStatus.isSymbolicLink()) {
      return { kind: "symlink", target: readlinkSync(absolutePath) };
    }
    if (!fileStatus.isFile()) {
      return { kind: "other", mode: fileStatus.mode };
    }
    return { kind: "file", mode: fileStatus.mode, content: readFileSync(absolutePath) };
  } catch (error) {
    if (error?.code === "ENOENT") {
      return { kind: "missing" };
    }
    throw error;
  }
}

function workingTreeStatesEqual(leftState, rightState) {
  if (leftState.kind !== rightState.kind) {
    return false;
  }
  if (leftState.kind === "file") {
    return leftState.mode === rightState.mode && leftState.content.equals(rightState.content);
  }
  if (leftState.kind === "symlink") {
    return leftState.target === rightState.target;
  }
  if (leftState.kind === "other") {
    return leftState.mode === rightState.mode;
  }
  return true;
}

function checkPatchAgainstIndex(repositoryRoot, patchBytes, environment = {}) {
  const result = executeGit(repositoryRoot, CHECK_PATCH_ARGUMENTS, environment, patchBytes);
  if (result.status !== 0) {
    throw new GitCommandError(CHECK_PATCH_ARGUMENTS, result);
  }
}

export function applyPatchSafely(repositoryRoot, absolutePath, relativePath, patchBytes, expectedWorkingTreeDiff, diffEnvironment = {}, actualEnvironment = {}) {
  const initialIndexFingerprint = getIndexFingerprint(repositoryRoot, actualEnvironment);
  assertWorkingTreeDiffUnchanged(repositoryRoot, relativePath, expectedWorkingTreeDiff, diffEnvironment);
  const workingTreeStateBeforeApply = getWorkingTreeState(absolutePath);
  checkPatchAgainstIndex(repositoryRoot, patchBytes, actualEnvironment);
  if (getIndexFingerprint(repositoryRoot, actualEnvironment) !== initialIndexFingerprint) {
    throw new SafetyError("the Git index changed during patch validation");
  }
  assertWorkingTreeDiffUnchanged(repositoryRoot, relativePath, expectedWorkingTreeDiff, diffEnvironment);
  const applyResult = executeGit(repositoryRoot, APPLY_PATCH_ARGUMENTS, actualEnvironment, patchBytes);
  if (applyResult.status !== 0) {
    if (getIndexFingerprint(repositoryRoot, actualEnvironment) !== initialIndexFingerprint) {
      throw new SafetyError("Git apply failed after changing the index");
    }
    throw new GitCommandError(APPLY_PATCH_ARGUMENTS, applyResult);
  }
  if (!workingTreeStatesEqual(workingTreeStateBeforeApply, getWorkingTreeState(absolutePath))) {
    throw new SafetyError("the working-tree file changed while applying the patch");
  }
  return getCachedDiff(repositoryRoot, relativePath, actualEnvironment);
}

function validateDryRun(repositoryRoot, relativePath, patchBytes, expectedWorkingTreeDiff, diffEnvironment = {}, actualEnvironment = {}) {
  const initialIndexFingerprint = getIndexFingerprint(repositoryRoot, actualEnvironment);
  assertWorkingTreeDiffUnchanged(repositoryRoot, relativePath, expectedWorkingTreeDiff, diffEnvironment);
  checkPatchAgainstIndex(repositoryRoot, patchBytes, actualEnvironment);
  if (getIndexFingerprint(repositoryRoot, actualEnvironment) !== initialIndexFingerprint) {
    throw new SafetyError("the Git index changed during dry-run validation");
  }
  assertWorkingTreeDiffUnchanged(repositoryRoot, relativePath, expectedWorkingTreeDiff, diffEnvironment);
}

function showHelp() {
  process.stdout.write([
    "Usage: git-stage-lines [options] [--] PATH [LINE-RANGES]", "", "Options:",
    "  --list                 list selectable diff hunks",
    "  --dry-run              print the checked patch without applying it",
    "  --changes NUMBERS      hunk numbers from --list; requires --fingerprint",
    "  --fingerprint HASH     require the --list diff fingerprint to match",
    "  -h, --help             show this help", "",
    "Line ranges use forms such as 42,45-48,57. Deletion hunks require --changes.",
    "Exit codes: 0 success, 1 internal error, 2 invalid request, 3 unsupported target/runtime, 4 safety check failure, 5 Git failure.",
  ].join("\n") + "\n");
}

function parseArguments(argumentsList) {
  const parsed = { list: false, dryRun: false, changes: undefined, fingerprint: undefined, path: undefined, lineRanges: undefined, help: false };
  let optionsEnded = false;
  const positionalArguments = [];
  for (let argumentIndex = 0; argumentIndex < argumentsList.length; argumentIndex += 1) {
    const argument = argumentsList[argumentIndex];
    if (!optionsEnded && argument === "--") {
      optionsEnded = true;
      continue;
    }
    if (!optionsEnded && (argument === "-h" || argument === "--help")) {
      parsed.help = true;
      continue;
    }
    if (!optionsEnded && (argument === "--list" || argument === "--dry-run")) {
      parsed[argument === "--list" ? "list" : "dryRun"] = true;
      continue;
    }
    if (!optionsEnded && (argument === "--changes" || argument === "--fingerprint")) {
      if (argumentIndex + 1 >= argumentsList.length) {
        throw new UserInputError(`${argument} requires a value`);
      }
      parsed[argument === "--changes" ? "changes" : "fingerprint"] = argumentsList[++argumentIndex];
      continue;
    }
    if (!optionsEnded && argument.startsWith("--changes=")) {
      parsed.changes = argument.slice("--changes=".length);
      continue;
    }
    if (!optionsEnded && argument.startsWith("--fingerprint=")) {
      parsed.fingerprint = argument.slice("--fingerprint=".length);
      continue;
    }
    if (!optionsEnded && argument.startsWith("-")) {
      throw new UserInputError(`unknown option: ${argument}`);
    }
    positionalArguments.push(argument);
  }
  if (positionalArguments.length > 0) {
    parsed.path = positionalArguments[0];
  }
  if (positionalArguments.length > 1) {
    parsed.lineRanges = positionalArguments[1];
  }
  if (positionalArguments.length > 2) {
    throw new UserInputError("only one path and one line range may be provided");
  }
  return parsed;
}

function assertNodeVersion() {
  const [major] = process.versions.node.split(".").map(Number);
  if (major < 20) {
    throw new SpecialGitCaseError(`Node.js 20 or newer is required (found ${process.versions.node})`);
  }
}

export function runCli(argumentsList = process.argv.slice(2)) {
  assertNodeVersion();
  const parsedArguments = parseArguments(argumentsList);
  if (parsedArguments.help) {
    showHelp();
    return 0;
  }
  if (parsedArguments.list && parsedArguments.dryRun) {
    throw new UserInputError("--list and --dry-run cannot be combined");
  }
  if (parsedArguments.list && (parsedArguments.changes !== undefined || parsedArguments.lineRanges !== undefined)) {
    throw new UserInputError("--list does not take a selection");
  }
  if (parsedArguments.changes !== undefined && parsedArguments.lineRanges !== undefined) {
    throw new UserInputError("use either a line range or --changes, not both");
  }
  if (parsedArguments.changes !== undefined && parsedArguments.fingerprint === undefined) {
    throw new UserInputError("--changes requires --fingerprint from the preceding --list output");
  }
  if (parsedArguments.fingerprint !== undefined && !/^[0-9a-f]{64}$/.test(parsedArguments.fingerprint)) {
    throw new UserInputError("--fingerprint must be a 64-character lowercase hexadecimal hash");
  }
  if (!parsedArguments.list && parsedArguments.changes === undefined && parsedArguments.lineRanges === undefined) {
    throw new UserInputError("a line range or --changes is required");
  }
  if (!parsedArguments.path) {
    throw new UserInputError("a file path is required");
  }
  const repositoryRoot = findRepositoryRoot();
  const actualEnvironment = {};
  rejectUnmergedRepositoryState(repositoryRoot, actualEnvironment);
  const { absolutePath, relativePath } = normalizeRepositoryPath(repositoryRoot, parsedArguments.path);
  rejectCachedRename(repositoryRoot, relativePath, actualEnvironment);
  const temporaryIndex = prepareUntrackedPath(repositoryRoot, absolutePath, relativePath, actualEnvironment);
  const diffEnvironment = temporaryIndex?.environment ?? actualEnvironment;
  try {
    const diffBytes = getDiffForPath(repositoryRoot, absolutePath, relativePath, diffEnvironment);
    const diffFingerprint = createHash("sha256").update(diffBytes).digest("hex");
    const { prefix, hunks } = parseHunks(diffBytes);
    if (parsedArguments.list) {
      for (const hunk of hunks) {
        process.stdout.write(`${hunk.number} ${hunk.displayLabel()}\n`);
      }
      process.stderr.write(`git-stage-lines: diff-fingerprint=${diffFingerprint}\n`);
      return 0;
    }
    if (parsedArguments.fingerprint !== undefined && parsedArguments.fingerprint !== diffFingerprint) {
      throw new SafetyError("the diff fingerprint changed after --list; refusing to select stale changes");
    }
    let selectedHunks;
    if (parsedArguments.changes !== undefined) {
      const selectedNumbers = parseChangeNumbers(parsedArguments.changes, hunks.length);
      selectedHunks = hunks.filter((hunk) => selectedNumbers.includes(hunk.number));
    } else {
      selectedHunks = selectHunksByRanges(hunks, parseLineRanges(parsedArguments.lineRanges));
    }
    const patchBytes = buildSelectedPatch(prefix, selectedHunks);
    if (parsedArguments.dryRun) {
      validateDryRun(repositoryRoot, relativePath, patchBytes, diffBytes, diffEnvironment, actualEnvironment);
      process.stdout.write(patchBytes);
      return 0;
    }
    const finalCachedDiff = applyPatchSafely(repositoryRoot, absolutePath, relativePath, patchBytes, diffBytes, diffEnvironment, actualEnvironment);
    process.stdout.write(finalCachedDiff);
    return 0;
  } finally {
    temporaryIndex?.cleanup();
  }
}

export function main(argumentsList = process.argv.slice(2)) {
  try {
    return runCli(argumentsList);
  } catch (error) {
    if (error instanceof UserInputError) {
      console.error(`git-stage-lines: error: ${error.message}`);
      return 2;
    }
    if (error instanceof SpecialGitCaseError) {
      console.error(`git-stage-lines: unsupported: ${error.message}`);
      return 3;
    }
    if (error instanceof SafetyError) {
      console.error(`git-stage-lines: safety error: ${error.message}`);
      return 4;
    }
    if (error instanceof GitCommandError) {
      console.error(`git-stage-lines: git error: ${error.message}`);
      return 5;
    }
    console.error(`git-stage-lines: internal error: ${error instanceof Error ? error.message : String(error)}`);
    return 1;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main();
}
