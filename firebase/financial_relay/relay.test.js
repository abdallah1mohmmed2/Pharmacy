'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {Readable}=require('node:stream');
const {createFinancialRelayHandler}=require('./handler');
const {validateOperation,digest,RelayError}=require('./contract');
const branch='11111111-1111-4111-8111-111111111111';
const party='22222222-2222-4222-8222-222222222222';
const cash='33333333-3333-4333-8333-333333333333';
const id='44444444-4444-4444-8444-444444444444';
function envelope(){
  return {schema_version:2,operation_uuid:id,branch_uuid:branch,fraction_digits:0,currency_code:'YER',
    voucher:{uuid:id,type:'RECEIPT',date:'2026-11-09T00:00:00.000',party_uuid:party,cash_uuid:cash,amount_minor:12525},
    journal:{uuid:'55555555-5555-4555-8555-555555555555',date:'2026-11-09T00:00:00.000'},
    lines:[
      {uuid:'88888888-8888-4888-8888-888888888888',account_uuid:'66666666-6666-4666-8666-666666666666',party_uuid:null,dr_minor:12525,cr_minor:0},
      {uuid:'99999999-9999-4999-8999-999999999999',account_uuid:'77777777-7777-4777-8777-777777777777',party_uuid:party,dr_minor:0,cr_minor:12525},
    ],
    ledger:{uuid:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'},cash:{uuid:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'}
  };
}
function operation(en=envelope()){return {operation_uuid:id,branch_uuid:branch,payload_hash:digest(en),envelope:en};}
function mockStore(){
  const saved=[];
  return {saved,async commit(op){
      const prior=saved.find(v=>v.operationUuid===op.operationUuid);
      if(prior){
        if(prior.payloadHash!==op.payloadHash) throw new RelayError('FINANCIAL_OPERATION_CONFLICT',409);
        return;
      }
      saved.push({...op,sequence:saved.length+1});
    },
    async list(b,after,limit){return saved.filter(v=>v.branchUuid===b&&v.sequence>after).slice(0,limit);}
  };
}
async function invoke(h,opts={}){
  const method=opts.method||'POST';
  const body=opts.body===undefined?operation():opts.body;
  const req=Readable.from(body===null?[]:[Buffer.from(JSON.stringify(body))]);
  req.method=method;req.url=opts.url||'/v1/operations';
  req.headers={authorization:opts.token===null?undefined:'Bearer '+(opts.token||'valid'),
    ...(method==='POST'?{'content-type':'application/json'}:{}),...(opts.headers||{})};
  let status,response;
  await h(req,{writeHead(code){status=code;},end(body){response=JSON.parse(body);}});
  return {status,body:response};
}
function handler(store=mockStore(),enabled=true,verifyIdToken=async()=>({uid:'operator-1',branch_id:branch,branch_role:'accountant'})){
  return createFinancialRelayHandler({verifyIdToken,store,enabled});
}
test('valid receipt and canonical hash',()=>{const x=validateOperation(operation(),branch);assert.equal(x.operationUuid,id);});
test('rejects missing or corrupt accounting members',()=>{
  for(const mutation of [
    e=>{e.lines[1].cr_minor=12524;},
    e=>{e.voucher.amount_minor=0;},
    e=>{e.voucher.memo='PRIVATE';},
    e=>{e.lines[1].party_uuid=null;},
    e=>{e.lines[0].account_uuid=e.lines[1].account_uuid;}
  ]){const en=envelope();mutation(en);assert.throws(()=>validateOperation(operation(en),branch),RelayError);}
});
test('rejects obsolete v1, wrong currency and fractional YER',()=>{
  for (const mutation of [
    e=>{e.schema_version=1;},
    e=>{e.currency_code='USD';},
    e=>{e.fraction_digits=2;},
    e=>{delete e.currency_code;}
  ]) {
    const en=envelope(); mutation(en);
    assert.throws(()=>validateOperation(operation(en),branch),RelayError);
  }
});
test('hash mismatch and branch mismatch never persist',async()=>{
  const store=mockStore(),h=handler(store);
  assert.equal((await invoke(h,{body:{...operation(),payload_hash:'f'.repeat(64)}})).status,400);
  assert.equal(store.saved.length,0);
  const wrong={...operation(),branch_uuid:'cccccccc-cccc-4ccc-8ccc-cccccccccccc'};
  assert.equal((await invoke(h,{body:wrong})).status,403);
  assert.equal(store.saved.length,0);
});
test('default disabled gate refuses all requests',async()=>{
  const s=mockStore();assert.equal((await invoke(handler(s,false))).status,503);assert.equal(s.saved.length,0);
});
test('missing, invalid and revoked tokens cannot read or write',async()=>{
  const s=mockStore(),h=handler(s,true,async()=>{throw Error('revoked');});
  assert.equal((await invoke(h,{token:null})).status,401);
  assert.equal((await invoke(h)).status,401);
  assert.equal((await invoke(h,{method:'GET',body:null,url:'/v1/operations?branch_uuid='+branch})).status,401);
  assert.equal(s.saved.length,0);
});
test('incorrect role or branch claim forbids upload',async()=>{
  const wrongRole=handler(mockStore(),true,async()=>({uid:'u',branch_id:branch,branch_role:'cashier'}));
  assert.equal((await invoke(wrongRole)).status,403);
  const wrongBranch=handler(mockStore(),true,async()=>({uid:'u',branch_id:'cccccccc-cccc-4ccc-8ccc-cccccccccccc',branch_role:'owner'}));
  assert.equal((await invoke(wrongBranch)).status,403);
});
test('identical replay is idempotent and conflicting payload is rejected',async()=>{
  const s=mockStore(),h=handler(s);
  assert.equal((await invoke(h)).body.status,'COMMITTED');
  assert.equal((await invoke(h)).body.status,'COMMITTED');
  assert.equal(s.saved.length,1);
  const en=envelope();en.voucher.amount_minor=12526;en.lines[0].dr_minor=12526;en.lines[1].cr_minor=12526;
  assert.equal((await invoke(h,{body:operation(en)})).status,409);
  assert.equal(s.saved.length,1);
});
test('paginated GET is branch-scoped and ordered',async()=>{
  const s=mockStore(),h=handler(s);await invoke(h);
  const query='/v1/operations?branch_uuid='+branch+'&after=&limit=1';
  const result=await invoke(h,{method:'GET',body:null,url:query});
  assert.equal(result.status,200);assert.equal(result.body.operations.length,1);assert.equal(result.body.next_cursor,'1');
  const noMore=await invoke(h,{method:'GET',body:null,url:'/v1/operations?branch_uuid='+branch+'&after=1&limit=1'});
  assert.equal(noMore.body.operations.length,0);
  assert.equal((await invoke(h,{method:'GET',body:null,url:'/v1/operations?branch_uuid=cccccccc-cccc-4ccc-8ccc-cccccccccccc'})).status,403);
});
test('bad cursor, unexpected query and text/plain POST are denied',async()=>{
  const h=handler();
  assert.equal((await invoke(h,{method:'GET',body:null,url:'/v1/operations?branch_uuid='+branch+'&after=1foo'})).status,400);
  assert.equal((await invoke(h,{method:'GET',body:null,url:'/v1/operations?branch_uuid='+branch+'&unexpected=x'})).status,400);
  assert.equal((await invoke(h,{headers:{'content-type':'text/plain'}})).status,415);
});
