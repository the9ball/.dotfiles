import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, realpathSync, statSync } from 'node:fs';
import { dirname, isAbsolute, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const DEFAULT_MANIFEST = resolve(SCRIPT_DIR, 'fixtures', 'manifest.json');
const SHA256 = /^[0-9a-f]{64}$/;
const COMMIT = /^[0-9a-f]{40}$/;
const SEVERITIES = new Set(['critical', 'high', 'medium', 'low']);
const DISCOVERY = new Set(['FOUND', 'MISSED', 'NOT_APPLICABLE']);
const REJECTION = new Set(['REJECTED', 'RETAINED', 'NOT_APPLICABLE']);
const ESCALATION_STEPS = new Set([
  'none',
  'eligibility',
  'reviewer',
  'respondent',
  'evidence_reacquisition',
  'neutral_adviser',
]);
const ESCALATION_ORDER = ['eligibility', 'reviewer', 'respondent', 'evidence_reacquisition', 'neutral_adviser'];
const EXACT_PAIR_FIELDS = [
  'gate_status',
  'evidence_status',
  'coverage_status',
  'deterministic_checks',
  'proceed_status',
];
const SCHEMA_SHA256 = {
  'manifest.schema.json': 'f880b772f829b7337170f78fafe85d216cdf5fdd12e577aa6bf88e0a1d1b453f',
  'case.schema.json': '5bda8c607e6d989c478fa5bd64196a958cb699e02262e3cd52ef0fe1f0edc877',
  'packet.schema.json': '50a05617e560a5b8be29f7024f6c3d51ca38cea61d2eb488857b1d1ad23c197a',
  'result.schema.json': 'f6541b45e3823fd38c82e20b8ed64cc91941a8abe970ead59ae9e22fcedd0123',
  'dispatch-receipt.schema.json': '3dde67b811620aae21e94a46033a6324877a39996e656398d14105e3b27f0261',
  'joint-record.schema.json': 'f970425ccd6efe31b46c1d91b6629c5fe8028422c02b6e0fbcd5206bc63e5a22',
};

class UsageError extends Error {}
class ContractError extends Error {}

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function stableStringify(value) {
  if (Array.isArray(value)) return `[${value.map((item) => stableStringify(item)).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

function targetIdentityHash(target) {
  const identityPayload = { repository: target.repository, commit: target.commit, files: target.files };
  return sha256(Buffer.from(stableStringify(identityPayload), 'utf8'));
}

function listFiles(rootDirectory, currentDirectory = rootDirectory) {
  return readdirSync(currentDirectory, { withFileTypes: true }).flatMap((entry) => {
    const path = resolve(currentDirectory, entry.name);
    if (entry.isSymbolicLink()) throw new ContractError(`aggregate に symlink を含められない: ${path}`);
    return entry.isDirectory() ? listFiles(rootDirectory, path) : entry.isFile() ? [path] : [];
  });
}

export function evaluationAggregate(rootDirectory = SCRIPT_DIR) {
  const root = 'agents/skills/rigorous-review/evaluation';
  const files = listFiles(rootDirectory)
    .map((filePath) => ({
      path: `${root}/${relative(rootDirectory, filePath).split('\\').join('/')}`,
      sha256: sha256(readFileSync(filePath)),
      bytes: statSync(filePath).size,
    }))
    .sort((left, right) => (left.path < right.path ? -1 : left.path > right.path ? 1 : 0));
  const payload = { root, files };
  return sha256(Buffer.from(stableStringify(payload), 'utf8'));
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function addError(errors, path, message) {
  errors.push({ path, message });
}

function addWarning(warnings, path, message) {
  warnings.push({ path, message });
}

function readJson(filePath, errors, pathLabel, ioErrors = null) {
  let raw;
  try {
    raw = readFileSync(filePath);
  } catch (error) {
    addError(errors, pathLabel, `読み込みに失敗した: ${error.message}`);
    ioErrors?.push({ path: pathLabel, message: error.message });
    return { value: null, raw: null };
  }
  try {
    return { value: JSON.parse(raw.toString('utf8')), raw };
  } catch (error) {
    addError(errors, pathLabel, `JSON として解釈できない: ${error.message}`);
    return { value: null, raw };
  }
}

function resolveContained(baseDirectory, relativePath, errors, pathLabel, containmentRoot = baseDirectory, ioErrors = null) {
  if (typeof relativePath !== 'string' || relativePath.length === 0) {
    addError(errors, pathLabel, '相対パスが必要である');
    return null;
  }
  if (isAbsolute(relativePath)) {
    addError(errors, pathLabel, '絶対パスは許可しない');
    return null;
  }
  const candidate = resolve(baseDirectory, relativePath);
  const rel = relative(containmentRoot, candidate);
  if (rel === '' || rel === '..' || rel.startsWith(`..${process.platform === 'win32' ? '\\' : '/'}`)) {
    addError(errors, pathLabel, 'fixture ディレクトリの外側を参照している');
    return null;
  }
  try {
    const realRoot = realpathSync(containmentRoot);
    const realCandidate = realpathSync(candidate);
    const realRel = relative(realRoot, realCandidate);
    if (realRel === '' || realRel === '..' || realRel.startsWith(`..${process.platform === 'win32' ? '\\' : '/'}`)) {
      addError(errors, pathLabel, 'symlink の解決後に fixture ディレクトリの外側を参照している');
      return null;
    }
  } catch (error) {
    if (error?.code !== 'ENOENT') {
      addError(errors, pathLabel, `実体パスを検証できない: ${error.message}`);
      ioErrors?.push({ path: pathLabel, message: error.message });
    }
  }
  return candidate;
}

function requireString(object, key, errors, pathLabel, pattern = null) {
  if (typeof object?.[key] !== 'string' || object[key].length === 0) {
    addError(errors, `${pathLabel}.${key}`, '空でない文字列が必要である');
    return false;
  }
  if (pattern && !pattern.test(object[key])) {
    addError(errors, `${pathLabel}.${key}`, '値の形式が不正である');
    return false;
  }
  return true;
}

function requireBoolean(object, key, expected, errors, pathLabel) {
  if (object?.[key] !== expected) {
    addError(errors, `${pathLabel}.${key}`, `${String(expected)} でなければならない`);
    return false;
  }
  return true;
}

function requireEnum(object, key, values, errors, pathLabel) {
  if (!values.has(object?.[key])) {
    addError(errors, `${pathLabel}.${key}`, `許可された値は ${[...values].join(', ')} である`);
    return false;
  }
  return true;
}

function validateSchemaValue(value, schema, errors, label, rootSchema = schema) {
  if (!isObject(schema)) {
    addError(errors, label, 'schema が object でない');
    return;
  }
  if (typeof schema.$ref === 'string') {
    const prefix = '#/$defs/';
    if (!schema.$ref.startsWith(prefix) || !isObject(rootSchema.$defs?.[schema.$ref.slice(prefix.length)])) {
      addError(errors, label, `未解決の schema ref ${schema.$ref}`);
      return;
    }
    validateSchemaValue(value, rootSchema.$defs[schema.$ref.slice(prefix.length)], errors, label, rootSchema);
    return;
  }
  if (schema.const !== undefined && stableStringify(value) !== stableStringify(schema.const)) addError(errors, label, `schema の const ${stableStringify(schema.const)} と一致しない`);
  if (Array.isArray(schema.enum) && !schema.enum.some((item) => stableStringify(item) === stableStringify(value))) addError(errors, label, 'schema の enum に含まれない');
  if (schema.type === 'object') {
    if (!isObject(value)) {
      addError(errors, label, 'schema の object ではない');
      return;
    }
    for (const key of schema.required ?? []) if (!Object.hasOwn(value, key)) addError(errors, `${label}.${key}`, 'schema の required field が欠落している');
    const properties = schema.properties ?? {};
    if (schema.additionalProperties === false) for (const key of Object.keys(value)) if (!Object.hasOwn(properties, key)) addError(errors, `${label}.${key}`, 'schema が許可しない field である');
    for (const [key, propertySchema] of Object.entries(properties)) if (Object.hasOwn(value, key)) validateSchemaValue(value[key], propertySchema, errors, `${label}.${key}`, rootSchema);
  } else if (schema.type === 'array') {
    if (!Array.isArray(value)) {
      addError(errors, label, 'schema の array ではない');
      return;
    }
    if (schema.minItems !== undefined && value.length < schema.minItems) addError(errors, label, `schema の minItems ${schema.minItems} を満たさない`);
    if (schema.items) for (const [index, item] of value.entries()) validateSchemaValue(item, schema.items, errors, `${label}[${index}]`, rootSchema);
  } else if (schema.type === 'string') {
    if (typeof value !== 'string') addError(errors, label, 'schema の string ではない');
    else {
      if (schema.minLength !== undefined && value.length < schema.minLength) addError(errors, label, `schema の minLength ${schema.minLength} を満たさない`);
      if (schema.pattern && !(new RegExp(schema.pattern)).test(value)) addError(errors, label, 'schema の pattern に一致しない');
    }
  } else if (schema.type === 'integer') {
    if (!Number.isInteger(value)) addError(errors, label, 'schema の integer ではない');
    else if (schema.minimum !== undefined && value < schema.minimum) addError(errors, label, `schema の minimum ${schema.minimum} を満たさない`);
  } else if (schema.type === 'boolean') {
    if (typeof value !== 'boolean') addError(errors, label, 'schema の boolean ではない');
  }
}

function validateManifest(manifest, manifestRaw, manifestPath, report, ioErrors = null) {
  const errors = report.errors;
  const pathLabel = 'manifest';
  if (!isObject(manifest)) {
    addError(errors, pathLabel, 'object が必要である');
    return null;
  }
  if (manifest.schema_version !== '1.0') addError(errors, `${pathLabel}.schema_version`, '1.0 でなければならない');
  requireString(manifest, 'manifest_id', errors, pathLabel, /^[a-z0-9][a-z0-9-]+$/);
  if (manifest.harness_mode !== 'fixture_only_observe_only') addError(errors, `${pathLabel}.harness_mode`, 'fixture_only_observe_only でなければならない');
  requireBoolean(manifest, 'default_path_changed', false, errors, pathLabel);
  requireBoolean(manifest, 'runtime_dispatch_attempted', false, errors, pathLabel);
  requireBoolean(manifest, 'runtime_dispatch_enforcement_claimed', false, errors, pathLabel);

  const target = manifest.target;
  if (!isObject(target)) {
    addError(errors, `${pathLabel}.target`, 'object が必要である');
  } else {
    if (target.repository !== 'the9ball/.dotfiles') addError(errors, `${pathLabel}.target.repository`, 'the9ball/.dotfiles でなければならない');
    requireString(target, 'repository', errors, `${pathLabel}.target`);
    requireString(target, 'commit', errors, `${pathLabel}.target`, COMMIT);
    requireString(target, 'identity_hash', errors, `${pathLabel}.target`, SHA256);
    if (!Array.isArray(target.files) || target.files.length === 0) {
      addError(errors, `${pathLabel}.target.files`, '1 件以上の対象ファイルが必要である');
    } else {
      const paths = new Set();
      for (const [index, file] of target.files.entries()) {
        const fileLabel = `${pathLabel}.target.files[${index}]`;
        requireString(file, 'path', errors, fileLabel);
        requireString(file, 'sha256', errors, fileLabel, SHA256);
        if (!Number.isInteger(file?.line_count) || file.line_count < 1) addError(errors, `${fileLabel}.line_count`, '1 以上の整数が必要である');
        if (paths.has(file?.path)) addError(errors, `${fileLabel}.path`, '対象ファイルが重複している');
        paths.add(file?.path);
      }
      if (SHA256.test(target.identity_hash ?? '') && targetIdentityHash(target) !== target.identity_hash) {
        addError(errors, `${pathLabel}.target.identity_hash`, `対象 manifest の計算値 ${targetIdentityHash(target)} と一致しない`);
      }
    }
  }
  requireString(manifest, 'epoch_hash', errors, pathLabel, SHA256);

  const policy = manifest.quality_policy;
  const expectedPolicy = {
    exact_structural_metrics: ['gate', 'evidence', 'coverage', 'deterministic_checks', 'proceed'],
    exact_discovery_severities: ['high', 'critical'],
    informational_severities: ['medium', 'low'],
    informational_metrics: ['discovery', 'rejection'],
    invalid_input_status: 'BLOCKED',
  };
  if (!isObject(policy)) {
    addError(errors, `${pathLabel}.quality_policy`, 'object が必要である');
  } else {
    for (const [key, expected] of Object.entries(expectedPolicy)) {
      if (stableStringify(policy[key]) !== stableStringify(expected)) addError(errors, `${pathLabel}.quality_policy.${key}`, `契約値 ${stableStringify(expected)} が必要である`);
    }
  }

  if (!Array.isArray(manifest.cases) || manifest.cases.length === 0) addError(errors, `${pathLabel}.cases`, '1 件以上の case が必要である');
  const caseIds = new Set();
  const fixtureDirectory = dirname(manifestPath);
  const caseEntries = [];
  const caseList = Array.isArray(manifest.cases) ? manifest.cases : [];
  for (const [index, entry] of caseList.entries()) {
    const entryLabel = `${pathLabel}.cases[${index}]`;
    if (!isObject(entry)) {
      addError(errors, entryLabel, 'object が必要である');
      continue;
    }
    requireString(entry, 'case_id', errors, entryLabel, /^[a-z0-9][a-z0-9-]+$/);
    requireString(entry, 'path', errors, entryLabel, /^cases\/[a-z0-9][a-z0-9-]+\.json$/);
    if (!['PASS', 'BLOCKED'].includes(entry.expected_status)) addError(errors, `${entryLabel}.expected_status`, 'PASS または BLOCKED が必要である');
    if (caseIds.has(entry.case_id)) addError(errors, `${entryLabel}.case_id`, 'case_id が重複している');
    caseIds.add(entry.case_id);
    const casePath = resolveContained(fixtureDirectory, entry.path, errors, `${entryLabel}.path`, fixtureDirectory, ioErrors);
    if (casePath) caseEntries.push({ entry, casePath, entryLabel });
  }
  return { fixtureDirectory, caseEntries, manifestSha256: sha256(manifestRaw) };
}

function loadSchemas(manifestPath, errors, ioErrors = null) {
  const evaluationRoot = resolve(dirname(manifestPath), '..');
  const schemaDirectory = resolveContained(evaluationRoot, 'schema', errors, 'schema', evaluationRoot, ioErrors);
  const schemas = {};
  if (!schemaDirectory) return schemas;
  for (const [key, name] of [['manifest', 'manifest.schema.json'], ['case', 'case.schema.json'], ['packet', 'packet.schema.json'], ['result', 'result.schema.json'], ['receipt', 'dispatch-receipt.schema.json'], ['jointRecord', 'joint-record.schema.json']]) {
    const schemaPath = resolveContained(evaluationRoot, `schema/${name}`, errors, `schema.${name}`, evaluationRoot, ioErrors);
    if (!schemaPath) continue;
    const schemaJson = readJson(schemaPath, errors, `schema.${name}`, ioErrors);
    if (schemaJson.raw && sha256(schemaJson.raw) !== SCHEMA_SHA256[name]) {
      addError(errors, `schema.${name}`, '固定 schema digest と一致しない');
    }
    if (schemaJson.value && isObject(schemaJson.value)) schemas[key] = schemaJson.value;
    else if (schemaJson.raw) addError(errors, `schema.${name}`, 'schema は object でなければならない');
  }
  return schemas;
}

function validatePacket(packet, packetRaw, manifest, caseFile, result, schema, errors, label) {
  if (!isObject(packet)) {
    addError(errors, label, 'packet は object でなければならない');
    return null;
  }
  if (schema) validateSchemaValue(packet, schema, errors, label);
  if (packet.schema_version !== '1.0') addError(errors, `${label}.schema_version`, '1.0 でなければならない');
  requireString(packet, 'packet_id', errors, label, /^[a-z0-9][a-z0-9-]+$/);
  if (packet.case_id !== caseFile.case_id) addError(errors, `${label}.case_id`, 'case_id が一致しない');
  if (packet.fixture_manifest_sha256 !== manifest.fixtureManifestSha256) addError(errors, `${label}.fixture_manifest_sha256`, 'fixture manifest digest が一致しない');
  if (packet.target_manifest_hash !== manifest.target.identity_hash) addError(errors, `${label}.target_manifest_hash`, 'target identity が一致しない');
  if (packet.epoch_hash !== manifest.epoch_hash) addError(errors, `${label}.epoch_hash`, 'epoch identity が一致しない');
  if (typeof packet.payload !== 'string' || packet.payload.length === 0) addError(errors, `${label}.payload`, '空でない payload が必要である');
  const packetHash = sha256(packetRaw);
  if (result && result.packet_sha256 !== packetHash) addError(errors, `${label}.sha256`, `result.packet_sha256 が実体 ${packetHash} と一致しない`);
  return packetHash;
}

function validateReceipt(receipt, receiptRaw, manifest, caseFile, result, schema, errors, label) {
  if (!isObject(receipt)) {
    addError(errors, label, 'dispatch receipt は object でなければならない');
    return null;
  }
  if (schema) validateSchemaValue(receipt, schema, errors, label);
  if (receipt.schema_version !== '1.0') addError(errors, `${label}.schema_version`, '1.0 でなければならない');
  requireString(receipt, 'receipt_id', errors, label, /^[a-z0-9][a-z0-9-]+$/);
  if (receipt.mode !== 'fixture_only_observe_only') addError(errors, `${label}.mode`, 'fixture_only_observe_only でなければならない');
  if (receipt.run_id !== result.run_id) addError(errors, `${label}.run_id`, 'run_id が一致しない');
  if (receipt.case_id !== caseFile.case_id) addError(errors, `${label}.case_id`, 'case_id が一致しない');
  if (receipt.side !== result.side) addError(errors, `${label}.side`, 'side が一致しない');
  if (receipt.fixture_manifest_sha256 !== manifest.fixtureManifestSha256) addError(errors, `${label}.fixture_manifest_sha256`, 'fixture manifest digest が一致しない');
  if (receipt.target_manifest_hash !== manifest.target.identity_hash) addError(errors, `${label}.target_manifest_hash`, 'target identity が一致しない');
  if (receipt.epoch_hash !== manifest.epoch_hash) addError(errors, `${label}.epoch_hash`, 'epoch identity が一致しない');
  if (!isObject(receipt.role_context_ids)) addError(errors, `${label}.role_context_ids`, 'object が必要である');
  if (receipt.role_context_ids?.reviewer !== result.role_context?.reviewer_context_id) addError(errors, `${label}.role_context_ids.reviewer`, 'Reviewer context が一致しない');
  if (receipt.role_context_ids?.respondent !== result.role_context?.respondent_context_id) addError(errors, `${label}.role_context_ids.respondent`, 'Respondent context が一致しない');
  if (!isObject(receipt.model_identity)) addError(errors, `${label}.model_identity`, 'object が必要である');
  if (receipt.model_identity?.reviewer !== result.model_identity?.reviewer || receipt.model_identity?.respondent !== result.model_identity?.respondent) addError(errors, `${label}.model_identity`, 'model identity が result と一致しない');
  if (receipt.routing_status !== 'DECLARED_ONLY') addError(errors, `${label}.routing_status`, 'DECLARED_ONLY でなければならない');
  if (!Number.isInteger(receipt.dispatch_count) || receipt.dispatch_count < 0) addError(errors, `${label}.dispatch_count`, '0 以上の整数が必要である');
  if (receipt.dispatch_count !== result.dispatch_count) addError(errors, `${label}.dispatch_count`, 'result と一致しない');
  requireBoolean(receipt, 'runtime_dispatch_attempted', false, errors, label);
  requireBoolean(receipt, 'runtime_dispatch_enforcement_claimed', false, errors, label);
  const receiptHash = sha256(receiptRaw);
  if (result.dispatch_receipt_sha256 !== receiptHash) addError(errors, `${label}.sha256`, `result.dispatch_receipt_sha256 が実体 ${receiptHash} と一致しない`);
  return receiptHash;
}

function validatePropositions(result, caseFile, errors, label) {
  if (!Array.isArray(result.propositions)) {
    addError(errors, `${label}.propositions`, '配列が必要である');
    return;
  }
  const fixturePropositions = Array.isArray(caseFile.propositions) ? caseFile.propositions : [];
  const expected = new Map(fixturePropositions.map((item) => [item?.proposition_id, item]));
  const seen = new Set();
  for (const [index, proposition] of result.propositions.entries()) {
    const propositionLabel = `${label}.propositions[${index}]`;
    requireString(proposition, 'proposition_id', errors, propositionLabel, /^[a-z0-9][a-z0-9-]+$/);
    if (seen.has(proposition?.proposition_id)) addError(errors, `${propositionLabel}.proposition_id`, 'proposition_id が重複している');
    seen.add(proposition?.proposition_id);
    const fixtureProposition = expected.get(proposition?.proposition_id);
    if (!fixtureProposition) {
      addError(errors, `${propositionLabel}.proposition_id`, '未知の proposition_id である');
      continue;
    }
    if (proposition.severity !== fixtureProposition.severity) addError(errors, `${propositionLabel}.severity`, 'fixture と severity が一致しない');
    if (!DISCOVERY.has(proposition.discovery)) addError(errors, `${propositionLabel}.discovery`, 'discovery の値が不正である');
    if (!REJECTION.has(proposition.rejection)) addError(errors, `${propositionLabel}.rejection`, 'rejection の値が不正である');
  }
  for (const propositionId of expected.keys()) if (!seen.has(propositionId)) addError(errors, `${label}.propositions`, `fixture の ${propositionId} が欠落している`);
}

function validateJointRecord(record, recordRaw, manifest, caseFile, result, jointRecordPath, schema, errors, label) {
  if (!isObject(record)) {
    addError(errors, label, 'joint record は object でなければならない');
    return;
  }
  if (schema) validateSchemaValue(record, schema, errors, label);
  if (record.schema_version !== '1.0') addError(errors, `${label}.schema_version`, '1.0 でなければならない');
  requireString(record, 'record_id', errors, label, /^[a-z0-9][a-z0-9-]+$/);
  if (record.case_id !== caseFile.case_id) addError(errors, `${label}.case_id`, 'case_id が一致しない');
  if (record.side !== result.side) addError(errors, `${label}.side`, 'side が一致しない');
  if (record.run_id !== result.run_id) addError(errors, `${label}.run_id`, 'run_id が一致しない');
  if (record.fixture_manifest_sha256 !== manifest.fixtureManifestSha256) addError(errors, `${label}.fixture_manifest_sha256`, 'fixture manifest digest が一致しない');
  if (record.target_manifest_hash !== manifest.target.identity_hash) addError(errors, `${label}.target_manifest_hash`, 'target identity が一致しない');
  if (record.epoch_hash !== manifest.epoch_hash) addError(errors, `${label}.epoch_hash`, 'epoch identity が一致しない');
  if (record.version !== result.role_context?.joint_record_version) addError(errors, `${label}.version`, 'result の joint_record_version と一致しない');
  if (record.gate_status !== 'PASS') addError(errors, `${label}.gate_status`, 'zero-findings の joint record は PASS でなければならない');
  if (record.finding_count !== 0) addError(errors, `${label}.finding_count`, 'zero-findings の finding_count は 0 でなければならない');
  if (!Array.isArray(record.findings) || record.findings.length !== 0) addError(errors, `${label}.findings`, 'zero-findings の findings は空配列でなければならない');
  const reviewer = record.reviewer;
  const respondent = record.respondent;
  if (reviewer?.context_id !== result.role_context?.reviewer_context_id || respondent?.context_id !== result.role_context?.respondent_context_id) addError(errors, `${label}.roles`, 'role context が result と一致しない');
  if (reviewer?.approved !== true || respondent?.approved !== true) addError(errors, `${label}.roles`, 'Reviewer と Respondent の双方が承認していない');
  if (result.joint_record_sha256 !== sha256(recordRaw)) addError(errors, `${label}.sha256`, `result.joint_record_sha256 が実体 ${sha256(recordRaw)} と一致しない`);
}

function validateResult(result, side, caseFile, manifest, packet, receipt, jointRecord, schemas, errors, label) {
  if (!isObject(result)) {
    addError(errors, label, 'result は object でなければならない');
    return;
  }
  if (schemas?.result) validateSchemaValue(result, schemas.result, errors, label);
  if (result.schema_version !== '1.0') addError(errors, `${label}.schema_version`, '1.0 でなければならない');
  requireString(result, 'run_id', errors, label, /^[a-z0-9][a-z0-9-]+$/);
  if (result.side !== side) addError(errors, `${label}.side`, `${side} でなければならない`);
  if (result.case_id !== caseFile.case_id) addError(errors, `${label}.case_id`, 'case_id が一致しない');
  if (result.fixture_manifest_sha256 !== manifest.fixtureManifestSha256) addError(errors, `${label}.fixture_manifest_sha256`, 'fixture manifest digest が一致しない');
  if (result.target_manifest_hash !== manifest.target.identity_hash) addError(errors, `${label}.target_manifest_hash`, 'target identity が一致しない');
  if (result.epoch_hash !== manifest.epoch_hash) addError(errors, `${label}.epoch_hash`, 'epoch identity が一致しない');
  requireEnum(result, 'deterministic_checks', new Set(['PASS', 'BLOCKED']), errors, label);
  requireEnum(result, 'evidence_status', new Set(['SUFFICIENT', 'NEEDS_EVIDENCE', 'INVALID', 'MISSING']), errors, label);
  requireEnum(result, 'coverage_status', new Set(['RELIABLE', 'UNRELIABLE', 'MISSING']), errors, label);
  requireEnum(result, 'gate_status', new Set(['PASS', 'BLOCKED']), errors, label);
  if (result.proceed_status !== 'NOT_AUTHORIZED') addError(errors, `${label}.proceed_status`, 'NOT_AUTHORIZED でなければならない');
  if (!ESCALATION_STEPS.has(result.escalation_step)) addError(errors, `${label}.escalation_step`, 'escalation step が不正である');
  if (!Array.isArray(result.escalation_trace) || result.escalation_trace.length === 0) {
    addError(errors, `${label}.escalation_trace`, '1 件以上の escalation trace が必要である');
  } else {
    if (result.escalation_step === 'none' && (result.escalation_trace.length !== 1 || result.escalation_trace[0] !== 'none')) addError(errors, `${label}.escalation_trace`, 'escalation_step=none では trace も none だけでなければならない');
    if (result.escalation_step !== 'none' && result.escalation_trace.includes('none')) addError(errors, `${label}.escalation_trace`, '実 escalation に none を混在させてはならない');
    let previousIndex = -1;
    for (const [index, step] of result.escalation_trace.entries()) {
      if (!ESCALATION_STEPS.has(step) || step === 'none') {
        if (step !== 'none') addError(errors, `${label}.escalation_trace[${index}]`, 'escalation step が不正である');
        continue;
      }
      const currentIndex = ESCALATION_ORDER.indexOf(step);
      if (step !== ESCALATION_ORDER[index]) addError(errors, `${label}.escalation_trace[${index}]`, '固定された escalation prefix を欠落させてはならない');
      if (currentIndex <= previousIndex) addError(errors, `${label}.escalation_trace[${index}]`, '固定された escalation 順序に違反している');
      previousIndex = currentIndex;
    }
    if (result.escalation_step !== 'none' && result.escalation_trace[result.escalation_trace.length - 1] !== result.escalation_step) addError(errors, `${label}.escalation_trace`, '最後の trace と escalation_step が一致しない');
  }
  if (!Number.isInteger(result.finding_count) || result.finding_count < 0) addError(errors, `${label}.finding_count`, '0 以上の整数が必要である');
  for (const key of ['input_tokens', 'output_tokens', 'dispatch_count']) if (!Number.isInteger(result[key]) || result[key] < 0) addError(errors, `${label}.${key}`, '0 以上の整数が必要である');
  requireBoolean(result, 'runtime_dispatch_attempted', false, errors, label);
  requireBoolean(result, 'runtime_dispatch_enforcement_claimed', false, errors, label);
  if (result.routing_status !== 'DECLARED_ONLY') addError(errors, `${label}.routing_status`, 'DECLARED_ONLY でなければならない');

  if (!isObject(result.role_context)) {
    addError(errors, `${label}.role_context`, 'object が必要である');
  } else {
    requireString(result.role_context, 'reviewer_context_id', errors, `${label}.role_context`);
    requireString(result.role_context, 'respondent_context_id', errors, `${label}.role_context`);
    requireString(result.role_context, 'joint_record_version', errors, `${label}.role_context`);
    requireBoolean(result.role_context, 'contexts_distinct', true, errors, `${label}.role_context`);
    if (result.role_context.reviewer_context_id === result.role_context.respondent_context_id) addError(errors, `${label}.role_context`, 'Reviewer と Respondent の context が同一である');
    if (result.gate_status === 'PASS') {
      requireBoolean(result.role_context, 'reviewer_approved', true, errors, `${label}.role_context`);
      requireBoolean(result.role_context, 'respondent_approved', true, errors, `${label}.role_context`);
    }
  }
  if (!isObject(result.model_identity)) {
    addError(errors, `${label}.model_identity`, 'object が必要である');
  } else {
    requireString(result.model_identity, 'reviewer', errors, `${label}.model_identity`);
    requireString(result.model_identity, 'respondent', errors, `${label}.model_identity`);
  }
  validatePropositions(result, caseFile, errors, label);
  if (caseFile.case_id === 'zero-findings') {
    if (result.finding_count !== 0) addError(errors, `${label}.finding_count`, 'zero-findings の finding_count は 0 でなければならない');
    if (!Array.isArray(result.propositions) || result.propositions.length !== 0) addError(errors, `${label}.propositions`, 'zero-findings の propositions は空配列でなければならない');
    if (!jointRecord) addError(errors, `${label}.joint_record`, 'zero-findings には共同最終記録が必要である');
    else validateJointRecord(jointRecord.value, jointRecord.raw, manifest, caseFile, result, jointRecord.path, schemas?.jointRecord, errors, `${label}.joint_record`);
  }
  if (result.gate_status === 'PASS') {
    if (result.deterministic_checks !== 'PASS') addError(errors, `${label}.gate_status`, 'deterministic checks が PASS でない状態では PASS にできない');
    if (result.evidence_status !== 'SUFFICIENT') addError(errors, `${label}.gate_status`, 'evidence 不足の状態では PASS にできない');
    if (result.coverage_status !== 'RELIABLE') addError(errors, `${label}.gate_status`, 'coverage 不良の状態では PASS にできない');
  }
  if (result.evidence_status !== 'SUFFICIENT' || result.coverage_status !== 'RELIABLE' || result.deterministic_checks !== 'PASS') {
    if (result.gate_status !== 'BLOCKED') addError(errors, `${label}.gate_status`, '不確実な evidence、coverage、deterministic check は BLOCKED にしなければならない');
  }
  if (packet) validatePacket(packet.value, packet.raw, manifest, caseFile, result, schemas?.packet, errors, `${label}.packet`);
  if (receipt) validateReceipt(receipt.value, receipt.raw, manifest, caseFile, result, schemas?.receipt, errors, `${label}.receipt`);
}

function comparePair(caseFile, baseline, candidate, errors, warnings, label) {
  if (!baseline || !candidate || !isObject(baseline.value) || !isObject(candidate.value)) return;
  const base = baseline.value;
  const cand = candidate.value;
  if (base.run_id === cand.run_id) addError(errors, `${label}.runs`, 'baseline と candidate の run_id が同一である');
  const baseContexts = [base.role_context?.reviewer_context_id, base.role_context?.respondent_context_id];
  const candidateContexts = [cand.role_context?.reviewer_context_id, cand.role_context?.respondent_context_id];
  for (const contextId of baseContexts) if (contextId && candidateContexts.includes(contextId)) addError(errors, `${label}.runs`, 'baseline と candidate の context が共有されている');
  if (base.role_context?.joint_record_version !== cand.role_context?.joint_record_version) addError(errors, `${label}.runs`, 'baseline と candidate の joint record version が一致しない');
  for (const field of EXACT_PAIR_FIELDS) if (base[field] !== cand[field]) addError(errors, `${label}.pair.${field}`, `baseline=${base[field]} と candidate=${cand[field]} が一致しない`);

  const baselinePropositions = Array.isArray(base.propositions) ? base.propositions : [];
  const candidatePropositions = Array.isArray(cand.propositions) ? cand.propositions : [];
  const baselineProps = new Map(baselinePropositions.map((item) => [item?.proposition_id, item]));
  const candidateProps = new Map(candidatePropositions.map((item) => [item?.proposition_id, item]));
  const fixturePropositions = Array.isArray(caseFile.propositions) ? caseFile.propositions : [];
  for (const fixtureProposition of fixturePropositions) {
    if (!isObject(fixtureProposition)) continue;
    const propositionId = fixtureProposition.proposition_id;
    const baseProp = baselineProps.get(propositionId);
    const candidateProp = candidateProps.get(propositionId);
    if (!baseProp || !candidateProp) continue;
    if (['high', 'critical'].includes(fixtureProposition.severity) && baseProp.discovery !== candidateProp.discovery) {
      addError(errors, `${label}.pair.${propositionId}.discovery`, `重要な discovery が baseline=${baseProp.discovery} と candidate=${candidateProp.discovery} で異なる`);
    }
    if (['medium', 'low'].includes(fixtureProposition.severity)) {
      for (const metric of ['discovery', 'rejection']) {
        if (Array.isArray(fixtureProposition.metrics) && !fixtureProposition.metrics.includes(metric)) continue;
        if (baseProp[metric] !== candidateProp[metric]) addWarning(warnings, `${label}.pair.${propositionId}.${metric}`, `medium/low の report-only 差分: baseline=${baseProp[metric]}, candidate=${candidateProp[metric]}`);
      }
    }
  }
}

function observedRunMetrics(run) {
  const value = run && isObject(run.value) ? run.value : null;
  if (!value) return null;
  return {
    cost: {
      input_tokens: value.input_tokens,
      output_tokens: value.output_tokens,
      total_tokens: Number.isInteger(value.input_tokens) && Number.isInteger(value.output_tokens)
        ? value.input_tokens + value.output_tokens
        : null,
      dispatch_count: value.dispatch_count,
    },
    model_identity: value.model_identity ?? null,
    routing_status: value.routing_status ?? null,
    role_context: value.role_context
      ? {
          reviewer_context_id: value.role_context.reviewer_context_id,
          respondent_context_id: value.role_context.respondent_context_id,
        }
      : null,
    escalation_step: value.escalation_step ?? null,
    escalation_trace: Array.isArray(value.escalation_trace) ? value.escalation_trace : null,
  };
}

function validateCase(caseEntry, manifest, schemas, report) {
  const { entry, casePath, entryLabel } = caseEntry;
  const errors = [];
  const warnings = [];
  const caseJson = readJson(casePath, errors, entryLabel, report.io_errors);
  if (!isObject(caseJson.value)) {
    if (errors.length === 0) addError(errors, entryLabel, 'case は object でなければならない');
    report.errors.push(...errors);
    report.cases.push({ case_id: entry.case_id, status: 'BLOCKED', errors, warnings });
    return;
  }
  const caseFile = caseJson.value;
  if (schemas?.case) validateSchemaValue(caseFile, schemas.case, errors, entryLabel);
  if (caseFile.schema_version !== '1.0') addError(errors, `${entryLabel}.schema_version`, '1.0 でなければならない');
  if (caseFile.case_id !== entry.case_id) addError(errors, `${entryLabel}.case_id`, 'manifest と case の case_id が一致しない');
  if (!Array.isArray(caseFile.propositions)) addError(errors, `${entryLabel}.propositions`, '配列が必要である');
  const propositionIds = new Set();
  const fixturePropositions = Array.isArray(caseFile.propositions) ? caseFile.propositions : [];
  for (const [index, proposition] of fixturePropositions.entries()) {
    const propositionLabel = `${entryLabel}.propositions[${index}]`;
    requireString(proposition, 'proposition_id', errors, propositionLabel, /^[a-z0-9][a-z0-9-]+$/);
    if (propositionIds.has(proposition?.proposition_id)) addError(errors, `${propositionLabel}.proposition_id`, 'proposition_id が重複している');
    propositionIds.add(proposition?.proposition_id);
    if (!SEVERITIES.has(proposition?.severity)) addError(errors, `${propositionLabel}.severity`, 'severity が不正である');
    if (!Array.isArray(proposition?.metrics) || proposition.metrics.length === 0) addError(errors, `${propositionLabel}.metrics`, 'metrics が必要である');
  }

  const caseDirectory = dirname(casePath);
  const packetPath = resolveContained(caseDirectory, caseFile.packet_path, errors, `${entryLabel}.packet_path`, manifest.fixtureDirectory, report.io_errors);
  const packetJson = packetPath ? readJson(packetPath, errors, `${entryLabel}.packet_path`, report.io_errors) : { value: null, raw: null };
  const packet = packetPath ? { ...packetJson, path: packetPath } : null;
  const runs = caseFile.runs;
  if (!isObject(runs)) addError(errors, `${entryLabel}.runs`, 'object が必要である');
  const runData = {};
  for (const side of ['baseline', 'candidate']) {
    const sideLabel = `${entryLabel}.runs.${side}`;
    const descriptor = runs?.[side];
    if (!isObject(descriptor)) {
      addError(errors, sideLabel, 'object が必要である');
      continue;
    }
    const resultPath = resolveContained(caseDirectory, descriptor.result_path, errors, `${sideLabel}.result_path`, manifest.fixtureDirectory, report.io_errors);
    const receiptPath = resolveContained(caseDirectory, descriptor.receipt_path, errors, `${sideLabel}.receipt_path`, manifest.fixtureDirectory, report.io_errors);
    const jointRecordPath = descriptor.joint_record_path ? resolveContained(caseDirectory, descriptor.joint_record_path, errors, `${sideLabel}.joint_record_path`, manifest.fixtureDirectory, report.io_errors) : null;
    const resultJson = resultPath ? readJson(resultPath, errors, `${sideLabel}.result_path`, report.io_errors) : { value: null, raw: null };
    const receiptJson = receiptPath ? readJson(receiptPath, errors, `${sideLabel}.receipt_path`, report.io_errors) : { value: null, raw: null };
    const jointRecordJson = jointRecordPath ? readJson(jointRecordPath, errors, `${sideLabel}.joint_record_path`, report.io_errors) : { value: null, raw: null };
    const receipt = receiptPath ? { ...receiptJson, path: receiptPath } : null;
    const jointRecord = jointRecordPath ? { ...jointRecordJson, path: jointRecordPath } : null;
    runData[side] = resultPath ? { ...resultJson, path: resultPath } : null;
    validateResult(resultJson.value, side, caseFile, manifest, packet, receipt, jointRecord, schemas, errors, sideLabel);
    if (isObject(caseFile.expected?.[side]) && isObject(resultJson.value)) {
      for (const field of ['gate_status', 'evidence_status', 'coverage_status', 'deterministic_checks']) {
        if (caseFile.expected[side][field] !== undefined && resultJson.value[field] !== caseFile.expected[side][field]) addError(errors, `${sideLabel}.expected.${field}`, `期待値 ${caseFile.expected[side][field]} と一致しない`);
      }
    }
  }
  comparePair(caseFile, runData.baseline, runData.candidate, errors, warnings, entryLabel);
  let caseStatus = errors.length === 0 ? 'PASS' : 'BLOCKED';
  if (caseStatus !== entry.expected_status) {
    addError(errors, `${entryLabel}.expected_status`, `期待値 ${entry.expected_status} と実際の ${caseStatus} が一致しない`);
    caseStatus = 'BLOCKED';
  }
  report.errors.push(...errors);
  report.warnings.push(...warnings);
  report.cases.push({
    case_id: entry.case_id,
    status: caseStatus,
    observations: {
      baseline: observedRunMetrics(runData.baseline),
      candidate: observedRunMetrics(runData.candidate),
    },
    errors,
    warnings,
  });
}

function validateManifestFileUnsafe(manifestPath, report) {
  const manifestJson = readJson(manifestPath, report.errors, 'manifest', report.io_errors);
  if (!manifestJson.value || !manifestJson.raw) {
    report.status = 'BLOCKED';
    return report;
  }
  const schemas = loadSchemas(manifestPath, report.errors, report.io_errors);
  if (schemas.manifest) validateSchemaValue(manifestJson.value, schemas.manifest, report.errors, 'manifest');
  const manifestInfo = validateManifest(manifestJson.value, manifestJson.raw, manifestPath, report, report.io_errors);
  if (manifestInfo) {
    manifestJson.value.fixtureDirectory = manifestInfo.fixtureDirectory;
    manifestJson.value.fixtureManifestSha256 = manifestInfo.manifestSha256;
    for (const caseEntry of manifestInfo.caseEntries) validateCase(caseEntry, manifestJson.value, schemas, report);
  }
  report.status = report.errors.length === 0 ? 'PASS' : 'BLOCKED';
  return report;
}

export function validateManifestFile(manifestPath = DEFAULT_MANIFEST) {
  const report = { status: 'PASS', manifest_path: manifestPath, errors: [], warnings: [], io_errors: [], cases: [] };
  try {
    return validateManifestFileUnsafe(manifestPath, report);
  } catch (error) {
    addError(report.errors, 'validator', `入力を安全に検証できない: ${error.message}`);
    report.status = 'BLOCKED';
    return report;
  }
}

function parseArgs(argv) {
  const options = { manifestPath: DEFAULT_MANIFEST, json: false, quiet: false, aggregate: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--manifest') {
      const value = argv[index + 1];
      if (!value) throw new UsageError('--manifest にはパスが必要である');
      options.manifestPath = resolve(process.cwd(), value);
      index += 1;
    } else if (argument === '--json') {
      options.json = true;
    } else if (argument === '--quiet') {
      options.quiet = true;
    } else if (argument === '--aggregate') {
      options.aggregate = true;
    } else if (argument === '--help' || argument === '-h') {
      throw new UsageError('usage: node validate.mjs [--manifest PATH] [--json] [--quiet] [--aggregate]');
    } else {
      throw new UsageError(`未知の引数: ${argument}`);
    }
  }
  return options;
}

function printHumanReport(report) {
  const passedCases = report.cases.filter((item) => item.status === 'PASS').length;
  const blockedCases = report.cases.filter((item) => item.status === 'BLOCKED').length;
  console.log(`Issue #6 fixture evaluation: ${report.status}`);
  console.log(`cases: PASS=${passedCases}, BLOCKED=${blockedCases}`);
  if (report.warnings.length > 0) console.log(`warnings: ${report.warnings.length} (medium/low report-only differences)`);
  for (const error of report.errors) console.error(`ERROR ${error.path}: ${error.message}`);
}

export function main(argv = process.argv.slice(2)) {
  let options;
  try {
    options = parseArgs(argv);
  } catch (error) {
    console.error(error.message);
    return 64;
  }
  if (options.aggregate) {
    try {
      console.log(evaluationAggregate());
      return 0;
    } catch (error) {
      console.error(error.message);
      return error instanceof ContractError ? 2 : 64;
    }
  }
  const report = validateManifestFile(options.manifestPath);
  if (options.json) console.log(JSON.stringify(report, null, 2));
  else if (!options.quiet) printHumanReport(report);
  return report.io_errors.length > 0 ? 64 : report.status === 'PASS' ? 0 : 2;
}

const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) process.exitCode = main();
