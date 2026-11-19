import { strict as assert } from 'node:assert';
import { cpSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { evaluationAggregate, main, validateManifestFile } from '../validate.mjs';

const TEST_DIR = dirname(fileURLToPath(import.meta.url));
const EVALUATION_DIR = resolve(TEST_DIR, '..');
const SOURCE_FIXTURE_DIR = join(EVALUATION_DIR, 'fixtures');
const SOURCE_MANIFEST = join(SOURCE_FIXTURE_DIR, 'manifest.json');

function readJson(filePath) {
  return JSON.parse(readFileSync(filePath, 'utf8'));
}

function writeJson(filePath, value) {
  writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function copyFixtureTree() {
  const tempRoot = mkdtempSync(join('/tmp', 'issue6-evaluation-'));
  const fixtureRoot = join(tempRoot, 'fixtures');
  cpSync(SOURCE_FIXTURE_DIR, fixtureRoot, { recursive: true });
  cpSync(join(EVALUATION_DIR, 'schema'), join(tempRoot, 'schema'), { recursive: true });
  return { tempRoot, manifestPath: join(fixtureRoot, 'manifest.json'), fixtureRoot };
}

for (const schemaName of ['manifest.schema.json', 'result.schema.json', 'dispatch-receipt.schema.json', 'joint-record.schema.json']) {
  const schema = readJson(join(EVALUATION_DIR, 'schema', schemaName));
  assert.equal(schema.$schema, 'https://json-schema.org/draft/2020-12/schema');
  assert.ok(Array.isArray(schema.required) && schema.required.length > 0, `${schemaName}: required fields are missing`);
}

function assertBlockedAfterMutation(mutate, label) {
  const copy = copyFixtureTree();
  try {
    mutate(copy);
    const report = validateManifestFile(copy.manifestPath);
    assert.equal(report.status, 'BLOCKED', `${label}: invalid fixture was accepted`);
    assert.ok(report.errors.length > 0, `${label}: no blocking reason was recorded`);
  } finally {
    rmSync(copy.tempRoot, { recursive: true, force: true });
  }
}

const baselineReport = validateManifestFile(SOURCE_MANIFEST);
assert.equal(baselineReport.status, 'PASS');
assert.deepEqual(baselineReport.io_errors, []);
assert.equal(baselineReport.cases.length, 6);
assert.ok(baselineReport.cases.every((item) => item.status === 'PASS'));
assert.equal(baselineReport.warnings.length, 3);
assert.ok(baselineReport.cases.every((item) => item.observations?.baseline && item.observations?.candidate));
assert.equal(baselineReport.cases.find((item) => item.case_id === 'zero-findings').observations.candidate.cost.dispatch_count, 0);
assert.match(evaluationAggregate(), /^[0-9a-f]{64}$/);

{
  const copy = copyFixtureTree();
  try {
    rmSync(copy.manifestPath);
    assert.equal(main(['--manifest', copy.manifestPath, '--quiet']), 64);
  } finally {
    rmSync(copy.tempRoot, { recursive: true, force: true });
  }
}

{
  const copy = copyFixtureTree();
  try {
    writeFileSync(copy.manifestPath, '{ malformed manifest\n', 'utf8');
    assert.equal(main(['--manifest', copy.manifestPath, '--quiet']), 2);
  } finally {
    rmSync(copy.tempRoot, { recursive: true, force: true });
  }
}

assertBlockedAfterMutation(({ fixtureRoot }) => {
  const resultPath = join(fixtureRoot, 'results', 'high-critical-findings.candidate.json');
  const result = readJson(resultPath);
  result.propositions[0].discovery = 'MISSED';
  writeJson(resultPath, result);
}, 'high/critical discovery regression');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  const resultPath = join(fixtureRoot, 'results', 'unresolved-evidence.candidate.json');
  const result = readJson(resultPath);
  result.gate_status = 'PASS';
  result.role_context.reviewer_approved = true;
  result.role_context.respondent_approved = true;
  writeJson(resultPath, result);
}, 'unresolved evidence bypass');

