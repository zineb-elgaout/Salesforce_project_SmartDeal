// Admin-only fixture setup. It preserves the existing three Opportunities.
// Reruns update only rows explicitly marked SD_CONTINUATION_DEMO.
String marker='SD_CONTINUATION_DEMO';
Set<String> oppKeys=new Set<String>{'OPP-DEMO-ATLAS-001','OPP-DEMO-EDUNOVA-001',
    'OPP-DEMO-GREENBUILD-001'};
Map<String,Opportunity> opps=new Map<String,Opportunity>();
for(Opportunity opp:[SELECT Id,Name,SmartDeal_Key__c,Feasibility_Status__c,Rescue_Required__c
    FROM Opportunity WHERE SmartDeal_Key__c IN :oppKeys]) {
    opps.put(opp.SmartDeal_Key__c,opp);
}
System.assertEquals(3,opps.size(),'Missing imported opportunities. Run preflight first.');
Set<String> erpKeys=new Set<String>{'ERP-PP-X100','ERP-PE-R100','ERP-LT-B100'};
Set<String> skus=new Set<String>{'PP-X100','PE-R100','LT-B100'};
Map<String,Product2> products=new Map<String,Product2>();
for(Product2 product:[SELECT Id,ProductCode,ERP_Product_ID__c,IsActive FROM Product2
    WHERE ERP_Product_ID__c IN :erpKeys OR ProductCode IN :skus]) {
    System.assert(erpKeys.contains(product.ERP_Product_ID__c),
        'SKU already exists with a different ERP ID: '+product.ProductCode);
    System.assert(!products.containsKey(product.ERP_Product_ID__c),'Duplicate ERP product.');
    products.put(product.ERP_Product_ID__c,product);
}
List<Product2> newProducts=new List<Product2>();
List<String> codes=new List<String>{'PP-X100','PE-R100','LT-B100'};
List<String> names=new List<String>{'Printer Pro X100','Printer Eco R100','Laptop Business B100'};
for(Integer i=0;i<codes.size();i++) {
    String erpId='ERP-'+codes[i];
    if(products.containsKey(erpId)) {
        System.assert(products.get(erpId).ProductCode==codes[i] && products.get(erpId).IsActive,
            'Existing product has unexpected SKU or is inactive: '+erpId);
    } else {
        newProducts.add(new Product2(Name=names[i],ProductCode=codes[i],
            ERP_Product_ID__c=erpId,IsActive=true));
    }
}
if(!newProducts.isEmpty()) insert newProducts;
for(Product2 product:newProducts) products.put(product.ERP_Product_ID__c,product);
Id pp=products.get('ERP-PP-X100').Id;
Id pe=products.get('ERP-PE-R100').Id;
Id laptop=products.get('ERP-LT-B100').Id;
List<Inventory__c> stocks=new List<Inventory__c>{
    new Inventory__c(Inventory_Key__c='PP-X100|SD-CASA',Product__c=pp,
        Warehouse_Code__c='SD-CASA',Warehouse_Name__c='Demo Casa',City__c='Casablanca',
        Available_Quantity__c=5,Reserved_Quantity__c=1,Unit_Price__c=2200,Lead_Time_Days__c=3),
    new Inventory__c(Inventory_Key__c='PP-X100|SD-MARR',Product__c=pp,
        Warehouse_Code__c='SD-MARR',Warehouse_Name__c='Demo Marrakech',City__c='Marrakech',
        Available_Quantity__c=2,Reserved_Quantity__c=0,Unit_Price__c=2180,Lead_Time_Days__c=4),
    new Inventory__c(Inventory_Key__c='PE-R100|SD-AGADIR',Product__c=pe,
        Warehouse_Code__c='SD-AGADIR',Warehouse_Name__c='Demo Agadir',City__c='Agadir',
        Available_Quantity__c=25,Reserved_Quantity__c=5,Unit_Price__c=2000,
        Lead_Time_Days__c=2,Is_Reconditioned__c=true),
    new Inventory__c(Inventory_Key__c='LT-B100|SD-CASA',Product__c=laptop,
        Warehouse_Code__c='SD-CASA',Warehouse_Name__c='Demo Casa',City__c='Casablanca',
        Available_Quantity__c=20,Reserved_Quantity__c=2,Unit_Price__c=8000,Lead_Time_Days__c=7)
};
Set<String> inventoryKeys=new Set<String>();
for(Inventory__c stock:stocks) inventoryKeys.add(stock.Inventory_Key__c);
for(Inventory__c old:[SELECT Inventory_Key__c,ERP_Source__c FROM Inventory__c
    WHERE Inventory_Key__c IN :inventoryKeys]) {
    System.assertEquals(marker,old.ERP_Source__c,'Stock key belongs to another dataset. Stop.');
}
for(Inventory__c stock:stocks) {
    stock.ERP_Source__c=marker; stock.Is_Active__c=true; stock.Last_Updated__c=System.now();
}
upsert stocks Inventory_Key__c;
List<String> orderedKeys=new List<String>{'OPP-DEMO-ATLAS-001','OPP-DEMO-EDUNOVA-001',
    'OPP-DEMO-GREENBUILD-001'};
