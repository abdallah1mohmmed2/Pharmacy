'use strict';

const { RelayError } = require('./contract');

// Backend-only Firestore documents; direct client reads/writes stay denied by
// firestore.rules. A branch-wide serial is assigned atomically per operation.
// Existing operation identity + identical hash is an idempotent no-op.
class FirestoreFinanceStore {
  constructor(firestore) { this.firestore=firestore; }
  async commit(operation,audit) {
    const stream=this.firestore.collection('financial_operation_streams').doc(operation.branchUuid);
    const record=stream.collection('operations').doc(operation.operationUuid);
    await this.firestore.runTransaction(async tx=>{
      const current=await tx.get(record);
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
  async list(branch,after,limit) {
    const stream=this.firestore.collection('financial_operation_streams').doc(branch);
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
