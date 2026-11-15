'use strict';

const { RelayError, validateOperation, uuid } = require('./contract');
const { validateSaleOperation } = require('./sale_contract');

const MAX_BYTES = 250000;
const AUTHORIZED_ROLES = new Set(['owner','manager','accountant']);

function jsonResponse(res, status, body) {
  res.writeHead(status, {'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff'});
  res.end(JSON.stringify(body));
}
async function readJson(req) {
  let size=0, chunks=[];
  for await (const chunk of req) {
    size+=chunk.length;
    if (size>MAX_BYTES) throw new RelayError('FINANCIAL_REQUEST_TOO_LARGE',413);
    chunks.push(chunk);
  }
  if (!chunks.length) throw new RelayError('EMPTY_FINANCIAL_REQUEST');
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch (_) { throw new RelayError('INVALID_FINANCIAL_JSON'); }
}
function parseCursor(raw) {
  if (raw === '') return 0;
  if (typeof raw!=='string' || !/^(?:0|[1-9]\d{0,14})$/.test(raw)) throw new RelayError('INVALID_FINANCIAL_CURSOR');
  return Number(raw);
}
function createFinancialRelayHandler({verifyIdToken,store,enabled=false,saleEnabled=false}) {
  if (typeof verifyIdToken !== 'function' || !store || typeof store.commit !== 'function' || typeof store.list !== 'function') {
    throw new TypeError('Authenticated financial relay dependencies are required');
  }
  return async function financialRelay(req,res) {
    try {
      if (!enabled) throw new RelayError('FINANCIAL_RELAY_DISABLED',503);
      if (req.url?.split('?')[0] !== '/v1/operations') throw new RelayError('NOT_FOUND',404);
      if (!['POST','GET'].includes(req.method)) throw new RelayError('METHOD_NOT_ALLOWED',405);
      const auth = req.headers.authorization;
      if (typeof auth!=='string' || !/^Bearer [^\s]+$/.test(auth)) throw new RelayError('AUTH_REQUIRED',401);
      let claims;
      try { claims=await verifyIdToken(auth.slice(7),true); }
      catch (_) { throw new RelayError('INVALID_AUTH_TOKEN',401); }
      if (!claims || typeof claims.uid!=='string' || typeof claims.branch_id!=='string') {
        throw new RelayError('BRANCH_CLAIM_REQUIRED',403);
      }
      const branch=uuid(claims.branch_id);
      if (!AUTHORIZED_ROLES.has(claims.branch_role)) throw new RelayError('FINANCIAL_ROLE_FORBIDDEN',403);

      if (req.method==='POST') {
        if (!String(req.headers['content-type']||'').toLowerCase().startsWith('application/json')) {
          throw new RelayError('JSON_CONTENT_TYPE_REQUIRED',415);
        }
        const body=await readJson(req);
        const isSale=body?.envelope?.operation_type==='CASH_SALE';
        if (isSale && !saleEnabled) throw new RelayError('FINANCIAL_SALES_DISABLED',403);
        const operation=isSale ? validateSaleOperation(body,branch) : validateOperation(body,branch);
        await store.commit(operation,{uid:claims.uid,branchRole:claims.branch_role});
        jsonResponse(res,200,{status:'COMMITTED',operation_uuid:operation.operationUuid,payload_hash:operation.payloadHash});
        return;
      }
      const uri=new URL(req.url,'https://financial-relay.invalid');
      if ([...uri.searchParams.keys()].some(key=>!['branch_uuid','after','limit','operation_type'].includes(key))) {
        throw new RelayError('INVALID_FINANCIAL_QUERY');
      }
      const requested=uuid(uri.searchParams.get('branch_uuid'));
      if (requested!==branch) throw new RelayError('FINANCIAL_BRANCH_FORBIDDEN',403);
      const operationType=uri.searchParams.get('operation_type');
      if (operationType!==null && operationType!=='CASH_SALE') throw new RelayError('INVALID_FINANCIAL_DOMAIN');
      if (operationType==='CASH_SALE' && !saleEnabled) throw new RelayError('FINANCIAL_SALES_DISABLED',403);
      const after=parseCursor(uri.searchParams.get('after')??'');
      const limit=integerLimit(uri.searchParams.get('limit')??'50');
      const items=await store.list(branch,after,limit,operationType);
      if (!Array.isArray(items) || items.length>limit) throw new RelayError('INVALID_RELAY_STORE',500);
      let previous=after;
      const operations=items.map(item=>{
        if (!Number.isSafeInteger(item.sequence)||item.sequence<=previous) throw new RelayError('INVALID_RELAY_ORDER',500);
        previous=item.sequence;
        return {operation_uuid:item.operationUuid,payload_hash:item.payloadHash,envelope:item.envelope};
      });
      jsonResponse(res,200,{operations,next_cursor:String(previous)});
    } catch (error) {
      const status=error instanceof RelayError?error.status:500;
      const code=error instanceof RelayError?error.code:'FINANCIAL_RELAY_INTERNAL_ERROR';
      jsonResponse(res,status,{error:code});
    }
  };
}
function integerLimit(raw) {
  if (typeof raw!=='string'||!/^[1-9]\d{0,2}$/.test(raw)) throw new RelayError('INVALID_PAGE_LIMIT');
  const n=Number(raw);
  if (n>100) throw new RelayError('INVALID_PAGE_LIMIT');
  return n;
}

module.exports = { createFinancialRelayHandler };