List<Id> requestProducts=new List<Id>{pp,laptop,pe};
List<Integer> quantities=new List<Integer>{10,25,15};
List<Decimal> budgets=new List<Decimal>{30000,220000,40000};
List<Integer> dateOffsets=new List<Integer>{7,4,7};
Set<Id> oppIds=new Set<Id>();
for(Opportunity opp:opps.values()) oppIds.add(opp.Id);
Map<String,Customer_Request__c> ownedRequests=new Map<String,Customer_Request__c>();
for(Customer_Request__c req:[SELECT Id,Original_Message__c,Opportunity__c FROM Customer_Request__c
    WHERE Opportunity__c IN :oppIds]) {
    if(req.Original_Message__c!=null && req.Original_Message__c.startsWith(marker+'|')) {
        System.assert(!ownedRequests.containsKey(req.Original_Message__c),'Duplicate demo request marker.');
        ownedRequests.put(req.Original_Message__c,req);
    }
}
List<Customer_Request__c> requests=new List<Customer_Request__c>();
for(Integer i=0;i<orderedKeys.size();i++) {
    String original=marker+'|'+orderedKeys[i]+'|Fictitious validated demonstration request';
    Customer_Request__c req=ownedRequests.get(original);
    if(req==null) req=new Customer_Request__c(Original_Message__c=original);
    req.Opportunity__c=opps.get(orderedKeys[i]).Id;
    req.Requested_Product__c=requestProducts[i]; req.Requested_Quantity__c=quantities[i];
    req.Budget__c=budgets[i]; req.Delivery_City__c='Agadir';
    req.Requested_Date__c=Date.today().addDays(dateOffsets[i]);
    req.Validation_Status__c='Validated'; req.Validated_By__c=UserInfo.getUserId();
    req.Validation_Date__c=System.now(); req.Consent_Status__c='Unknown';
    req.Original_Channel__c='Manual'; req.Extraction_Source__c='Manual'; requests.add(req);
}
upsert requests;
Id atlasId=opps.get('OPP-DEMO-ATLAS-001').Id;
Map<String,Rescue_Scenario__c> ownedScenarios=new Map<String,Rescue_Scenario__c>();
for(Rescue_Scenario__c old:[SELECT Id,Assumptions__c,Selected__c,Decision_By__c,Decision_Date__c,
    Decision_Comment__c FROM Rescue_Scenario__c WHERE Opportunity__c=:atlasId]) {
    if(old.Assumptions__c!=null && old.Assumptions__c.startsWith(marker+'|ATLAS|')) {
        String key=old.Assumptions__c.substringBefore(';');
        System.assert(!ownedScenarios.containsKey(key),'Duplicate demo scenario marker.');
        ownedScenarios.put(key,old);
    }
}
List<Rescue_Scenario__c> scenarios=new List<Rescue_Scenario__c>();
for(Integer i=0;i<2;i++) {
    String key=marker+'|ATLAS|'+(i==0?'ALT':'PARTIAL');
    Rescue_Scenario__c scenario=ownedScenarios.get(key);
    if(scenario==null) scenario=new Rescue_Scenario__c(Opportunity__c=atlasId);
    scenario.Scenario_Type__c = (i == 0) ? 'Reconditioned Product' : 'Partial Delivery';
    scenario.Proposed_Product__c = (i == 0) ? pe : pp;
    scenario.Proposed_Quantity__c = (i == 0) ? 10 : 4;
    scenario.Warehouse_Code__c = (i == 0) ? 'SD-AGADIR' : 'SD-CASA';
    scenario.Warehouse_Name__c = (i == 0) ? 'Demo Agadir' : 'Demo Casa';
    scenario.Estimated_Delivery_Date__c = Date.today().addDays((i == 0) ? 2 : 3);
    scenario.Is_Reconditioned__c = (i == 0);
    scenario.Data_Freshness__c = System.now();
    scenario.Availability_Score__c = (i == 0) ? 100 : 40;
    scenario.Service_Score__c = 100;
    scenario.Margin_Score__c = (i == 0) ? 60 : 70;
    scenario.Eco_Score__c = (i == 0) ? 80 : 50;
    scenario.Priority_Score__c = 50;
    scenario.Assumptions__c=key+'; DEMO ONLY. Margin, eco and priority notes are illustrative. '+
        'No measured cost or carbon data. Human product compatibility review required. '+
        (i==1?'Only 4 of 10 units; remaining 6 are unresolved.':'No stock reserved.');
    scenario.Total_Score__c=null; scenario.Rank__c=null;
    scenario.Score_Version__c=null; scenario.Explanation__c=null;
    scenario.Selected__c=false; scenario.Decision_By__c=null;
    scenario.Decision_Date__c=null; scenario.Decision_Comment__c=null;
    scenarios.add(scenario);
}
upsert scenarios;
List<Opportunity> resetOpps=new List<Opportunity>();
for(Opportunity opp:opps.values()) {
    if(opp.Feasibility_Status__c=='Rescued') {
        resetOpps.add(new Opportunity(Id=opp.Id,Feasibility_Status__c='At Risk',
            Rescue_Required__c=true));
    }
}
if(!resetOpps.isEmpty()) update resetOpps;
System.debug(LoggingLevel.ERROR,'DEMO READY: existing Opportunities preserved; '+
    'demo scenario decisions cleared; 4 tagged stock rows, 3 tagged requests, 2 tagged Atlas scenarios.');
for(Customer_Request__c req:requests) {
    System.debug(LoggingLevel.ERROR,'Request '+req.Id+' -> Opportunity '+req.Opportunity__c);
}
