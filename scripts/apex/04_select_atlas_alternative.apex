// OPTIONAL HUMAN DECISION. Replace the demo comment after reviewing the alternative.
Boolean compatibilityConfirmed=true;
String decisionComment='DEMO: alternative accepted after compatibility review.';
System.assert(compatibilityConfirmed && !String.isBlank(decisionComment),
    'Review product compatibility, set compatibilityConfirmed=true and explain your decision.');
// Lock the existing parent before modifying its choices. No HTTP callout in this transaction.
List<Opportunity> parents=[SELECT Id FROM Opportunity
    WHERE SmartDeal_Key__c='OPP-DEMO-ATLAS-001' FOR UPDATE];
System.assertEquals(1,parents.size(),'Expected the existing Atlas opportunity.');
Id oppId=parents[0].Id;
List<Customer_Request__c> requests=[SELECT Id,Original_Message__c,Requested_Quantity__c,
    Requested_Date__c,Budget__c FROM Customer_Request__c WHERE Opportunity__c=:oppId];
Customer_Request__c req;
for(Customer_Request__c value:requests) {
    if(value.Original_Message__c!=null &&
        value.Original_Message__c.startsWith('SD_CONTINUATION_DEMO|OPP-DEMO-ATLAS-001|')) {
        System.assertEquals(null,req,'Duplicate demo request.'); req=value;
    }
}
System.assertNotEquals(null,req,'Missing Atlas demonstration request.');
List<Rescue_Scenario__c> scenarios=[SELECT Id,Assumptions__c,Selected__c,Proposed_Product__c,
    Proposed_Quantity__c,Warehouse_Code__c,Data_Freshness__c,Total_Score__c,
    Estimated_Delivery_Date__c,Score_Version__c FROM Rescue_Scenario__c WHERE Opportunity__c=:oppId];
Rescue_Scenario__c chosen;
for(Rescue_Scenario__c scenario:scenarios) {
    if(scenario.Assumptions__c!=null &&
        scenario.Assumptions__c.startsWith('SD_CONTINUATION_DEMO|ATLAS|ALT;')) {
        System.assertEquals(null,chosen,'Duplicate alternative scenario.'); chosen=scenario;
    }
}
System.assertNotEquals(null,chosen,'Missing Atlas alternative.');
SmartDeal_Weight__mdt config=SmartDeal_Weight__mdt.getInstance('Default_v1');
System.assert(config!=null && config.Active__c,'Missing active scoring configuration.');
System.assert(chosen.Total_Score__c!=null &&
    chosen.Total_Score__c>=config.Minimum_Accepted_Score__c &&
    chosen.Score_Version__c==config.Version__c,'Score missing, below threshold or outdated.');
System.assert(chosen.Data_Freshness__c!=null &&
    chosen.Data_Freshness__c>=System.now().addHours(-24),'Scenario data is stale.');
System.assert(chosen.Proposed_Quantity__c>=req.Requested_Quantity__c,
    'This acceptance script requires the entire requested quantity.');
Id proposed=chosen.Proposed_Product__c;
String warehouseCode=chosen.Warehouse_Code__c;
List<Inventory__c> stocks=[SELECT Id,Usable_Quantity__c,Unit_Price__c,Lead_Time_Days__c,
    Last_Updated__c FROM Inventory__c WHERE Product__c=:proposed AND Warehouse_Code__c=:warehouseCode
    AND ERP_Source__c='SD_CONTINUATION_DEMO' AND Is_Active__c=true FOR UPDATE];
System.assertEquals(1,stocks.size(),'Expected one current alternative stock row.');
Inventory__c stock=stocks[0];
System.assert(stock.Last_Updated__c!=null && stock.Last_Updated__c>=System.now().addHours(-24) &&
    stock.Last_Updated__c<=System.now().addMinutes(5),'Stock is stale or incorrectly dated.');
System.assert(stock.Usable_Quantity__c>=req.Requested_Quantity__c,'Stock no longer covers the request.');
System.assert(stock.Lead_Time_Days__c!=null && stock.Lead_Time_Days__c>=0 &&
    Date.today().addDays(stock.Lead_Time_Days__c.intValue())<=req.Requested_Date__c,
    'Current delivery estimate does not meet the request.');
System.assert(req.Budget__c!=null && stock.Unit_Price__c!=null &&
    stock.Unit_Price__c*req.Requested_Quantity__c<=req.Budget__c,'Budget requires review.');
List<Rescue_Scenario__c> updates=new List<Rescue_Scenario__c>();
for(Rescue_Scenario__c scenario:scenarios) {
    if(scenario.Id==chosen.Id) {
        scenario.Selected__c=true; scenario.Decision_By__c=UserInfo.getUserId();
        scenario.Decision_Date__c=System.now(); scenario.Decision_Comment__c=decisionComment;
        updates.add(scenario);
    } else if(scenario.Selected__c) {
        scenario.Selected__c=false; updates.add(scenario);
    }
}
update updates;
update new Opportunity(Id=oppId,Feasibility_Status__c='Rescued',Rescue_Required__c=false);
System.debug(LoggingLevel.ERROR,'Human choice recorded. Rescued = alternative accepted for this demo. '+
    'No inventory reservation, customer message, quote or order was created.');
