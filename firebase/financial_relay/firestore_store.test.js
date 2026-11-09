'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { FirestoreFinanceStore } = require('./firestore_store');
const { RelayError } = require('./contract');

const branch='11111111-1111-4111-8111-111111111111';
const party='22222222-2222-4222-8222-222222222222';
const cash='33333333-3333-4333-8333-333333333333';
const cashGl='66666666-6666-4666-8666-666666666666';
const partyGl='77777777-7777-4777-8777-777777777777';
const operationId='44444444-4444-4444-8444-444444444444';

class FakeFirestore {
  constructor(){this.docs=new Map();}
  ref(path) {
    const db=this;
    const ref={path,collection(name){return db.collectionAt(path+'/'+name);}};
    return ref;
  }
  collection(name){return this.collectionAt(name);}
  collectionAt(path){
    const db=this;
    return {
      doc(id){return db.ref(path+'/'+id);},
      where(field,op,val){
        if(field!=='sequence'||op!=='>')throw Error('unexpected query');
        return {
          orderBy(key,dir){
            if(key!=='sequence'||dir!=='asc')throw Error('unexpected order');
            return {limit(n){return {async get(){
              const docs=[...db.docs.entries()].filter(([name,data])=>
                name.startsWith(path+'/') && data.sequence>val)
                .sort((a,b)=>a[1].sequence-b[1].sequence).slice(0,n)
                .map(([name,data])=>({id:name.split('/').pop(),data:()=>data}));
              return {docs};
            }};}};
          }
        };
      }
    };
  }
  async runTransaction(callback){
    const db=this;
    const writes=[];
    const tx={
      async get(ref){const exists=db.docs.has(ref.path);return {exists,data:()=>db.docs.get(ref.path)};},
      set(ref,data,opts){writes.push(()=>db.docs.set(ref.path,opts?.merge?{...db.docs.get(ref.path),...data}:data));},
      create(ref,data){writes.push(()=>{if(db.docs.has(ref.path))throw Error('already exists');db.docs.set(ref.path,data);});}
    };
    const value=await callback(tx);
    for(const write of writes)write();
    return value;
  }
  approve(parties=[party],fractionDigits=2,cashGlUuid=cashGl){
    this.docs.set('financial_operation_registries/'+branch,{
      enabled:true,fraction_digits:fractionDigits,
      party_uuids:parties,cash_accounts:{[cash]:cashGlUuid},
      party_gl:{RECEIPT:partyGl,PAYMENT:partyGl}
    });
  }
}
function operation(){
  return {
    operationUuid:operationId, branchUuid:branch,payloadHash:'a'.repeat(64),
    fractionDigits:2,
    envelope:{
      voucher:{type:'RECEIPT',party_uuid:party,cash_uuid:cash},
      lines:[
        {account_uuid:cashGl,party_uuid:null},
        {account_uuid:partyGl,party_uuid:party}
      ]
    }
  };
}
const audit={uid:'verified-firebase-user',branchRole:'accountant'};

test('relay refuses unprovisioned branch financial references',async()=>{
  const db=new FakeFirestore(),store=new FirestoreFinanceStore(db);
  await assert.rejects(store.commit(operation(),audit),e=>e instanceof RelayError && e.code==='FINANCIAL_REFERENCES_NOT_APPROVED');
  assert.equal(db.docs.size,0);
});
test('relay refuses unauthorized party, wrong account mapping and precision',async()=>{
  const db=new FakeFirestore(),store=new FirestoreFinanceStore(db);
  db.approve([],2);
  await assert.rejects(store.commit(operation(),audit),e=>e.code==='FINANCIAL_PARTY_NOT_APPROVED');
  db.approve([party],0);
  await assert.rejects(store.commit(operation(),audit),e=>e.code==='FINANCIAL_CURRENCY_POLICY_MISMATCH');
  db.approve([party],2,partyGl);
  await assert.rejects(store.commit(operation(),audit),e=>e.code==='FINANCIAL_ACCOUNTS_NOT_APPROVED');
  assert.equal(db.docs.has('financial_operation_streams/'+branch),false);
});
test('approved transaction persists once, returns ordered stream, rejects changed hash',async()=>{
  const db=new FakeFirestore(),store=new FirestoreFinanceStore(db);
  db.approve();
  await store.commit(operation(),audit);
  await store.commit(operation(),audit);
  const first=await store.list(branch,0,10);
  assert.equal(first.length,1);
  assert.equal(first[0].sequence,1);
  assert.equal(first[0].operationUuid,operationId);
  assert.deepEqual(await store.list(branch,1,10),[]);
  await assert.rejects(store.commit({...operation(),payloadHash:'b'.repeat(64)},audit),e=>e.code==='FINANCIAL_OPERATION_CONFLICT');
  assert.equal((await store.list(branch,0,10)).length,1);
  assert.equal(db.docs.get('financial_operation_streams/'+branch).last_sequence,1);
});