assertBlockedAfterMutation(({ manifestPath }) => {
  const manifest = readJson(manifestPath);
  manifest.runtime_dispatch_enforcement_claimed = true;
  writeJson(manifestPath, manifest);
}, 'runtime enforcement claim');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  const receiptPath = join(fixtureRoot, 'receipts', 'zero-findings.candidate.json');
  const receipt = readJson(receiptPath);
  receipt.dispatch_count = 1;
  writeJson(receiptPath, receipt);
}, 'receipt mismatch');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  const resultPath = join(fixtureRoot, 'results', 'unresolved-evidence.candidate.json');
  const result = readJson(resultPath);
  result.escalation_trace = ['respondent', 'reviewer', 'evidence_reacquisition'];
  writeJson(resultPath, result);
}, 'escalation order');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  const resultPath = join(fixtureRoot, 'results', 'unresolved-evidence.candidate.json');
  const result = readJson(resultPath);
  result.escalation_step = 'respondent';
  result.escalation_trace = ['eligibility', 'respondent'];
  writeJson(resultPath, result);
}, 'escalation missing prefix');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  const resultPath = join(fixtureRoot, 'results', 'high-critical-findings.candidate.json');
  writeFileSync(resultPath, '{ malformed result\n', 'utf8');
}, 'malformed result');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  rmSync(join(fixtureRoot, 'receipts', 'high-critical-findings.candidate.json'));
}, 'missing receipt');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  const resultPath = join(fixtureRoot, 'results', 'high-critical-findings.candidate.json');
  const result = readJson(resultPath);
  result.packet_sha256 = '0'.repeat(64);
  writeJson(resultPath, result);
}, 'packet hash mismatch');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  const packetPath = join(fixtureRoot, 'packets', 'high-critical-findings.json');
  const packet = readJson(packetPath);
  packet.fixture_manifest_sha256 = '0'.repeat(64);
  writeJson(packetPath, packet);
}, 'packet fixture identity mismatch');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  const resultPath = join(fixtureRoot, 'results', 'high-critical-findings.candidate.json');
  const result = readJson(resultPath);
  result.epoch_hash = '0'.repeat(64);
  writeJson(resultPath, result);
}, 'epoch mismatch');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  const resultPath = join(fixtureRoot, 'results', 'high-critical-findings.candidate.json');
  const result = readJson(resultPath);
  result.propositions.push({ ...result.propositions[0] });
  writeJson(resultPath, result);
}, 'duplicate proposition');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  const resultPath = join(fixtureRoot, 'results', 'high-critical-findings.candidate.json');
  const result = readJson(resultPath);
  result.propositions.push({
    proposition_id: 'unknown-001',
    severity: 'low',
    discovery: 'FOUND',
    rejection: 'NOT_APPLICABLE',
  });
  writeJson(resultPath, result);
}, 'unknown proposition');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  const resultPath = join(fixtureRoot, 'results', 'zero-findings.candidate.json');
  const result = readJson(resultPath);
  delete result.role_context.reviewer_approved;
  writeJson(resultPath, result);
}, 'missing approval field');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  const resultPath = join(fixtureRoot, 'results', 'zero-findings.candidate.json');
  const result = readJson(resultPath);
  result.finding_count = 1;
  writeJson(resultPath, result);
}, 'zero finding count mismatch');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  const resultPath = join(fixtureRoot, 'results', 'zero-findings.candidate.json');
  const result = readJson(resultPath);
  result.role_context.joint_record_version = 'joint-zero-v2';
  writeJson(resultPath, result);
}, 'joint record version mismatch');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  const recordPath = join(fixtureRoot, 'records', 'zero-findings.candidate.json');
  const record = readJson(recordPath);
  record.respondent.approved = false;
  writeJson(recordPath, record);
}, 'joint record approval');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  const recordPath = join(fixtureRoot, 'records', 'zero-findings.candidate.json');
  const record = readJson(recordPath);
  record.fixture_manifest_sha256 = '0'.repeat(64);
  writeJson(recordPath, record);
}, 'joint record fixture identity mismatch');

assertBlockedAfterMutation(({ manifestPath }) => {
  const manifest = readJson(manifestPath);
  manifest.cases[0].expected_status = 'BLOCKED';
  writeJson(manifestPath, manifest);
}, 'case expected status mismatch');

assertBlockedAfterMutation(({ manifestPath }) => {
  const manifest = readJson(manifestPath);
  manifest.cases = {};
  writeJson(manifestPath, manifest);
}, 'malformed manifest cases type');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  const casePath = join(fixtureRoot, 'cases', 'zero-findings.json');
  const caseFile = readJson(casePath);
  caseFile.propositions = {};
  writeJson(casePath, caseFile);
}, 'malformed case propositions type');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  const resultPath = join(fixtureRoot, 'results', 'high-critical-findings.candidate.json');
  const result = readJson(resultPath);
  result.propositions = {};
  writeJson(resultPath, result);
}, 'malformed result propositions type');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  const casePath = join(fixtureRoot, 'cases', 'high-critical-findings.json');
  const caseFile = readJson(casePath);
  caseFile.propositions[0] = null;
  writeJson(casePath, caseFile);
}, 'null case proposition');

assertBlockedAfterMutation(({ fixtureRoot }) => {
  writeFileSync(join(fixtureRoot, 'cases', 'zero-findings.json'), 'null\n', 'utf8');
}, 'null case');

for (const schemaName of ['manifest.schema.json', 'case.schema.json', 'packet.schema.json', 'result.schema.json', 'dispatch-receipt.schema.json', 'joint-record.schema.json']) {
  assertBlockedAfterMutation(({ tempRoot }) => {
    writeFileSync(join(tempRoot, 'schema', schemaName), 'null\n', 'utf8');
  }, `null ${schemaName}`);

  assertBlockedAfterMutation(({ tempRoot }) => {
    writeFileSync(join(tempRoot, 'schema', schemaName), '{}\n', 'utf8');
  }, `weakened ${schemaName}`);
}

if (process.platform !== 'win32') {
  assertBlockedAfterMutation(({ tempRoot, fixtureRoot }) => {
    const outsidePath = join(tempRoot, 'outside-case.json');
    const sourceCasePath = join(SOURCE_FIXTURE_DIR, 'cases', 'zero-findings.json');
    writeFileSync(outsidePath, readFileSync(sourceCasePath));
    const casePath = join(fixtureRoot, 'cases', 'zero-findings.json');
    rmSync(casePath);
    symlinkSync(outsidePath, casePath);
  }, 'symlink escape');

  const outsideRoot = mkdtempSync(join('/tmp', 'issue6-schema-outside-'));
  try {
    assertBlockedAfterMutation(({ tempRoot }) => {
      const outsideSchemaPath = join(outsideRoot, 'result.schema.json');
      cpSync(join(EVALUATION_DIR, 'schema', 'result.schema.json'), outsideSchemaPath);
      const schemaPath = join(tempRoot, 'schema', 'result.schema.json');
      rmSync(schemaPath);
      symlinkSync(outsideSchemaPath, schemaPath);
    }, 'schema symlink escape');
  } finally {
    rmSync(outsideRoot, { recursive: true, force: true });
  }
}

console.log('Issue #6 evaluation validator tests passed.');
