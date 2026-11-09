'use strict';

const { createHash, timingSafeEqual } = require('node:crypto');

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256 = /^[0-9a-f]{64}$/;
const DATE = /^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})?)?$/;
const MAX_MINOR = 999999999999;
const TOP = ['schema_version','operation_uuid','branch_uuid','fraction_digits','voucher','journal','lines','ledger','cash'];

class RelayError extends Error {
  constructor(code, status = 400) { super(code); this.code = code; this.status = status; }
}
function fail(code, status) { throw new RelayError(code, status); }
function object(value, fields) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail('INVALID_FINANCIAL_OBJECT');
  const keys = Object.keys(value).sort();
  if (keys.length !== fields.length || keys.some((key, i) => key !== [...fields].sort()[i])) fail('INVALID_FINANCIAL_FIELDS');
  return value;
}
function uuid(value) {
  if (typeof value !== 'string' || !UUID.test(value)) fail('INVALID_FINANCIAL_UUID');
  return value.toLowerCase();
}
function integer(value, min, max) {
  if (!Number.isSafeInteger(value) || value < min || value > max) fail('INVALID_FINANCIAL_INTEGER');
  return value;
}
function date(value) {
  if (typeof value !== 'string' || !DATE.test(value) || !Number.isFinite(Date.parse(value))) fail('INVALID_FINANCIAL_DATE');
  return value;
}
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') {
    const out = {};
    for (const key of Object.keys(value).sort()) out[key] = canonical(value[key]);
    return out;
  }
  return value;
}
function digest(envelope) { return createHash('sha256').update(JSON.stringify(canonical(envelope))).digest('hex'); }
function safeHashEqual(a,b) {
  if (typeof a !== 'string' || typeof b !== 'string' || !SHA256.test(a) || !SHA256.test(b)) return false;
  return timingSafeEqual(Buffer.from(a,'hex'), Buffer.from(b,'hex'));
}

// This parser deliberately supports only the financial CASH v1 contract.
// Sensitive text, local SQLite row IDs, and unknown fields fail closed.
function validateOperation(input, authorizedBranch) {
  object(input, ['operation_uuid','branch_uuid','payload_hash','envelope']);
  const branch = uuid(input.branch_uuid);
  if (branch !== uuid(authorizedBranch)) fail('FINANCIAL_BRANCH_FORBIDDEN',403);
  const envelope = object(input.envelope, TOP);
  if (envelope.schema_version !== 1 || uuid(envelope.branch_uuid) !== branch) fail('FINANCIAL_SCHEMA_OR_BRANCH');
  const operation = uuid(envelope.operation_uuid);
  if (uuid(input.operation_uuid) !== operation) fail('FINANCIAL_OPERATION_MISMATCH');
  const submittedHash = input.payload_hash;
  if (!safeHashEqual(submittedHash,digest(envelope))) fail('FINANCIAL_HASH_MISMATCH');
  const digits = integer(envelope.fraction_digits,0,3);
  const voucher = object(envelope.voucher,['uuid','type','date','party_uuid','cash_uuid','amount_minor']);
  if (uuid(voucher.uuid) !== operation || !['RECEIPT','PAYMENT'].includes(voucher.type)) fail('FINANCIAL_VOUCHER_INVALID');
  date(voucher.date);
  const party = uuid(voucher.party_uuid), cashAccount = uuid(voucher.cash_uuid);
  if (party === cashAccount) fail('FINANCIAL_DEPENDENCY_COLLISION');
  const amount = integer(voucher.amount_minor,1,MAX_MINOR);
  const journal = object(envelope.journal,['uuid','date']);
  date(journal.date);
  const ledger = object(envelope.ledger,['uuid']);
  const movement = object(envelope.cash,['uuid']);
  const memberIds = [operation,uuid(journal.uuid),uuid(ledger.uuid),uuid(movement.uuid)];
  const lines = envelope.lines;
  if (!Array.isArray(lines) || lines.length !== 2) fail('FINANCIAL_LINE_COUNT');
  let dr=0,cr=0,withParty=0,withoutParty=0;
  const accounts = new Set();
  for (const raw of lines) {
    const line=object(raw,['uuid','account_uuid','party_uuid','dr_minor','cr_minor']);
    memberIds.push(uuid(line.uuid));
    accounts.add(uuid(line.account_uuid));
    const ld=integer(line.dr_minor,0,MAX_MINOR), lc=integer(line.cr_minor,0,MAX_MINOR);
    if (!((ld===amount && lc===0)||(lc===amount && ld===0))) fail('FINANCIAL_LINE_VALUE');
    dr+=ld; cr+=lc;
    if (line.party_uuid === null) {
      withoutParty++;
      if ((voucher.type==='RECEIPT' && ld!==amount)||(voucher.type==='PAYMENT' && lc!==amount)) fail('FINANCIAL_CASH_SIDE');
    } else {
      if (uuid(line.party_uuid)!==party) fail('FINANCIAL_PARTY_MISMATCH');
      withParty++;
      if ((voucher.type==='RECEIPT' && lc!==amount)||(voucher.type==='PAYMENT' && ld!==amount)) fail('FINANCIAL_PARTY_SIDE');
    }
  }
  if (new Set(memberIds).size!==memberIds.length || accounts.size!==2) fail('FINANCIAL_MEMBER_COLLISION');
  if (dr!==amount || cr!==amount || withParty!==1 || withoutParty!==1) fail('FINANCIAL_JOURNAL_UNBALANCED');
  // Enforce immutable values but do not echo source PII in ACKs.
  return { operationUuid:operation, branchUuid:branch, payloadHash:submittedHash, envelope, fractionDigits:digits };
}

module.exports = { RelayError, validateOperation, digest, canonical, uuid };
