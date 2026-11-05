// lib/data/services/hr_and_payroll_service.dart
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';

class HrAndPayrollService {
  HrAndPayrollService({DatabaseHelper? helper}):_helper=helper??DatabaseHelper.instance;
  final DatabaseHelper _helper;
  String _now()=>DateTime.now().toIso8601String();
  String _uuid(String p)=>'$p-${DateTime.now().microsecondsSinceEpoch}';
  double _n(Object? v)=>v is num?v.toDouble():double.tryParse('$v')??0;

  Future<List<Map<String,Object?>>> employees(int branchId)=>_helper.rawQuery('SELECT e.*,p.name_ar,p.phone,COALESCE(b.total_lah,0) total_lah,COALESCE(b.total_alayh,0) total_alayh FROM employees e JOIN parties p ON p.id=e.party_id LEFT JOIN v_party_balance b ON b.party_id=p.id WHERE e.branch_id=? AND p.is_deleted=0 ORDER BY p.name_ar',[branchId]);
  Future<List<Map<String,Object?>>> attendance(int employeeId,String periodCode)=>_helper.rawQuery('SELECT a.*,w.name_ar shift_name FROM employee_attendance a LEFT JOIN work_shifts w ON w.id=a.work_shift_id WHERE a.employee_id=? AND substr(a.work_date,1,7)=? ORDER BY a.work_date',[employeeId,periodCode]);

  Future<int> registerAttendance({required int employeeId,required String workDate,required String status,int? workShiftId,String? checkIn,String? checkOut,double overtimeHours=0}) async {
    if(!['PRESENT','ABSENT','LEAVE','HALF_DAY','OVERTIME'].contains(status))throw ArgumentError('حالة حضور غير صحيحة');
    final db=await _helper.database;
    return db.transaction((tx)async{
      final employeeRows=await tx.query('employees',where:'id=?',whereArgs:[employeeId],limit:1);
      if(employeeRows.isEmpty)throw StateError('الموظف غير موجود');
      final employee=employeeRows.first;final daily=employee['pay_type']=='DAILY';
      final rate=_n(employee['pay_rate']);
      final earned=daily?(status=='PRESENT'||status=='OVERTIME'?rate+(overtimeHours*rate/8):status=='HALF_DAY'?rate/2:0):0;
      final existing=await tx.query('employee_attendance',columns:['id'],where:'employee_id=? AND work_date=? AND work_shift_id IS ?',whereArgs:[employeeId,workDate,workShiftId],limit:1);
      final values={'employee_id':employeeId,'work_date':workDate,'work_shift_id':workShiftId,'check_in':checkIn,'check_out':checkOut,'status':status,'overtime_hours':overtimeHours,'wage_earned':earned};
      int attendanceId;
      if(existing.isEmpty){attendanceId=await tx.insert('employee_attendance',values);}else{attendanceId=existing.first['id'] as int;await tx.update('employee_attendance',values,where:'id=?',whereArgs:[attendanceId]);}
      if(daily&&earned>0){
        final prior=await tx.query('lah_alayh_ledger',columns:['id'],where:"doc_type='ATTENDANCE' AND doc_id=? AND entry_type='SALARY_ACCRUAL'",whereArgs:[attendanceId],limit:1);
        if(prior.isEmpty){final partyId=employee['party_id'] as int;await _ledger(tx,partyId:partyId,branchId:employee['branch_id'] as int,entryType:'SALARY_ACCRUAL',lah:earned,docType:'ATTENDANCE',docId:attendanceId,statement:'استحقاق يومية بتاريخ $workDate');}
      }
      return attendanceId;
    });
  }

