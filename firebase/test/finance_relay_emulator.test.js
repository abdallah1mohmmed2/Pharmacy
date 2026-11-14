'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const { validateOperation, digest, RelayError } = require('../financial_relay/contract');
const { FirestoreFinanceStore } = require('../financial_relay/firestore_store');
const { createFinancialRelayHandler } = require('../financial_relay/handler');

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

test('Firestore Emulator: authenticated CASH_SALE HTTP contract and isolated server stream', {
  skip: !process.env.FIRESTORE_EMULATOR_HOST
}, async()=>{
  const { Readable }=require('node:stream');
  if (!admin.apps.length) admin.initializeApp({projectId:'pharmacy-dafb6'});
  const db=admin.firestore(),store=new FirestoreFinanceStore(db);
  const invoice='f2222222-2222-4222-8222-222222222222';
  const cashier='f3333333-3333-4333-8333-333333333333';
  const drug='f4444444-4444-4444-8444-444444444444';
  const warehouse='f5555555-5555-4555-8555-555555555555';
  const batch='f6666666-6666-4666-8666-666666666666';
  const revenue='f7777777-7777-4777-8777-777777777777';
  const cogs='f8888888-8888-4888-8888-888888888888';
  const inventory='f9999999-9999-4999-8999-999999999999';
  const date='2026-11-10T09:00:00.000';
  const env={
    schema_version:1,operation_type:'CASH_SALE',
    operation_uuid:invoice,branch_uuid:branch,currency_code:'YER',fraction_digits:0,
    invoice:{uuid:invoice,date,cashier_uuid:cashier,subtotal_minor:40,
      discount_minor:0,net_minor:40,paid_minor:40,cost_minor:10},
    items:[{uuid:'faaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',drug_uuid:drug,
      sell_unit:'UNIT',qty_in_sell_unit:2,qty_units:2,unit_price_minor:20,
      line_discount_minor:0,line_total_minor:40,line_cost_minor:10}],
    batches:[{uuid:batch,drug_uuid:drug,warehouse_uuid:warehouse}],
    allocations:[{uuid:'fbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      item_uuid:'faaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',batch_uuid:batch,qty_units:2,unit_cost_minor:5}],
    movements:[{uuid:'fccccccc-cccc-4ccc-8ccc-cccccccccccc',
      batch_uuid:batch,movement_type:'SALE_OUT',qty_units:-2,
      unit_cost_minor:5,unit_price_minor:20,occurred_at:date}],
    payments:[{uuid:'fddddddd-dddd-4ddd-8ddd-dddddddddddd',
      cash_uuid:cash,amount_minor:40}],
    cash:[{uuid:'feeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      cash_uuid:cash,amount_minor:40,date}],
    journal:{uuid:'ffffffff-ffff-4fff-8fff-ffffffffffff',date},
    lines:[
      {uuid:'a1111111-1111-4111-8111-111111111111',account_uuid:cashGl,dr_minor:40,cr_minor:0},
      {uuid:'a2222222-2222-4222-8222-222222222222',account_uuid:revenue,dr_minor:0,cr_minor:40},
      {uuid:'a3333333-3333-4333-8333-333333333333',account_uuid:cogs,dr_minor:10,cr_minor:0},
      {uuid:'a4444444-4444-4444-8444-444444444444',account_uuid:inventory,dr_minor:0,cr_minor:10}
    ]
  };
  const operation={operation_uuid:invoice,branch_uuid:branch,payload_hash:digest(env),envelope:env};
  const registry=db.collection('financial_operation_registries').doc(branch);
  const stream=db.collection('financial_sale_operation_streams').doc(branch);
  const member=stream.collection('operations').doc(invoice);
  await member.delete();await stream.delete();await registry.delete();
  const handler=createFinancialRelayHandler({
    verifyIdToken:async()=>({uid:'u',branch_id:branch,branch_role:'manager'}),
    store,enabled:true,saleEnabled:true
  });
  async function call(method,body,url='/v1/operations'){
    const req=Readable.from(method==='POST'?[Buffer.from(JSON.stringify(body))]:[]);
    req.method=method;req.url=url;req.headers={authorization:'Bearer test',
      'content-type':'application/json'};
    const res={status:0,body:'',writeHead(status){this.status=status;},
      end(v){this.body=v;}};
    await handler(req,res);
    return {status:res.status,data:JSON.parse(res.body)};
  }
  try {
    assert.equal((await call('POST',operation)).status,403);
    assert.equal((await member.get()).exists,false);
    await registry.set({
      enabled:true,fraction_digits:0,sale_enabled:true,
      sale_cashier_uuids:[cashier],sale_drug_uuids:[drug],
      sale_batches:{[batch]:{drug_uuid:drug,warehouse_uuid:warehouse}},
      cash_accounts:{[cash]:cashGl},sale_gl:{revenue,cogs,inventory}
    });
    assert.equal((await call('POST',operation)).status,200);
    assert.equal((await call('POST',operation)).status,200);
    const q='/v1/operations?branch_uuid='+branch+'&operation_type=CASH_SALE&after=0&limit=20';
    const page=await call('GET',null,q);
    assert.equal(page.status,200);
    assert.equal(page.data.operations.length,1);
    assert.equal(page.data.next_cursor,'1');
    assert.equal((await call('GET',null,'/v1/operations?branch_uuid='+branch)).data.operations.length,0);
    assert.equal((await stream.get()).data().last_sequence,1);
    const changed=JSON.parse(JSON.stringify(operation));
    changed.envelope.invoice.date='2026-11-11T09:00:00.000';
    changed.payload_hash=digest(changed.envelope);
    assert.equal((await call('POST',changed)).status,409);
    assert.equal((await stream.get()).data().last_sequence,1);
  } finally {
    await member.delete();await stream.delete();await registry.delete();
  }
});
