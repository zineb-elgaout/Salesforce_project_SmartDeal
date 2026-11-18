List<SmartDealInventoryService.Input> inputs=new List<SmartDealInventoryService.Input>();
for(Customer_Request__c req:[SELECT Id,Original_Message__c FROM Customer_Request__c
    WHERE Opportunity__r.SmartDeal_Key__c IN
    ('OPP-DEMO-ATLAS-001','OPP-DEMO-EDUNOVA-001','OPP-DEMO-GREENBUILD-001')]) {
    if(req.Original_Message__c!=null && req.Original_Message__c.startsWith('SD_CONTINUATION_DEMO|')) {
        SmartDealInventoryService.Input item=new SmartDealInventoryService.Input();
        item.requestId=req.Id; inputs.add(item);
    }
}
System.assertEquals(3,inputs.size(),'Run 01_prepare_demo.apex first.');
for(SmartDealInventoryService.Result result:SmartDealInventoryService.check(inputs)) {
    System.debug(LoggingLevel.ERROR,JSON.serializePretty(result));
}
// Read only: no Opportunity, stock or request is updated here.
