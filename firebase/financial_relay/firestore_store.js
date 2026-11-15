'use strict';

const { RelayError, uuid } = require('./contract');

// Backend-only Firestore documents; direct client reads/writes stay denied by
// firestore.rules. A branch-wide serial is assigned atomically per operation.
// Existing operation identity + identical hash is an idempotent no-op.
class FirestoreFinanceStore {
  constructor(firestore) { this.firestore=firestore; }
  async commit(operation,audit) {
    const stream=this.firestore.collection(operation.operationType==='CASH_SALE' ? 'financial_sale_operation_streams' : 'financial_operation_streams').doc(operation.branchUuid);
    const record=stream.collection('operations').doc(operation.operationUuid);
    const registry=this.firestore.collection('financial_operation_registries').doc(operation.branchUuid);
    await this.firestore.runTransaction(async tx=>{
      const current=await tx.get(record);
      const reference=await tx.get(registry);
      // Admin-provisioned authoritative mapping. A legitimate Firebase login
      // alone cannot invent master UUIDs or select arbitrary ledger accounts.
      if (!reference.exists || reference.data().enabled !== true) {
        throw new RelayError('FINANCIAL_REFERENCES_NOT_APPROVED',403);
      }
      const approved=reference.data();
      if (approved.fraction_digits!==operation.fractionDigits) {
        throw new RelayError('FINANCIAL_CURRENCY_POLICY_MISMATCH',403);
      }
      if (operation.operationType==='CASH_SALE') {
        this._authorizeSale(operation.envelope, approved);
      } else {
      const voucher=operation.envelope.voucher;
      if (!Array.isArray(approved.party_uuids) ||
          !approved.party_uuids.includes(voucher.party_uuid)) {
        throw new RelayError('FINANCIAL_PARTY_NOT_APPROVED',403);
      }
      const cashAccounts=approved.cash_accounts;
      const accountGl=cashAccounts && typeof cashAccounts==='object'
        ? cashAccounts[voucher.cash_uuid] : null;
      const partyGl=approved.party_gl && approved.party_gl[voucher.type];
      if (typeof accountGl!=='string' || typeof partyGl!=='string' ||
          uuid(accountGl)===uuid(partyGl)) {
        throw new RelayError('FINANCIAL_ACCOUNTS_NOT_APPROVED',403);
      }
      const lines=operation.envelope.lines;
      const cashLine=lines.find(line=>line.party_uuid===null);
      const partyLine=lines.find(line=>line.party_uuid!==null);
      if (!cashLine || !partyLine ||
          cashLine.account_uuid!==accountGl ||
          partyLine.account_uuid!==partyGl) {
        throw new RelayError('FINANCIAL_GL_MAPPING_MISMATCH',403);
      }
      }
      if (current.exists) {
        const stored=current.data();
        if (stored.payload_hash!==operation.payloadHash || stored.branch_uuid!==operation.branchUuid) {
          throw new RelayError('FINANCIAL_OPERATION_CONFLICT',409);
        }
        return;
      }
      const state=await tx.get(stream);
      const last=state.exists ? state.data().last_sequence : 0;
      if (!Number.isSafeInteger(last)||last<0||last>=Number.MAX_SAFE_INTEGER-1) throw new RelayError('FINANCIAL_SEQUENCE_INVALID',500);
      const sequence=last+1;
      tx.set(stream,{branch_uuid:operation.branchUuid,last_sequence:sequence},{merge:true});
      tx.create(record,{
        sequence,operation_uuid:operation.operationUuid,
        branch_uuid:operation.branchUuid,payload_hash:operation.payloadHash,
        envelope:operation.envelope,accepted_by: audit.uid,
        accepted_role:audit.branchRole,
        created_at: new Date().toISOString(),
      });
    });
  }
  // Branch registry is provisioned by a trusted administrator; a client must
  // never register its own cash, stock, cashier or general-ledger references.
  _authorizeSale(e, approved) {
    if (approved.sale_enabled!==true ||
        !Array.isArray(approved.sale_cashier_uuids) ||
        !approved.sale_cashier_uuids.includes(e.invoice.cashier_uuid) ||
        !Array.isArray(approved.sale_drug_uuids) ||
        !approved.sale_batches || typeof approved.sale_batches!=='object') {
      throw new RelayError('FINANCIAL_SALE_REFERENCES_NOT_APPROVED',403);
    }
    for (const item of e.items) {
      if (!approved.sale_drug_uuids.includes(item.drug_uuid)) {
        throw new RelayError('FINANCIAL_SALE_DRUG_NOT_APPROVED',403);
      }
    }
    for (const batch of e.batches) {
      const known=approved.sale_batches[batch.uuid];
      if (!known || known.drug_uuid!==batch.drug_uuid ||
          known.warehouse_uuid!==batch.warehouse_uuid) {
        throw new RelayError('FINANCIAL_SALE_BATCH_NOT_APPROVED',403);
      }
    }
    const gl=approved.sale_gl;
    if (!gl || typeof gl!=='object' ||
        typeof gl.revenue!=='string' || typeof gl.cogs!=='string' ||
        typeof gl.inventory!=='string') {
      throw new RelayError('FINANCIAL_SALE_GL_NOT_APPROVED',403);
    }
    const expected=new Map();
    const add=(account,dr,cr)=>{
      if (!account || typeof account!=='string') {
        throw new RelayError('FINANCIAL_SALE_GL_NOT_APPROVED',403);
      }
      uuid(account);
      const prev=expected.get(account)||[0,0];
      expected.set(account,[prev[0]+dr,prev[1]+cr]);
    };
    add(gl.revenue,0,e.invoice.net_minor);
    if (e.invoice.cost_minor>0) {
      add(gl.cogs,e.invoice.cost_minor,0);
      add(gl.inventory,0,e.invoice.cost_minor);
    }
    for (const payment of e.payments) {
      const account=approved.cash_accounts?.[payment.cash_uuid];
      if (!account) throw new RelayError('FINANCIAL_SALE_CASH_NOT_APPROVED',403);
      add(account,payment.amount_minor,0);
    }
    const actual=new Map();
    for (const line of e.lines) {
      if (actual.has(line.account_uuid)) {
        throw new RelayError('FINANCIAL_SALE_DUPLICATE_GL_LINE',403);
      }
      actual.set(line.account_uuid,[line.dr_minor,line.cr_minor]);
    }
    if (actual.size!==expected.size ||
        [...actual].some(([account,values])=>{
          const e=expected.get(account);
          return !e || e[0]!==values[0] || e[1]!==values[1];
        })) {
      throw new RelayError('FINANCIAL_SALE_GL_MAPPING_MISMATCH',403);
    }
  }

  async list(branch,after,limit,operationType=null) {
    const stream=this.firestore.collection(operationType==='CASH_SALE' ? 'financial_sale_operation_streams' : 'financial_operation_streams').doc(branch);
    const query=stream.collection('operations').where('sequence','>',after)
      .orderBy('sequence','asc').limit(limit);
    const snap=await query.get();
    return snap.docs.map(doc=>{
      const data=doc.data();
      if(data.branch_uuid!==branch)throw new RelayError('FINANCIAL_STORE_BRANCH_MISMATCH',500);
      return {sequence:data.sequence,operationUuid:data.operation_uuid,
        payloadHash:data.payload_hash,envelope:data.envelope};
    });
  }
}
module.exports={FirestoreFinanceStore};
