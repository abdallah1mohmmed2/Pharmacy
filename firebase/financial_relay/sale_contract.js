'use strict';

// F10 CASH_SALE v1 — wire-only schema. No SQLite integer IDs, row snapshots,
// free-text notes, customer identifiers, or client-provided running balances.
const { RelayError, digest, uuid } = require('./contract');
const MAX = 999999999999;
function fail(code) { throw new RelayError('SALE_' + code); }
function exact(value, names) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).length !== names.length ||
      Object.keys(value).some(k => !names.includes(k))) fail('FIELDS_INVALID');
  return value;
}
function rows(value, max=100) {
  if (!Array.isArray(value) || !value.length || value.length>max) fail('MEMBERS_INVALID');
  return value;
}
function integer(n,min=0,max=MAX) {
  if (!Number.isSafeInteger(n) || n<min || n>max) fail('INTEGER_INVALID');
  return n;
}
function identifier(v) {
  try { return uuid(v); } catch (_) { fail('UUID_INVALID'); }
}
function date(v) {
  if (typeof v!=='string' || v.length>35 ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})?$/.test(v) ||
    !Number.isFinite(Date.parse(v))) fail('DATE_INVALID');
  return v;
}
function safeAdd(a,b) { const n=a+b; if (!Number.isSafeInteger(n) || n>MAX) fail('TOTAL_OVERFLOW'); return n; }
function validateSaleOperation(input, authorizedBranch) {
  exact(input,['operation_uuid','branch_uuid','payload_hash','envelope']);
  const branch=identifier(authorizedBranch);
  if (identifier(input.branch_uuid)!==branch) throw new RelayError('FINANCIAL_BRANCH_FORBIDDEN',403);
  const e=exact(input.envelope,['schema_version','operation_type','operation_uuid','branch_uuid','currency_code',
    'fraction_digits','invoice','items','batches','allocations','movements','payments','cash','journal','lines']);
  if (e.schema_version!==1 || e.operation_type!=='CASH_SALE' ||
      e.currency_code!=='YER' || e.fraction_digits!==0 ||
      identifier(e.branch_uuid)!==branch ||
      identifier(e.operation_uuid)!==identifier(input.operation_uuid)) fail('HEADER_INVALID');
  if (digest(e)!==input.payload_hash) fail('HASH_INVALID');
  const seen=new Set();
  function member(v) {
    const id=identifier(v);
    if (seen.has(id)) fail('MEMBER_DUPLICATE');
    seen.add(id);
    return id;
  }
  const i=exact(e.invoice,['uuid','date','cashier_uuid','subtotal_minor','discount_minor',
    'net_minor','paid_minor','cost_minor']);
  if (member(i.uuid)!==e.operation_uuid) fail('INVOICE_UUID_INVALID');
  date(i.date); identifier(i.cashier_uuid);
  const subtotal=integer(i.subtotal_minor,1), discount=integer(i.discount_minor);
  const net=integer(i.net_minor,1), paid=integer(i.paid_minor,1);
  const cost=integer(i.cost_minor);
  if (subtotal<discount || subtotal-discount!==net || paid!==net) fail('INVOICE_TOTALS_INVALID');
  const j=exact(e.journal,['uuid','date']);
  member(j.uuid); date(j.date);

  const items=new Map(), batches=new Map(), payments=new Map(), cash=new Map();
  let itemTotal=0, itemCost=0;
  for (const raw of rows(e.items)) {
    const x=exact(raw,['uuid','drug_uuid','sell_unit','qty_in_sell_unit','qty_units',
      'unit_price_minor','line_discount_minor','line_total_minor','line_cost_minor']);
    const id=member(x.uuid); identifier(x.drug_uuid);
    if (!['UNIT','PACK'].includes(x.sell_unit)) fail('SELL_UNIT_INVALID');
    integer(x.qty_in_sell_unit,1,1000000); integer(x.qty_units,1,1000000);
    integer(x.unit_price_minor); integer(x.line_discount_minor);
    const total=integer(x.line_total_minor);
    const c=integer(x.line_cost_minor);
    if (x.unit_price_minor*x.qty_in_sell_unit - x.line_discount_minor!==total) fail('ITEM_TOTAL_INVALID');
    itemTotal=safeAdd(itemTotal,total); itemCost=safeAdd(itemCost,c);
    items.set(id,{...x,allocated:0,allocationCost:0});
  }
  if (itemTotal!==subtotal || itemCost!==cost) fail('ITEM_SUM_INVALID');

  for (const raw of rows(e.batches)) {
    const b=exact(raw,['uuid','drug_uuid','warehouse_uuid']);
    const id=identifier(b.uuid);
    if (batches.has(id)) fail('BATCH_DUPLICATE');
    identifier(b.drug_uuid); identifier(b.warehouse_uuid);
    batches.set(id,b);
  }
  const outgoing=new Map(), movementCount=new Map();
  for (const raw of rows(e.allocations,300)) {
    const a=exact(raw,['uuid','item_uuid','batch_uuid','qty_units','unit_cost_minor']);
    member(a.uuid);
    const item=items.get(identifier(a.item_uuid)), batch=batches.get(identifier(a.batch_uuid));
    if (!item || !batch || item.drug_uuid!==batch.drug_uuid) fail('ALLOCATION_REFERENCE_INVALID');
    const q=integer(a.qty_units,1,1000000), price=integer(a.unit_cost_minor);
    item.allocated+=q; item.allocationCost=safeAdd(item.allocationCost,q*price);
    outgoing.set(a.batch_uuid,(outgoing.get(a.batch_uuid)||0)+q);
  }
  for (const item of items.values()) {
    if (item.allocated!==item.qty_units || item.allocationCost!==item.line_cost_minor) fail('ALLOCATION_TOTAL_INVALID');
  }
  for (const raw of rows(e.movements,600)) {
    const m=exact(raw,['uuid','batch_uuid','movement_type','qty_units','unit_cost_minor','unit_price_minor','occurred_at']);
    member(m.uuid); date(m.occurred_at);
    if (!batches.has(identifier(m.batch_uuid)) || !['SALE_OUT','PACK_OPEN'].includes(m.movement_type)) fail('MOVEMENT_INVALID');
    integer(m.unit_cost_minor); integer(m.unit_price_minor);
    if (m.movement_type==='SALE_OUT') {
      integer(-m.qty_units,1,1000000);
      movementCount.set(m.batch_uuid,(movementCount.get(m.batch_uuid)||0)-m.qty_units);
    } else if (m.qty_units!==0) fail('PACK_OPEN_INVALID');
  }
  if (movementCount.size!==outgoing.size ||
    [...outgoing].some(([id,q])=>movementCount.get(id)!==q)) fail('STOCK_TOTAL_INVALID');

  let paidSum=0,cashSum=0;
  for (const raw of rows(e.payments)) {
    const x=exact(raw,['uuid','cash_uuid','amount_minor']);
    member(x.uuid); identifier(x.cash_uuid);
    const amount=integer(x.amount_minor,1);
    if (payments.has(x.cash_uuid)) fail('PAYMENT_ACCOUNT_DUPLICATE');
    payments.set(x.cash_uuid,amount);
    paidSum=safeAdd(paidSum,amount);
  }
  for (const raw of rows(e.cash)) {
    const x=exact(raw,['uuid','cash_uuid','amount_minor','date']);
    member(x.uuid); identifier(x.cash_uuid); date(x.date);
    const amount=integer(x.amount_minor,1);
    if (cash.has(x.cash_uuid) || payments.get(x.cash_uuid)!==amount) fail('CASH_MISMATCH');
    cash.set(x.cash_uuid,amount); cashSum=safeAdd(cashSum,amount);
  }
  if (paidSum!==net || cashSum!==net || payments.size!==cash.size) fail('PAYMENT_TOTAL_INVALID');

  let debits=0,credits=0;
  const journals=[];
  for (const raw of rows(e.lines)) {
    const l=exact(raw,['uuid','account_uuid','dr_minor','cr_minor']);
    member(l.uuid); identifier(l.account_uuid);
    const dr=integer(l.dr_minor), cr=integer(l.cr_minor);
    if ((dr===0)===(cr===0)) fail('JOURNAL_SIDE_INVALID');
    debits=safeAdd(debits,dr); credits=safeAdd(credits,cr);
    journals.push(l);
  }
  if (debits!==credits || debits!==net+cost) fail('JOURNAL_TOTAL_INVALID');
  return {operationUuid:e.operation_uuid, branchUuid:branch, payloadHash:input.payload_hash,
    envelope:e, fractionDigits:0, operationType:'CASH_SALE'};
}
module.exports={validateSaleOperation};
