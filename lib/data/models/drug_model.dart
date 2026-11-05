class DrugModel {
  const DrugModel({
    this.id, this.uuid, this.branchId = 1, this.createdAt, this.updatedAt, this.isDeleted = false, this.syncStatus = 'LOCAL', this.syncVersion = 1,
    this.internalCode = '', this.isActive = true, this.completenessPct = 0,
    this.tradeNameAr = '', this.tradeNameEn = '', this.manufacturerId, this.scientificName = '', this.activeIngredientId,
    this.ingredientsJson = '[]', this.chemicalComposition = '', this.categoryId, this.therapeuticClass = '', this.pharmacologicClass = '', this.atcCode = '',
    this.dosageForm = 'OTHER', this.strengthText = '', this.strengthValue, this.strengthUnit = '', this.route = 'OTHER', this.isStripBased = false,
    this.indications = '', this.dosageAdministration = '', this.adultDoseMinMg, this.adultDoseMaxMgPerDay, this.doseFrequencyText = '', this.takeWithFood = 'ANY', this.labelDoseTextAr = '',
    this.contraindications = '', this.contraindicationsJson = '[]', this.warningsPrecautions = '', this.blackBoxWarning = '', this.warningsJson = '[]',
    this.interactionsSummary = '', this.hasCriticalInteractions = false, this.sideEffectsCommon = '', this.sideEffectsSerious = '',
    this.stripsPerPack = 1, this.unitsPerStrip = 1, this.unitsPerPack = 1, this.costPricePack = 0, this.lastPurchaseCostPack = 0,
    this.sellPricePack = 0, this.sellPriceStrip = 0, this.sellPriceUnit = 0, this.stripPriceMode = 'AUTO', this.profitMarginPct = 0,
    this.publicPricePack = 0, this.taxRatePct = 0, this.minStockUnits = 0, this.reorderQtyPacks = 0, this.stockTotalUnits = 0,
    this.minAgeMonths, this.maxAgeMonths, this.allowedPopulationsJson = '[]',
    this.hepaticStatus = 'UNKNOWN', this.hepaticNotes = '', this.renalStatus = 'UNKNOWN', this.renalNotes = '', this.isNephrotoxic = false,
    this.geriatricStatus = 'UNKNOWN', this.geriatricNotes = '', this.beersCriteria = '', this.geriatricAgeThreshold = 65,
    this.pediatricStatus = 'UNKNOWN', this.pediatricNotes = '', this.pedDoseMgPerKgMin, this.pedDoseMgPerKgMax, this.pedMaxDailyMgPerKg, this.pedDosesPerDay, this.neonateAllowed = false,
    this.pregnancyCategory = 'UNKNOWN', this.pregnancyNotes = '', this.pregnancyTrimesterJson = '{}',
    this.lactationRisk = 'UNKNOWN', this.lactationNotes = '',
    this.storageConditions = '', this.storageTempMinC, this.storageTempMaxC, this.requiresRefrigeration = false, this.protectFromLight = false,
    this.barcodeInternational = '', this.barcodeLocal = '', this.registrationNo = '', this.isControlled = false, this.controlledSchedule = '',
    this.requiresPrescription = false, this.prescriptionRestricted = false, this.isAntibiotic = false,
  });

  final int? id, branchId, manufacturerId, activeIngredientId, categoryId, stripsPerPack, unitsPerStrip, unitsPerPack, stockTotalUnits, minStockUnits, reorderQtyPacks, minAgeMonths, maxAgeMonths, geriatricAgeThreshold, pedDosesPerDay;
  final String? uuid, createdAt, updatedAt;
  final bool isDeleted, isActive, isStripBased, hasCriticalInteractions, isNephrotoxic, neonateAllowed, requiresRefrigeration, protectFromLight, isControlled, requiresPrescription, prescriptionRestricted, isAntibiotic;
  final String syncStatus, internalCode, tradeNameAr, tradeNameEn, scientificName, ingredientsJson, chemicalComposition, therapeuticClass, pharmacologicClass, atcCode, dosageForm, strengthText, strengthUnit, route, indications, dosageAdministration, doseFrequencyText, takeWithFood, labelDoseTextAr, contraindications, contraindicationsJson, warningsPrecautions, blackBoxWarning, warningsJson, interactionsSummary, sideEffectsCommon, sideEffectsSerious, stripPriceMode, allowedPopulationsJson, hepaticStatus, hepaticNotes, renalStatus, renalNotes, geriatricStatus, geriatricNotes, beersCriteria, pediatricStatus, pediatricNotes, pregnancyCategory, pregnancyNotes, pregnancyTrimesterJson, lactationRisk, lactationNotes, storageConditions, barcodeInternational, barcodeLocal, registrationNo, controlledSchedule;
  final double? strengthValue, adultDoseMinMg, adultDoseMaxMgPerDay, pedDoseMgPerKgMin, pedDoseMgPerKgMax, pedMaxDailyMgPerKg, storageTempMinC, storageTempMaxC;
  final double costPricePack, lastPurchaseCostPack, sellPricePack, sellPriceStrip, sellPriceUnit, profitMarginPct, publicPricePack, taxRatePct;
  final int syncVersion;
  
  int toBaseUnits(String unit, num quantity) {
    if (quantity <= 0) throw ArgumentError.value(quantity, 'quantity', 'يجب أن تكون الكمية أكبر من صفر');
    final multiplier = switch (unit.toUpperCase()) { 'PACK' => unitsPerPack, 'STRIP' => unitsPerStrip, 'UNIT' => 1, _ => throw ArgumentError('وحدة بيع غير معروفة') };
    return (quantity * multiplier).round();
  }

  double calculateCompletenessPct() {
    final checks = <bool>[
      tradeNameAr.trim().isNotEmpty,
      scientificName.trim().isNotEmpty,
      categoryId != null || atcCode.isNotEmpty,
      dosageForm != 'OTHER' || strengthText.isNotEmpty,
      indications.trim().isNotEmpty,
      dosageAdministration.trim().isNotEmpty,
      contraindications.trim().isNotEmpty,
      warningsPrecautions.trim().isNotEmpty,
      interactionsSummary.trim().isNotEmpty,
      sideEffectsCommon.trim().isNotEmpty || sideEffectsSerious.trim().isNotEmpty,
      stripsPerPack > 0 && unitsPerStrip > 0 && sellPricePack >= 0,
      allowedPopulationsJson.trim().isNotEmpty,
      hepaticStatus != 'UNKNOWN' || hepaticNotes.isNotEmpty,
      renalStatus != 'UNKNOWN' || renalNotes.isNotEmpty,
      geriatricStatus != 'UNKNOWN' || geriatricNotes.isNotEmpty,
      pediatricStatus != 'UNKNOWN' || pediatricNotes.isNotEmpty,
      pregnancyCategory != 'UNKNOWN' || pregnancyNotes.isNotEmpty,
      lactationRisk != 'UNKNOWN' || lactationNotes.isNotEmpty,
      storageConditions.isNotEmpty || barcodeInternational.isNotEmpty || barcodeLocal.isNotEmpty,
    ];
    return checks.where((e) => e).length * 100 / 19;
  }

  Map<String,Object?> toMap() => {
    'id':id,'uuid':uuid,'branch_id':branchId,'created_at':createdAt,'updated_at':updatedAt,'is_deleted':isDeleted?1:0,'sync_status':syncStatus,'sync_version':syncVersion,
    'internal_code':internalCode,'is_active':isActive?1:0,'completeness_pct':calculateCompletenessPct(),
    'trade_name_ar':tradeNameAr,'trade_name_en':tradeNameEn,'manufacturer_id':manufacturerId,'scientific_name':scientificName,'active_ingredient_id':activeIngredientId,'ingredients_json':ingredientsJson,'chemical_composition':chemicalComposition,
    'category_id':categoryId,'therapeutic_class':therapeuticClass,'pharmacologic_class':pharmacologicClass,'atc_code':atcCode,
    'dosage_form':dosageForm,'strength_text':strengthText,'strength_value':strengthValue,'strength_unit':strengthUnit,'route':route,'is_strip_based':isStripBased?1:0,
    'indications':indications,'dosage_administration':dosageAdministration,'adult_dose_min_mg':adultDoseMinMg,'adult_dose_max_mg_per_day':adultDoseMaxMgPerDay,'dose_frequency_text':doseFrequencyText,'take_with_food':takeWithFood,'label_dose_text_ar':labelDoseTextAr,
    'contraindications':contraindications,'contraindications_json':contraindicationsJson,'warnings_precautions':warningsPrecautions,'black_box_warning':blackBoxWarning,'warnings_json':warningsJson,
    'interactions_summary':interactionsSummary,'has_critical_interactions':hasCriticalInteractions?1:0,'side_effects_common':sideEffectsCommon,'side_effects_serious':sideEffectsSerious,
    'strips_per_pack':stripsPerPack,'units_per_strip':unitsPerStrip,'units_per_pack':stripsPerPack*unitsPerStrip,'cost_price_pack':costPricePack,'last_purchase_cost_pack':lastPurchaseCostPack,'sell_price_pack':sellPricePack,'sell_price_strip':sellPriceStrip,'sell_price_unit':sellPriceUnit,'strip_price_mode':stripPriceMode,'profit_margin_pct':profitMarginPct,'public_price_pack':publicPricePack,'tax_rate_pct':taxRatePct,'min_stock_units':minStockUnits,'reorder_qty_packs':reorderQtyPacks,'stock_total_units':stockTotalUnits,
    'min_age_months':minAgeMonths,'max_age_months':maxAgeMonths,'allowed_populations_json':allowedPopulationsJson,
    'hepatic_status':hepaticStatus,'hepatic_notes':hepaticNotes,'renal_status':renalStatus,'renal_notes':renalNotes,'is_nephrotoxic':isNephrotoxic?1:0,
    'geriatric_status':geriatricStatus,'geriatric_notes':geriatricNotes,'beers_criteria':beersCriteria,'geriatric_age_threshold':geriatricAgeThreshold,
    'pediatric_status':pediatricStatus,'pediatric_notes':pediatricNotes,'ped_dose_mg_per_kg_min':pedDoseMgPerKgMin,'ped_dose_mg_per_kg_max':pedDoseMgPerKgMax,'ped_max_daily_mg_per_kg':pedMaxDailyMgPerKg,'ped_doses_per_day':pedDosesPerDay,'neonate_allowed':neonateAllowed?1:0,
    'pregnancy_category':pregnancyCategory,'pregnancy_notes':pregnancyNotes,'pregnancy_trimester_json':pregnancyTrimesterJson,'lactation_risk':lactationRisk,'lactation_notes':lactationNotes,
    'storage_conditions':storageConditions,'storage_temp_min_c':storageTempMinC,'storage_temp_max_c':storageTempMaxC,'requires_refrigeration':requiresRefrigeration?1:0,'protect_from_light':protectFromLight?1:0,'barcode_international':barcodeInternational.isEmpty?null:barcodeInternational,'barcode_local':barcodeLocal.isEmpty?null:barcodeLocal,'registration_no':registrationNo,'is_controlled':isControlled?1:0,'controlled_schedule':controlledSchedule,'requires_prescription':requiresPrescription?1:0,'prescription_restricted':prescriptionRestricted?1:0,'is_antibiotic':isAntibiotic?1:0
  };

  factory DrugModel.fromMap(Map<String,Object?> m) {
    int? integer(String k) => m[k] as int?;
    double? decimal(String k) => (m[k] as num?)?.toDouble();
    String str(String k,[String d='']) => m[k] as String? ?? d;
    bool flag(String k) => (m[k] as num? ?? 0) != 0;
    return DrugModel(
      id:integer('id'),uuid:str('uuid').isEmpty?null:str('uuid'),branchId:integer('branch_id')??1,createdAt:str('created_at').isEmpty?null:str('created_at'),updatedAt:str('updated_at').isEmpty?null:str('updated_at'),isDeleted:flag('is_deleted'),syncStatus:str('sync_status','LOCAL'),syncVersion:integer('sync_version')??1,
      internalCode:str('internal_code'),isActive:!m.containsKey('is_active')||flag('is_active'),completenessPct:decimal('completeness_pct')??0,
      tradeNameAr:str('trade_name_ar'),tradeNameEn:str('trade_name_en'),manufacturerId:integer('manufacturer_id'),scientificName:str('scientific_name'),activeIngredientId:integer('active_ingredient_id'),ingredientsJson:str('ingredients_json','[]'),chemicalComposition:str('chemical_composition'),
      categoryId:integer('category_id'),therapeuticClass:str('therapeutic_class'),pharmacologicClass:str('pharmacologic_class'),atcCode:str('atc_code'),
      dosageForm:str('dosage_form','OTHER'),strengthText:str('strength_text'),strengthValue:decimal('strength_value'),strengthUnit:str('strength_unit'),route:str('route','OTHER'),isStripBased:flag('is_strip_based'),
      indications:str('indications'),dosageAdministration:str('dosage_administration'),adultDoseMinMg:decimal('adult_dose_min_mg'),adultDoseMaxMgPerDay:decimal('adult_dose_max_mg_per_day'),doseFrequencyText:str('dose_frequency_text'),takeWithFood:str('take_with_food','ANY'),labelDoseTextAr:str('label_dose_text_ar'),
      contraindications:str('contraindications'),contraindicationsJson:str('contraindications_json','[]'),warningsPrecautions:str('warnings_precautions'),blackBoxWarning:str('black_box_warning'),warningsJson:str('warnings_json','[]'),
      interactionsSummary:str('interactions_summary'),hasCriticalInteractions:flag('has_critical_interactions'),sideEffectsCommon:str('side_effects_common'),sideEffectsSerious:str('side_effects_serious'),
      stripsPerPack:integer('strips_per_pack')??1,unitsPerStrip:integer('units_per_strip')??1,unitsPerPack:integer('units_per_pack')??1,costPricePack:decimal('cost_price_pack')??0,lastPurchaseCostPack:decimal('last_purchase_cost_pack')??0,sellPricePack:decimal('sell_price_pack')??0,sellPriceStrip:decimal('sell_price_strip')??0,sellPriceUnit:decimal('sell_price_unit')??0,stripPriceMode:str('strip_price_mode','AUTO'),profitMarginPct:decimal('profit_margin_pct')??0,publicPricePack:decimal('public_price_pack')??0,taxRatePct:decimal('tax_rate_pct')??0,minStockUnits:integer('min_stock_units')??0,reorderQtyPacks:integer('reorder_qty_packs')??0,stockTotalUnits:integer('stock_total_units')??0,
      minAgeMonths:integer('min_age_months'),maxAgeMonths:integer('max_age_months'),allowedPopulationsJson:str('allowed_populations_json','[]'),
      hepaticStatus:str('hepatic_status','UNKNOWN'),hepaticNotes:str('hepatic_notes'),renalStatus:str('renal_status','UNKNOWN'),renalNotes:str('renal_notes'),isNephrotoxic:flag('is_nephrotoxic'),
      geriatricStatus:str('geriatric_status','UNKNOWN'),geriatricNotes:str('geriatric_notes'),beersCriteria:str('beers_criteria'),geriatricAgeThreshold:integer('geriatric_age_threshold')??65,
      pediatricStatus:str('pediatric_status','UNKNOWN'),pediatricNotes:str('pediatric_notes'),pedDoseMgPerKgMin:decimal('ped_dose_mg_per_kg_min'),pedDoseMgPerKgMax:decimal('ped_dose_mg_per_kg_max'),pedMaxDailyMgPerKg:decimal('ped_max_daily_mg_per_kg'),pedDosesPerDay:integer('ped_doses_per_day'),neonateAllowed:flag('neonate_allowed'),
      pregnancyCategory:str('pregnancy_category','UNKNOWN'),pregnancyNotes:str('pregnancy_notes'),pregnancyTrimesterJson:str('pregnancy_trimester_json','{}'),lactationRisk:str('lactation_risk','UNKNOWN'),lactationNotes:str('lactation_notes'),
      storageConditions:str('storage_conditions'),storageTempMinC:decimal('storage_temp_min_c'),storageTempMaxC:decimal('storage_temp_max_c'),requiresRefrigeration:flag('requires_refrigeration'),protectFromLight:flag('protect_from_light'),barcodeInternational:str('barcode_international'),barcodeLocal:str('barcode_local'),registrationNo:str('registration_no'),isControlled:flag('is_controlled'),controlledSchedule:str('controlled_schedule'),requiresPrescription:flag('requires_prescription'),prescriptionRestricted:flag('prescription_restricted'),isAntibiotic:flag('is_antibiotic'),
    );
  }
}
