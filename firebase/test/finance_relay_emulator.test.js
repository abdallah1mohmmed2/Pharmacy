'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const { validateOperation, digest, RelayError } = require('../financial_relay/contract');
const { FirestoreFinanceStore } = require('../financial_relay/firestore_store');

const branch='d1111111-1111-4111-8111-111111111111';
const voucherId='d2222222-2222-4222-8222-222222222222';
const party='d3333333-3333-4333-8333-333333333333';
const cash='d4444444-4444-4444-8444-444444444444';
const cashGl='d5555555-5555-4555-8555-555555555555';
const partyGl='d6666666-6666-4666-8666-666666666666';

function event(){
  const envelope={
    schema_version:2,branch_uuid:branch,operation_uuid:voucherId,fraction_digits:0,currency_code:'YER',
    voucher:{uuid:voucherId,type:'RECEIPT',date:'2026-11-09T00:00:00.000',party_uuid:party,cash_uuid:cash,amount_minor:12050},
    journal:{uuid:'d7777777-7777-4777-8777-777777777777',date:'2026-11-09T00:00:00.000'},
    lines:[
      {uuid:'d8888888-8888-4888-8888-888888888888',account_uuid:cashGl,party_uuid:null,dr_minor:12050,cr_minor:0},
      {uuid:'d9999999-9999-4999-8999-999999999999',account_uuid:partyGl,party_uuid:party,dr_minor:0,cr_minor:12050}
    ],
    ledger:{uuid:'daaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'},
    cash:{uuid:'dbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'},
  };
  return validateOperation({operation_uuid:voucherId,branch_uuid:branch,payload_hash:digest(envelope),envelope},branch);
}

test('Firestore Emulator: approved financial voucher persists atomically and replays once', {
  skip: !process.env.FIRESTORE_EMULATOR_HOST
}, async()=>{
  if (!admin.apps.length) admin.initializeApp({projectId:'pharmacy-dafb6'});
  const db=admin.firestore();
  const registry=db.collection('financial_operation_registries').doc(branch);
  const stream=db.collection('financial_operation_streams').doc(branch);
  const member=stream.collection('operations').doc(voucherId);
  await member.delete();await stream.delete();await registry.delete();
  const store=new FirestoreFinanceStore(db);
  try {
    await assert.rejects(store.commit(event(),{uid:'u',branchRole:'accountant'}),
      e=>e instanceof RelayError && e.code==='FINANCIAL_REFERENCES_NOT_APPROVED');
    assert.equal((await member.get()).exists,false);
    await registry.set({enabled:true,fraction_digits:0,
      party_uuids:[party],cash_accounts:{[cash]:cashGl},
      party_gl:{RECEIPT:partyGl,PAYMENT:partyGl}});
    const op=event();
    await store.commit(op,{uid:'u',branchRole:'accountant'});
    await store.commit(op,{uid:'u',branchRole:'accountant'});
    const all=await store.list(branch,0,20);
    assert.equal(all.length,1);
    assert.equal(all[0].sequence,1);
    assert.equal((await member.get()).data().payload_hash,op.payloadHash);
    assert.equal((await stream.get()).data().last_sequence,1);
    assert.deepEqual(await store.list(branch,1,20),[]);
    await assert.rejects(
      store.commit({...op,payloadHash:'f'.repeat(64)},{uid:'u',branchRole:'accountant'}),
      e=>e instanceof RelayError && e.code==='FINANCIAL_OPERATION_CONFLICT');
    assert.equal((await stream.get()).data().last_sequence,1);
  } finally {
    await member.delete();await stream.delete();await registry.delete();
  }
});
