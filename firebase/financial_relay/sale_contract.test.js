'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {digest,RelayError}=require('./contract');
const {validateSaleOperation}=require('./sale_contract');
const {createFinancialRelayHandler}=require('./handler');
const branch='11111111-1111-4111-8111-111111111111';
const invoice='22222222-2222-4222-8222-222222222222';
const cashier='33333333-3333-4333-8333-333333333333';
const drug='44444444-4444-4444-8444-444444444444';
const warehouse='55555555-5555-4555-8555-555555555555';
const batch='66666666-6666-4666-8666-666666666666';
const cashAccount='77777777-7777-4777-8777-777777777777';
const cashGl='88888888-8888-4888-8888-888888888888';
const revenueGl='99999999-9999-4999-8999-999999999999';
const cogsGl='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const inventoryGl='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const at='2026-11-10T08:00:00.000';
function envelope(){
  return {
    schema_version:1,operation_type:'CASH_SALE',operation_uuid:invoice,
    branch_uuid:branch,currency_code:'YER',fraction_digits:0,
    invoice:{uuid:invoice,date:at,cashier_uuid:cashier,subtotal_minor:40,
      discount_minor:0,net_minor:40,paid_minor:40,cost_minor:10},
    items:[{uuid:'cccccccc-cccc-4ccc-8ccc-cccccccccccc',drug_uuid:drug,
      sell_unit:'UNIT',qty_in_sell_unit:2,qty_units:2,unit_price_minor:20,
      line_discount_minor:0,line_total_minor:40,line_cost_minor:10}],
    batches:[{uuid:batch,drug_uuid:drug,warehouse_uuid:warehouse}],
    allocations:[{uuid:'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      item_uuid:'cccccccc-cccc-4ccc-8ccc-cccccccccccc',batch_uuid:batch,
      qty_units:2,unit_cost_minor:5}],
    movements:[{uuid:'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      batch_uuid:batch,movement_type:'SALE_OUT',qty_units:-2,
      unit_cost_minor:5,unit_price_minor:20,occurred_at:at}],
    payments:[{uuid:'ffffffff-ffff-4fff-8fff-ffffffffffff',
      cash_uuid:cashAccount,amount_minor:40}],
    cash:[{uuid:'11111111-2222-4222-8222-111111111111',
      cash_uuid:cashAccount,amount_minor:40,date:at}],
    journal:{uuid:'22222222-3333-4333-8333-222222222222',date:at},
    lines:[
      {uuid:'33333333-4444-4444-8444-333333333333',account_uuid:cashGl,dr_minor:40,cr_minor:0},
      {uuid:'44444444-5555-4555-8555-444444444444',account_uuid:revenueGl,dr_minor:0,cr_minor:40},
      {uuid:'55555555-6666-4666-8666-555555555555',account_uuid:cogsGl,dr_minor:10,cr_minor:0},
      {uuid:'66666666-7777-4777-8777-666666666666',account_uuid:inventoryGl,dr_minor:0,cr_minor:10},
    ],
  };
}
function event(e=envelope()) {
  return {operation_uuid:invoice,branch_uuid:branch,payload_hash:digest(e),envelope:e};
}
test('F10 validates complete UUID-only sale with balanced accounting',()=>{
  const op=validateSaleOperation(event(),branch);
  assert.equal(op.operationUuid,invoice);
  assert.equal(op.operationType,'CASH_SALE');
});
test('F10 rejects local IDs, unknown fields, missing allocations and altered hash',()=>{
  for(const mutate of [
    e=>{e.invoice.id=1;},
    e=>{e.items[0].drug_id=8;},
    e=>{e.allocations=[];},
    e=>{e.allocations[0].qty_units=1;},
    e=>{e.movements[0].qty_units=-1;},
    e=>{e.lines[3].cr_minor=9;},
    e=>{e.payments[0].amount_minor=39;},
    e=>{e.cash[0].uuid=e.invoice.uuid;},
    e=>{e.invoice.net_minor=39;},
    e=>{e.invoice.cashier_uuid=1;},
    e=>{e.currency_code='USD';},
    e=>{e.fraction_digits=2;},
    e=>{e.invoice.cost_minor=9;},
    e=>{e.movements[0].movement_type='PURCHASE_IN';},
  ]){
    const e=envelope();mutate(e);
    assert.throws(()=>validateSaleOperation(event(e),branch),RelayError);
  }
  const e=envelope();const op=event(e);e.invoice.net_minor=1;
  assert.throws(()=>validateSaleOperation(op,branch),RelayError);
  assert.throws(()=>validateSaleOperation(event(),'99999999-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),RelayError);
});
async function invoke(handler,method='POST',url='/v1/operations',body=event()) {
  const {Readable}=require('node:stream');
  const req=Readable.from(method==='POST'?[Buffer.from(JSON.stringify(body))]:[]);
  req.method=method; req.url=url;
  req.headers={authorization:'Bearer good','content-type':'application/json'};
  const res={
    status:0, data:'',
    writeHead(status){this.status=status;},
    end(value){this.data=value;},
  };
  await handler(req,res);
  return {status:res.status,body:JSON.parse(res.data)};
}
test('F10 relay is separately disabled even when vouchers are enabled',async()=>{
  let commits=0;
  const store={async commit(){commits++;},async list(){return [];}};
  const auth=async()=>({uid:'u',branch_id:branch,branch_role:'accountant'});
  const h=createFinancialRelayHandler({verifyIdToken:auth,store,enabled:true});
  assert.equal((await invoke(h)).status,403);
  assert.equal(commits,0);
  assert.equal((await invoke(h,'GET','/v1/operations?branch_uuid='+branch+'&operation_type=CASH_SALE')).status,403);
});
test('F10 uses existing authenticated endpoint with independent sale cursor',async()=>{
  let saved,kind;
  const store={
    async commit(x){saved=x;},
    async list(b,after,limit,type){kind=type;
      return [{sequence:1,operationUuid:invoice,payloadHash:saved.payloadHash,envelope:saved.envelope}];},
  };
  const auth=async()=>({uid:'u',branch_id:branch,branch_role:'manager'});
  const h=createFinancialRelayHandler({verifyIdToken:auth,store,enabled:true,saleEnabled:true});
  assert.equal((await invoke(h)).status,200);
  assert.equal(saved.operationType,'CASH_SALE');
  const got=await invoke(h,'GET','/v1/operations?branch_uuid='+branch+'&operation_type=CASH_SALE&after=0&limit=10');
  assert.equal(got.status,200);
  assert.equal(kind,'CASH_SALE');
  assert.equal(got.body.operations[0].operation_uuid,invoice);
  assert.equal(got.body.next_cursor,'1');
  assert.equal((await invoke(createFinancialRelayHandler({
    verifyIdToken:async()=>({uid:'u',branch_id:branch,branch_role:'cashier'}),
    store,enabled:true,saleEnabled:true}))).status,403);
});
module.exports={envelope,event,branch,invoice,drug,batch,cashier,cashAccount,
  cashGl,revenueGl,cogsGl,inventoryGl};