  Future<int> postEmployeeAdvance({required int employeeId,required int cashAccountId,required double amount,required bool managerApproved,String? managerName,String note='سلفة موظف'}) async {
    if(amount<=0)throw ArgumentError('مبلغ السلفة يجب أن يكون أكبر من صفر');
    final db=await _helper.database;
    return db.transaction((tx)async{
      final rows=await tx.query('employees',where:'id=?',whereArgs:[employeeId],limit:1);
      if(rows.isEmpty)throw StateError('الموظف غير موجود');
      final employee=rows.first;final partyId=employee['party_id'] as int;final branchId=employee['branch_id'] as int;
      final balance=await tx.rawQuery('SELECT COALESCE(SUM(alayh_amount),0)-COALESCE(SUM(lah_amount),0) due FROM lah_alayh_ledger WHERE party_id=?',[partyId]);
      final currentDue=_n(balance.first['due']);
      final monthly=_n(employee['pay_rate'])*(employee['pay_type']=='DAILY'?26:1);
      final ceiling=monthly*_n(employee['max_advance_pct'])/100;
      if(currentDue+amount>ceiling&&!managerApproved)throw StateError('تجاوزت السلفة سقف المسموح؛ يلزم اعتماد المدير');
      final account=await tx.query('cash_accounts',columns:['current_balance','gl_account_id'],where:'id=? AND branch_id=?',whereArgs:[cashAccountId,branchId],limit:1);
      if(account.isEmpty||_n(account.first['current_balance'])<amount)throw StateError('رصيد الصندوق لا يكفي');
      final cashGl=account.first['gl_account_id'] as int;final advanceGl=await _gl(tx,'1202');
      final je=await _journal(tx,branchId,'EMPLOYEE_ADVANCE','سلفة للموظف $partyId');
      await _line(tx,branchId,je,advanceGl,dr:amount,partyId:partyId,memo:note);await _line(tx,branchId,je,cashGl,cr:amount,memo:note);
      final voucher=await tx.insert('vouchers',{'uuid':_uuid('voucher'),'branch_id':branchId,'created_at':_now(),'updated_at':_now(),'voucher_no':'ADV-${DateTime.now().millisecondsSinceEpoch}','voucher_type':'PAYMENT','voucher_date':_now(),'party_id':partyId,'cash_account_id':cashAccountId,'amount':amount,'method':'CASH','description':note,'journal_entry_id':je});
      await _cash(tx,branchId,cashAccountId,amount,'OUT','ADVANCE','VOUCHER',voucher,note);
      await _ledger(tx,partyId:partyId,branchId:branchId,entryType:'EMPLOYEE_ADVANCE',alayh:amount,docType:'VOUCHER',docId:voucher,je:je,statement:note);
      return voucher;
    });
  }

  Future<int> recordAdjustment({required int employeeId,required double amount,required bool isBonus,required String reason}) async {
    if(amount<=0||reason.trim().length<3)throw ArgumentError('أدخل مبلغاً صحيحاً وبياناً واضحاً');
    final db=await _helper.database;
    return db.transaction((tx)async{
      final e=await tx.query('employees',where:'id=?',whereArgs:[employeeId],limit:1);if(e.isEmpty)throw StateError('الموظف غير موجود');
      final row=e.first;return _ledger(tx,partyId:row['party_id'] as int,branchId:row['branch_id'] as int,entryType:isBonus?'EMPLOYEE_BONUS':'EMPLOYEE_DEDUCTION',lah:isBonus?amount:0,alayh:isBonus?0:amount,docType:'HR_ADJUSTMENT',statement:reason);
    });
  }

