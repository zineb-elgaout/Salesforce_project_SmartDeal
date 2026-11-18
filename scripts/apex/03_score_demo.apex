// Admin-only demo scoring. Only explicitly tagged Atlas scenarios are updated.
List<Rescue_Scenario__c> scenarios=new List<Rescue_Scenario__c>();
List<SmartDealScoringService.Factors> inputs=new List<SmartDealScoringService.Factors>();
for(Rescue_Scenario__c scenario:[SELECT Id,Assumptions__c,Selected__c,Data_Freshness__c,
    Availability_Score__c,Service_Score__c,Margin_Score__c,Eco_Score__c,Priority_Score__c
    FROM Rescue_Scenario__c WHERE Opportunity__r.SmartDeal_Key__c='OPP-DEMO-ATLAS-001']) {
    if(scenario.Assumptions__c==null || !scenario.Assumptions__c.startsWith('SD_CONTINUATION_DEMO|ATLAS|')) continue;
    System.assert(!scenario.Selected__c,'Do not recalculate a selected demonstration scenario.');
    System.assert(scenario.Data_Freshness__c!=null &&
        scenario.Data_Freshness__c>=System.now().addHours(-24),'Demo scenario is stale.');
    SmartDealScoringService.Factors input=new SmartDealScoringService.Factors();
    input.availability=scenario.Availability_Score__c; input.service=scenario.Service_Score__c;
    input.margin=scenario.Margin_Score__c; input.eco=scenario.Eco_Score__c;
    input.priority=scenario.Priority_Score__c; inputs.add(input); scenarios.add(scenario);
}
System.assertEquals(2,scenarios.size(),'Expected the two tagged Atlas scenarios.');
List<SmartDealScoringService.Result> outputs=SmartDealScoringService.calculate(inputs);
for(Integer i=0;i<scenarios.size();i++) {
    scenarios[i].Total_Score__c=outputs[i].score;
    scenarios[i].Score_Version__c=outputs[i].version;
    scenarios[i].Explanation__c=outputs[i].explanation+' '+scenarios[i].Assumptions__c;
}
for(Integer i=0;i<scenarios.size();i++) {
    Integer rank=1;
    for(Integer j=0;j<scenarios.size();j++) {
        if(scenarios[j].Total_Score__c>scenarios[i].Total_Score__c ||
            (scenarios[j].Total_Score__c==scenarios[i].Total_Score__c &&
            String.valueOf(scenarios[j].Id).compareTo(String.valueOf(scenarios[i].Id))<0)) rank++;
    }
    scenarios[i].Rank__c=rank;
}
update scenarios;
System.debug(LoggingLevel.ERROR,'Scores saved on tagged demo scenarios; no selection or order created.');
