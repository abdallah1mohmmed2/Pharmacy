'use strict';

const http = require('node:http');
const admin = require('firebase-admin');
const { createFinancialRelayHandler } = require('./handler');
const { FirestoreFinanceStore } = require('./firestore_store');

if (!admin.apps.length) admin.initializeApp();

// This executable is intentionally OFF by default. Deploy behind HTTPS,
// configure trusted Firebase Auth custom claims, and explicitly enable only
// after an operator approves master-data registration and end-to-end security.
// Never run it using emulator credentials in production.
const enabled = process.env.PHARMACY_FINANCIAL_RELAY_ENABLED === 'true';
const port = Number(process.env.PORT || 8085);
if (!Number.isInteger(port)||port<1||port>65535) throw new Error('Invalid PORT');

const handler = createFinancialRelayHandler({
  verifyIdToken: (token,checkRevoked)=>admin.auth().verifyIdToken(token,checkRevoked),
  store: new FirestoreFinanceStore(admin.firestore()),
  enabled,
});
http.createServer(handler).listen(port,()=>{
  process.stdout.write('Financial relay HTTP server initialized; enabled='+enabled+'\n');
});