  Future<int> generatePayroll({required int employeeId,required String periodCode}) async {
    if(!RegExp(r'^\d{4}-\d{2}$').hasMatch(periodCode))throw ArgumentError('صيغة الفترة يجب أن تكون YYYY-MM');
    final db=await _helper.database;
    return db.transaction((tx)async{
      final employees=await tx.query('employees',where:'id=?',whereArgs:[employeeId],limit:1);if(employees.isEmpty)throw StateError('الموظف غير موجود');
      final e=employees.first;final partyId=e['party_id'] as int;
      final existing=await tx.query('payroll_runs',where:'employee_id=? AND period_code=?',whereArgs:[employeeId,periodCode],limit:1);
      if(existing.isNotEmpty&&existing.first['status']!='DRAFT')throw StateError('المسير معتمد ولا يمكن إعادة توليده');
      double gross=0;
      if(e['pay_type']=='MONTHLY'){
        gross=_n(e['pay_rate']);
        final accrual=await tx.query('lah_alayh_ledger',columns:['id'],where:"party_id=? AND entry_type='SALARY_ACCRUAL' AND doc_type='PAYROLL' AND statement_ar=?",whereArgs:[partyId,'استحقاق راتب $periodCode'],limit:1);
        if(accrual.isEmpty)await _ledger(tx,partyId:partyId,branchId:e['branch_id'] as int,entryType:'SALARY_ACCRUAL',lah:gross,docType:'PAYROLL',statement:'استحقاق راتب $periodCode');
      }else{
        final attendance=await tx.rawQuery("SELECT COALESCE(SUM(wage_earned),0) total FROM employee_attendance WHERE employee_id=? AND substr(work_date,1,7)=?",[employeeId,periodCode]);
        gross=_n(attendance.first['total']);
      }
      final movements=await tx.rawQuery("SELECT COALESCE(SUM(CASE WHEN entry_type IN('EMPLOYEE_BONUS') THEN lah_amount ELSE 0 END),0) bonuses,COALESCE(SUM(CASE WHEN entry_type IN('EMPLOYEE_ADVANCE','EMPLOYEE_DEDUCTION','CASHIER_SHORTAGE') THEN alayh_amount ELSE 0 END),0) deductions FROM lah_alayh_ledger WHERE party_id=? AND substr(entry_date,1,7)=?",[partyId,periodCode]);
      final bonuses=_n(movements.first['bonuses']);final due=_n(movements.first['deductions']);
      final advances=await tx.rawQuery("SELECT COALESCE(SUM(alayh_amount),0) total FROM lah_alayh_ledger WHERE party_id=? AND entry_type='EMPLOYEE_ADVANCE' AND substr(entry_date,1,7)=?",[partyId,periodCode]);
      final advanceAmount=_n(advances.first['total']);final deductions=(due-advanceAmount).clamp(0,double.infinity).toDouble();
      final net=gross+bonuses-advanceAmount-deductions;
      if(net<0)throw StateError('الاستقطاعات تتجاوز الاستحقاقات؛ راجع المسير قبل الاعتماد');
      final values={'employee_id':employeeId,'period_code':periodCode,'gross_lah':gross,'bonuses_lah':bonuses,'advances_alayh':advanceAmount,'deductions_alayh':deductions,'net_amount':net,'status':'DRAFT'};
      if(existing.isEmpty)return tx.insert('payroll_runs',values);
      final id=existing.first['id'] as int;await tx.update('payroll_runs',values,where:'id=?',whereArgs:[id]);return id;
    });
  }

  Future<void> approvePayroll(int payrollId) async {final db=await _helper.database;final n=await db.update('payroll_runs',{'status':'APPROVED'},where:"id=? AND status='DRAFT'",whereArgs:[payrollId]);if(n!=1)throw StateError('المسير غير موجود أو ليس في حالة مسودة');}

