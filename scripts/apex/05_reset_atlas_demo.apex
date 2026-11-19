Opportunity target = [
    SELECT Id
    FROM Opportunity
    WHERE Name = 'Atlas Office - 10 imprimantes'
    LIMIT 1
];

target.Feasibility_Status__c = 'At Risk';
target.Rescue_Required__c = true;
update target;

List<Rescue_Scenario__c> scenarios = [
    SELECT Id
    FROM Rescue_Scenario__c
    WHERE Opportunity__c = :target.Id
];

for (Rescue_Scenario__c scenario : scenarios) {
    scenario.Selected__c = false;
    scenario.Decision_By__c = null;
    scenario.Decision_Date__c = null;
    scenario.Decision_Comment__c = null;
    scenario.Rejection_Reason__c = null;
}
update scenarios;

System.debug('Atlas demo reset: ' + scenarios.size() + ' scénarios désélectionnés.');
