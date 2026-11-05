import 'package:sqflite/sqflite.dart';

abstract final class SchemaIteration2 {
  static Future<void> upgrade(DatabaseExecutor db) async {
    final statements=<String>[
      """CREATE TABLE IF NOT EXISTS warehouses(id INTEGER PRIMARY KEY AUTOINCREMENT,branch_id INTEGER NOT NULL DEFAULT 1,code TEXT NOT NULL UNIQUE,name_ar TEXT NOT NULL,wh_type TEXT NOT NULL CHECK(wh_type IN('PHARMACY_FLOOR','MAIN_STORE','FRIDGE','CONTROLLED_CABINET','QUARANTINE','DAMAGED')),is_sellable INTEGER NOT NULL DEFAULT 1 CHECK(is_sellable IN(0,1)),created_at TEXT NOT NULL)""",
      """CREATE TABLE IF NOT EXISTS shelf_locations(id INTEGER PRIMARY KEY AUTOINCREMENT,warehouse_id INTEGER NOT NULL,code TEXT NOT NULL,description TEXT,is_fridge INTEGER NOT NULL DEFAULT 0 CHECK(is_fridge IN(0,1)),UNIQUE(warehouse_id,code),FOREIGN KEY(warehouse_id) REFERENCES warehouses(id))""",
      """CREATE TABLE IF NOT EXISTS cold_chain_log(id INTEGER PRIMARY KEY AUTOINCREMENT,warehouse_id INTEGER NOT NULL,reading_at TEXT NOT NULL,temp_c REAL NOT NULL,humidity_pct REAL,is_out_of_range INTEGER NOT NULL,corrective_action TEXT,recorded_by INTEGER,FOREIGN KEY(warehouse_id) REFERENCES warehouses(id))""",
      """CREATE TABLE IF NOT EXISTS batches_fefo(id INTEGER PRIMARY KEY AUTOINCREMENT,drug_id INTEGER NOT NULL,warehouse_id INTEGER NOT NULL,location_id INTEGER,batch_no TEXT NOT NULL,expiry_date TEXT NOT NULL,manufacture_date TEXT,sealed_packs INTEGER NOT NULL DEFAULT 0 CHECK(sealed_packs>=0),loose_units INTEGER NOT NULL DEFAULT 0 CHECK(loose_units>=0),total_units INTEGER NOT NULL DEFAULT 0 CHECK(total_units>=0),unit_cost REAL NOT NULL DEFAULT 0,pack_cost REAL NOT NULL DEFAULT 0,purchase_invoice_item_id INTEGER,status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK(status IN('ACTIVE','QUARANTINED','EXPIRED','DEPLETED','RETURNED_TO_SUPPLIER','DISPOSED')),UNIQUE(drug_id,warehouse_id,batch_no,expiry_date),FOREIGN KEY(drug_id) REFERENCES drugs(id),FOREIGN KEY(warehouse_id) REFERENCES warehouses(id),FOREIGN KEY(location_id) REFERENCES shelf_locations(id))""",
      """CREATE TABLE IF NOT EXISTS stock_movements(id INTEGER PRIMARY KEY AUTOINCREMENT,drug_id INTEGER NOT NULL,batch_id INTEGER NOT NULL,warehouse_id INTEGER NOT NULL,movement_type TEXT NOT NULL,qty_units INTEGER NOT NULL CHECK(qty_units<>0 OR movement_type='PACK_OPEN'),unit_cost REAL NOT NULL DEFAULT 0,unit_price REAL NOT NULL DEFAULT 0,balance_after_units INTEGER NOT NULL,doc_type TEXT,doc_id INTEGER,doc_line_id INTEGER,movement_at TEXT NOT NULL,note TEXT)""",
      """CREATE TABLE IF NOT EXISTS sales_invoice_item_batches(id INTEGER PRIMARY KEY AUTOINCREMENT,invoice_item_id INTEGER NOT NULL,batch_id INTEGER NOT NULL,qty_units INTEGER NOT NULL CHECK(qty_units>0),unit_cost REAL NOT NULL,returned_qty_units INTEGER NOT NULL DEFAULT 0 CHECK(returned_qty_units>=0),FOREIGN KEY(batch_id) REFERENCES batches_fefo(id))""",
      """CREATE TABLE IF NOT EXISTS stocktaking_sessions(id INTEGER PRIMARY KEY AUTOINCREMENT,session_no TEXT NOT NULL UNIQUE,warehouse_id INTEGER NOT NULL,scope_type TEXT NOT NULL,blind_count INTEGER NOT NULL DEFAULT 0,status TEXT NOT NULL DEFAULT 'DRAFT' CHECK(status IN('DRAFT','COUNTING','REVIEW','APPROVED')),created_at TEXT NOT NULL,approved_at TEXT,approved_by INTEGER)""",
      """CREATE TABLE IF NOT EXISTS stocktaking_lines(id INTEGER PRIMARY KEY AUTOINCREMENT,session_id INTEGER NOT NULL,batch_id INTEGER NOT NULL,system_units INTEGER NOT NULL,counted_packs INTEGER NOT NULL DEFAULT 0,counted_loose_units INTEGER NOT NULL DEFAULT 0,counted_units INTEGER NOT NULL DEFAULT 0,diff_units INTEGER NOT NULL DEFAULT 0,unit_cost REAL NOT NULL DEFAULT 0,diff_value REAL NOT NULL DEFAULT 0,reason_code TEXT,UNIQUE(session_id,batch_id),FOREIGN KEY(session_id) REFERENCES stocktaking_sessions(id),FOREIGN KEY(batch_id) REFERENCES batches_fefo(id))""",
      """CREATE TABLE IF NOT EXISTS disposals(id INTEGER PRIMARY KEY AUTOINCREMENT,disposal_no TEXT NOT NULL UNIQUE,disposal_date TEXT NOT NULL,reason TEXT NOT NULL CHECK(reason IN('EXPIRED','BROKEN','DAMAGED_STORAGE','RECALL','CONTAMINATED')),method TEXT,authority_ref TEXT,witness_name TEXT,status TEXT NOT NULL DEFAULT 'DRAFT',total_cost_value REAL NOT NULL DEFAULT 0,journal_entry_id INTEGER)""",
      """CREATE TABLE IF NOT EXISTS disposal_items(id INTEGER PRIMARY KEY AUTOINCREMENT,disposal_id INTEGER NOT NULL,batch_id INTEGER NOT NULL,qty_units INTEGER NOT NULL CHECK(qty_units>0),unit_cost REAL NOT NULL,recoverable_from_supplier INTEGER NOT NULL DEFAULT 0,FOREIGN KEY(disposal_id) REFERENCES disposals(id),FOREIGN KEY(batch_id) REFERENCES batches_fefo(id))""",
      """CREATE TABLE IF NOT EXISTS stock_transfers(id INTEGER PRIMARY KEY AUTOINCREMENT,transfer_no TEXT NOT NULL UNIQUE,transfer_type TEXT NOT NULL,from_warehouse_id INTEGER NOT NULL,to_warehouse_id INTEGER NOT NULL,status TEXT NOT NULL DEFAULT 'DRAFT' CHECK(status IN('DRAFT','IN_TRANSIT','RECEIVED')),created_at TEXT NOT NULL,received_at TEXT)""",
      """CREATE TABLE IF NOT EXISTS stock_transfer_items(id INTEGER PRIMARY KEY AUTOINCREMENT,transfer_id INTEGER NOT NULL,from_batch_id INTEGER NOT NULL,to_batch_id INTEGER,qty_units INTEGER NOT NULL CHECK(qty_units>0),received_qty_units INTEGER NOT NULL DEFAULT 0,unit_cost REAL NOT NULL,FOREIGN KEY(transfer_id) REFERENCES stock_transfers(id),FOREIGN KEY(from_batch_id) REFERENCES batches_fefo(id),FOREIGN KEY(to_batch_id) REFERENCES batches_fefo(id))""",
      """CREATE TABLE IF NOT EXISTS purchase_orders(id INTEGER PRIMARY KEY AUTOINCREMENT,po_no TEXT NOT NULL UNIQUE,supplier_party_id INTEGER NOT NULL,po_date TEXT NOT NULL,origin TEXT NOT NULL CHECK(origin IN('MANUAL','AUTO_SHORTAGE')),status TEXT NOT NULL DEFAULT 'DRAFT',estimated_total REAL NOT NULL DEFAULT 0)""",
      """CREATE TABLE IF NOT EXISTS purchase_order_items(id INTEGER PRIMARY KEY AUTOINCREMENT,po_id INTEGER NOT NULL,drug_id INTEGER NOT NULL,qty_packs INTEGER NOT NULL,received_packs INTEGER NOT NULL DEFAULT 0,expected_cost_pack REAL NOT NULL,expected_bonus_packs INTEGER NOT NULL DEFAULT 0,FOREIGN KEY(po_id) REFERENCES purchase_orders(id),FOREIGN KEY(drug_id) REFERENCES drugs(id))""",
      """CREATE TABLE IF NOT EXISTS purchase_invoices(id INTEGER PRIMARY KEY AUTOINCREMENT,invoice_no TEXT NOT NULL UNIQUE,supplier_invoice_no TEXT,supplier_party_id INTEGER NOT NULL,po_id INTEGER,warehouse_id INTEGER NOT NULL,invoice_date TEXT NOT NULL,due_date TEXT,payment_type TEXT NOT NULL CHECK(payment_type IN('CASH','CREDIT','PARTIAL')),subtotal REAL NOT NULL,discount_pct REAL NOT NULL DEFAULT 0,discount_amount REAL NOT NULL DEFAULT 0,tax_amount REAL NOT NULL DEFAULT 0,net_total REAL NOT NULL,paid_total REAL NOT NULL DEFAULT 0,remaining_lah REAL NOT NULL DEFAULT 0,status TEXT NOT NULL DEFAULT 'POSTED',journal_entry_id INTEGER,UNIQUE(supplier_party_id,supplier_invoice_no))""",
      """CREATE TABLE IF NOT EXISTS purchase_invoice_items(id INTEGER PRIMARY KEY AUTOINCREMENT,invoice_id INTEGER NOT NULL,drug_id INTEGER NOT NULL,batch_no TEXT NOT NULL,expiry_date TEXT NOT NULL,location_id INTEGER,qty_packs_paid INTEGER NOT NULL,bonus_packs INTEGER NOT NULL DEFAULT 0,qty_packs_total INTEGER NOT NULL,pack_price REAL NOT NULL,line_discount_pct REAL NOT NULL DEFAULT 0,line_total REAL NOT NULL,effective_pack_cost REAL NOT NULL,new_sell_price_pack REAL NOT NULL DEFAULT 0,FOREIGN KEY(invoice_id) REFERENCES purchase_invoices(id),FOREIGN KEY(drug_id) REFERENCES drugs(id),FOREIGN KEY(location_id) REFERENCES shelf_locations(id))""",
      """CREATE TABLE IF NOT EXISTS purchase_returns(id INTEGER PRIMARY KEY AUTOINCREMENT,return_no TEXT NOT NULL UNIQUE,supplier_party_id INTEGER NOT NULL,return_date TEXT NOT NULL,reason TEXT NOT NULL,settlement_type TEXT NOT NULL CHECK(settlement_type IN('CREDIT_NOTE','CASH_REFUND','EXCHANGE_GOODS')),total_value REAL NOT NULL DEFAULT 0,status TEXT NOT NULL DEFAULT 'DRAFT')""",
      """CREATE TABLE IF NOT EXISTS purchase_return_items(id INTEGER PRIMARY KEY AUTOINCREMENT,return_id INTEGER NOT NULL,batch_id INTEGER NOT NULL,qty_units INTEGER NOT NULL,credit_unit_value REAL NOT NULL,cost_unit_value REAL NOT NULL,FOREIGN KEY(return_id) REFERENCES purchase_returns(id),FOREIGN KEY(batch_id) REFERENCES batches_fefo(id))""",
      """CREATE TABLE IF NOT EXISTS price_history(id INTEGER PRIMARY KEY AUTOINCREMENT,drug_id INTEGER NOT NULL,change_type TEXT NOT NULL CHECK(change_type IN('SELL_PRICE','COST_AVG','LAST_PURCHASE_COST')),old_value REAL NOT NULL,new_value REAL NOT NULL,source_doc_type TEXT,source_doc_id INTEGER,created_at TEXT NOT NULL,FOREIGN KEY(drug_id) REFERENCES drugs(id))""",
      "CREATE INDEX IF NOT EXISTS idx_batches_fefo_expiry ON batches_fefo(status,expiry_date,drug_id)",
      "CREATE INDEX IF NOT EXISTS idx_stock_movements_drug_date ON stock_movements(drug_id,movement_at)",
      "CREATE INDEX IF NOT EXISTS idx_purchase_invoice_supplier ON purchase_invoices(supplier_party_id,invoice_date)",
      """CREATE TRIGGER IF NOT EXISTS trg_stock_movements_no_update BEFORE UPDATE ON stock_movements BEGIN SELECT RAISE(ABORT,'stock_movements is append-only'); END""",
      """CREATE TRIGGER IF NOT EXISTS trg_stock_movements_no_delete BEFORE DELETE ON stock_movements BEGIN SELECT RAISE(ABORT,'stock_movements is append-only'); END""",
      """CREATE VIEW IF NOT EXISTS v_fefo_batch_balances AS SELECT b.*,d.trade_name_ar,s.code shelf_code FROM batches_fefo b JOIN drugs d ON d.id=b.drug_id LEFT JOIN shelf_locations s ON s.id=b.location_id"""
    ];
    for(final sql in statements){await db.execute(sql);}
    await _seedDefaults(db);
  }
  static Future<void> _seedDefaults(DatabaseExecutor db) async {
    final count=Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM warehouses'))??0;
    if(count>0)return;
    final now=DateTime.now().toIso8601String();
    final defs=<List<Object>>[['PHARM','صالة الصيدلية','PHARMACY_FLOOR',1],['MAIN','المخزن الرئيسي','MAIN_STORE',0],['FRIDGE','الثلاجة','FRIDGE',1],['CONTROL','خزانة المراقبة','CONTROLLED_CABINET',0],['QUAR','الحجر','QUARANTINE',0],['DAMAGED','التالف','DAMAGED',0]];
    for(final w in defs){await db.insert('warehouses',{'code':w[0],'name_ar':w[1],'wh_type':w[2],'is_sellable':w[3],'created_at':now});}
    final warehouses=await db.query('warehouses',columns:['id','code']);
    final main=warehouses.firstWhere((r)=>r['code']=='MAIN')['id'] as int;
    final fridge=warehouses.firstWhere((r)=>r['code']=='FRIDGE')['id'] as int;
    final pharmacy=warehouses.firstWhere((r)=>r['code']=='PHARM')['id'] as int;
    final shelves=<List<Object>>[['A-01-01',main,0],['A-01-02',main,0],['A-02-01',main,0],['P-01-01',pharmacy,0],['F-01-01',fridge,1],['F-01-02',fridge,1]];
    for(final shelf in shelves){await db.insert('shelf_locations',{'warehouse_id':shelf[1],'code':shelf[0],'description':'رف \${shelf[0]}','is_fridge':shelf[2]});}
    final drugs=await db.query('drugs',columns:['id','units_per_pack','cost_price_pack','requires_refrigeration','stock_total_units'],where:'is_deleted=0');
    for(var index=0;index<drugs.length;index++){
      final drug=drugs[index];
      final units=(drug['units_per_pack'] as int?)??1;
      if(units<=0)throw StateError('وحدات الباكت غير صالحة للصنف رقم '+drug['id'].toString());
      final cold=(drug['requires_refrigeration'] as int? ?? 0)==1;
      final warehouse=cold?fridge:pharmacy;
      final shelf=await db.query('shelf_locations',columns:['id'],where:'warehouse_id=?',whereArgs:[warehouse],limit:1);
      if(shelf.isEmpty)throw StateError('لا يوجد رف افتراضي للمستودع');
      final originalUnits=(drug['stock_total_units'] as int?)??0;
      final first=originalUnits~/3;
      final second=originalUnits~/3;
      final portions=<int>[first,second,originalUnits-first-second];
      final offsets=<int>[-4,25,55];
      final packCost=(drug['cost_price_pack'] as num? ?? 0).toDouble();
      for(var lot=0;lot<portions.length;lot++){
        final lotUnits=portions[lot];
        if(lotUnits<=0)continue;
        final expiry=DateTime.now().add(Duration(days:offsets[lot])).toIso8601String().substring(0,10);
        await db.insert('batches_fefo',{'drug_id':drug['id'],'warehouse_id':warehouse,'location_id':shelf.first['id'],'batch_no':'SEED-'+(index+1).toString()+'-'+(lot+1).toString(),'expiry_date':expiry,'sealed_packs':lotUnits~/units,'loose_units':lotUnits%units,'total_units':lotUnits,'unit_cost':packCost/units,'pack_cost':packCost,'status':expiry.compareTo(now.substring(0,10))<0?'EXPIRED':'ACTIVE'});
      }
    }
    await db.execute('UPDATE drugs SET stock_total_units=COALESCE((SELECT SUM(total_units) FROM batches_fefo WHERE batches_fefo.drug_id=drugs.id),0)');
  }
}