  Future<int> payPayroll({required int payrollId,required int cashAccountId}) async {
    final db=await _helper.database;
    return db.transaction((tx)async{
      final rows=await tx.query('payroll_runs',where:"id=? AND status='APPROVED'",whereArgs:[payrollId],limit:1);if(rows.isEmpty)throw StateError('اعتمد المسير أولاً');
      final p=rows.first;final employee=(await tx.query('employees',where:'id=?',whereArgs:[p['employee_id']],limit:1)).first;final amount=_n(p['net_amount']);if(amount<=0)throw StateError('لا يوجد صافي مستحق للصرف');
      final branchId=employee['branch_id'] as int;final partyId=employee['party_id'] as int;final cash=(await tx.query('cash_accounts',columns:['current_balance','gl_account_id'],where:'id=? AND branch_id=?',whereArgs:[cashAccountId,branchId],limit:1)).first;if(_n(cash['current_balance'])<amount)throw StateError('رصيد الصندوق لا يكفي');
      final cashGl=cash['gl_account_id'] as int;final payable=await _gl(tx,'2301');final je=await _journal(tx,branchId,'PAYROLL_PAYMENT','صرف راتب ${p['period_code']}');
      await _line(tx,branchId,je,payable,dr:amount,partyId:partyId,memo:'صرف صافي الراتب');await _line(tx,branchId,je,cashGl,cr:amount,memo:'صرف صافي الراتب');
      final voucher=await tx.insert('vouchers',{'uuid':_uuid('voucher'),'branch_id':branchId,'created_at':_now(),'updated_at':_now(),'voucher_no':'PAY-${DateTime.now().millisecondsSinceEpoch}','voucher_type':'PAYMENT','voucher_date':_now(),'party_id':partyId,'cash_account_id':cashAccountId,'amount':amount,'method':'CASH','description':'صرف صافي راتب ${p['period_code']}','journal_entry_id':je});
      await _cash(tx,branchId,cashAccountId,amount,'OUT','SALARY','VOUCHER',voucher,'صرف صافي الراتب');
      await _ledger(tx,partyId:partyId,branchId:branchId,entryType:'PAYROLL_PAYMENT',alayh:amount,docType:'VOUCHER',docId:voucher,je:je,statement:'صرف صافي راتب ${p['period_code']}');
      await tx.update('payroll_runs',{'status':'PAID','paid_voucher_id':voucher},where:'id=?',whereArgs:[payrollId]);
      return voucher;
    });
  }

  Future<int> _ledger(DatabaseExecutor tx,{required int partyId,required int branchId,required String entryType,double alayh=0,double lah=0,String docType='HR',int? docId,int? je,required String statement}) async=>tx.insert('lah_alayh_ledger',{'uuid':_uuid('ledger'),'branch_id':branchId,'created_at':_now(),'updated_at':_now(),'party_id':partyId,'entry_date':_now(),'entry_type':entryType,'alayh_amount':alayh,'lah_amount':lah,'doc_type':docType,'doc_id':docId,'journal_entry_id':je,'statement_ar':statement});
  Future<int> _gl(DatabaseExecutor tx,String code) async {final r=await tx.query('chart_of_accounts',columns:['id'],where:'code=?',whereArgs:[code],limit:1);if(r.isEmpty)throw StateError('الحساب $code غير موجود');return r.first['id'] as int;}
  Future<int> _journal(DatabaseExecutor tx,int branchId,String source,String description) async=>tx.insert('journal_entries',{'uuid':_uuid('je'),'branch_id':branchId,'created_at':_now(),'updated_at':_now(),'entry_no':'HR-${DateTime.now().microsecondsSinceEpoch}','entry_date':_now(),'description':description,'source_type':source,'is_posted':1});
  Future<void> _line(DatabaseExecutor tx,int branchId,int je,int account,{double dr=0,double cr=0,int? partyId,String? memo}) async {await tx.insert('journal_lines',{'uuid':_uuid('jl'),'branch_id':branchId,'created_at':_now(),'updated_at':_now(),'journal_entry_id':je,'account_id':account,'party_id':partyId,'dr_amount':dr,'cr_amount':cr,'memo':memo});}
  Future<void> _cash(DatabaseExecutor tx,int branchId,int account,double amount,String direction,String type,String docType,int docId,String note) async {final r=await tx.query('cash_accounts',columns:['current_balance'],where:'id=?',whereArgs:[account],limit:1);final balance=_n(r.first['current_balance'])-amount;await tx.update('cash_accounts',{'current_balance':balance,'updated_at':_now()},where:'id=?',whereArgs:[account]);await tx.insert('cash_transactions',{'cash_account_id':account,'tx_date':_now(),'direction':direction,'amount':amount,'tx_type':type,'doc_type':docType,'doc_id':docId,'balance_after':balance,'note':note,'branch_id':branchId});}
}
