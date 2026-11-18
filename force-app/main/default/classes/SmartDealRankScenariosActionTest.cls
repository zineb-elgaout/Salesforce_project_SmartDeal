@IsTest
private class SmartDealRankScenariosActionTest {
    @TestSetup static void setupData() {
        Account account = new Account(Name='SD ranking test'); insert account;
        Product2 product = new Product2(Name='SD ranking printer', ProductCode='SD-RANK-PRN',
            ERP_Product_ID__c='SD-RANK-PRN', IsActive=true); insert product;
        String stage;
        for (Schema.PicklistEntry entry : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (entry.isActive()) { stage=entry.getValue(); break; }
        }
        Opportunity opp = new Opportunity(Name='SD ranking test', AccountId=account.Id,
            StageName=stage, CloseDate=Date.today().addDays(10), SmartDeal_Key__c='SD-RANK-OPP');
        Opportunity empty = new Opportunity(Name='SD empty ranking test', AccountId=account.Id,
            StageName=stage, CloseDate=Date.today().addDays(10), SmartDeal_Key__c='SD-RANK-EMPTY');
        insert new List<Opportunity>{opp,empty};
        List<Decimal> scores = new List<Decimal>{90,80,80,70,null,99,98};
        List<Rescue_Scenario__c> scenarios = new List<Rescue_Scenario__c>();
        for (Integer i=0;i<scores.size();i++) {
            scenarios.add(new Rescue_Scenario__c(
                Opportunity__c=opp.Id, Scenario_Type__c='Partial Delivery',
                Proposed_Product__c=product.Id, Proposed_Quantity__c=4,
                Warehouse_Code__c='SD-TEST', Estimated_Delivery_Date__c=Date.today().addDays(3),
                Availability_Score__c=40, Service_Score__c=100, Margin_Score__c=50,
                Eco_Score__c=50, Priority_Score__c=50, Total_Score__c=scores[i],
                Score_Version__c=i==6?'old-version':'rank-test-v1',
                Data_Freshness__c=i==5?System.now().addHours(-25):System.now(),
                Explanation__c='Stored test score; no recalculation requested.',
                Assumptions__c='DEMO: partial quantity; margin and ecology notes are illustrative.',
                Selected__c=false
            ));
        }
        insert scenarios;
    }
    private static void configure(Integer maximum) {
        SmartDealRankScenariosAction.configurationOverride = new SmartDeal_Weight__mdt(
            Active__c=true, Version__c='rank-test-v1', Maximum_Scenarios__c=maximum
        );
    }
    private static SmartDealRankScenariosAction.Request request(String key) {
        SmartDealRankScenariosAction.Request value = new SmartDealRankScenariosAction.Request();
        value.opportunityId=[SELECT Id FROM Opportunity WHERE SmartDeal_Key__c=:key LIMIT 1].Id;
        return value;
    }
    @IsTest static void ranksFiltersAndDoesNotWrite() {
        configure(3);
        SmartDealRankScenariosAction.Request input=request('SD-RANK-OPP');
        Integer dmlBefore=Limits.getDmlStatements();
        Integer queriesBefore=Limits.getQueries();
        SmartDealRankScenariosAction.Response result=SmartDealRankScenariosAction.execute(
            new List<SmartDealRankScenariosAction.Request>{input})[0];
        System.assertEquals(0,Limits.getDmlStatements()-dmlBefore);
        System.assertEquals(3,Limits.getQueries()-queriesBefore);
        System.assertEquals('OK',result.status);
        System.assertEquals(3,result.scenarioCount);
        System.assertEquals(4,result.omittedScenarioCount);
        System.assert(result.requiresHumanDecision);
        List<Object> values=(List<Object>)JSON.deserializeUntyped(result.rankedScenarios);
        Map<String,Object> first=(Map<String,Object>)values[0];
        System.assertEquals(Decimal.valueOf('90'),Decimal.valueOf(String.valueOf(first.get('score'))));
        System.assertEquals('SD-RANK-PRN',first.get('productCode'));
        System.assertEquals(Decimal.valueOf('4'),Decimal.valueOf(String.valueOf(first.get('quantity'))));
        Map<String,Object> second=(Map<String,Object>)values[1];
        Map<String,Object> third=(Map<String,Object>)values[2];
        System.assertEquals(Decimal.valueOf('80'),Decimal.valueOf(String.valueOf(second.get('score'))));
        System.assertEquals(Decimal.valueOf('80'),Decimal.valueOf(String.valueOf(third.get('score'))));
        System.assert(String.valueOf(second.get('scenarioId')).compareTo(
            String.valueOf(third.get('scenarioId')))<0);
        System.assert(String.valueOf(first.get('assumptions')).contains('partial'));
    }
    @IsTest static void honorsConfiguredMaximum() {
        configure(1);
        SmartDealRankScenariosAction.Response result=SmartDealRankScenariosAction.execute(
            new List<SmartDealRankScenariosAction.Request>{request('SD-RANK-OPP')})[0];
        System.assertEquals(1,result.scenarioCount);
        System.assertEquals(6,result.omittedScenarioCount);
        configure(9);
        result=SmartDealRankScenariosAction.execute(
            new List<SmartDealRankScenariosAction.Request>{request('SD-RANK-OPP')})[0];
        System.assertEquals(3,result.scenarioCount);
    }
    @IsTest static void preservesInputOutputOrderAndDuplicates() {
        configure(3);
        SmartDealRankScenariosAction.Request full=request('SD-RANK-OPP');
        SmartDealRankScenariosAction.Request empty=request('SD-RANK-EMPTY');
        List<SmartDealRankScenariosAction.Response> results=SmartDealRankScenariosAction.execute(
            new List<SmartDealRankScenariosAction.Request>{empty,full,full});
        System.assertEquals(3,results.size());
        System.assertEquals('NO_DATA',results[0].status);
        System.assertEquals(empty.opportunityId,results[0].opportunityId);
        System.assertEquals('OK',results[1].status);
        System.assertEquals(results[1].rankedScenarios,results[2].rankedScenarios);
    }
    @IsTest static void handlesMissingAndInvalidRequests() {
        configure(3);
        System.assertEquals(0,SmartDealRankScenariosAction.execute(null).size());
        System.assertEquals(0,SmartDealRankScenariosAction.execute(
            new List<SmartDealRankScenariosAction.Request>()).size());
        SmartDealRankScenariosAction.Request wrong=new SmartDealRankScenariosAction.Request();
        wrong.opportunityId=UserInfo.getUserId();
        List<SmartDealRankScenariosAction.Response> results=SmartDealRankScenariosAction.execute(
            new List<SmartDealRankScenariosAction.Request>{null,new SmartDealRankScenariosAction.Request(),wrong});
        for(SmartDealRankScenariosAction.Response result:results) {
            System.assertEquals('INVALID_REQUEST',result.status);
            System.assertEquals('[]',result.rankedScenarios);
        }
    }
    @IsTest static void rejectsInactiveConfigurationAndOversizedBatch() {
        configure(3);
        SmartDealRankScenariosAction.Request input=request('SD-RANK-OPP');
        SmartDealRankScenariosAction.configurationOverride.Active__c=false;
        System.assertEquals('CONFIG_ERROR',SmartDealRankScenariosAction.execute(
            new List<SmartDealRankScenariosAction.Request>{input})[0].status);
        List<SmartDealRankScenariosAction.Request> many=new List<SmartDealRankScenariosAction.Request>();
        for(Integer i=0;i<21;i++)many.add(input);
        List<SmartDealRankScenariosAction.Response> results=SmartDealRankScenariosAction.execute(many);
        System.assertEquals(21,results.size());
        System.assertEquals('LIMIT_EXCEEDED',results[0].status);
    }
}
