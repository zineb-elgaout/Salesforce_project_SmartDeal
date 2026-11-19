public with sharing class SmartDealReportingController {
    public class Dashboard {
        @AuraEnabled public Integer requestsTotal;
        @AuraEnabled public Integer requestsValidated;
        @AuraEnabled public Integer requestsToValidate;
        @AuraEnabled public Decimal validationRate;
        @AuraEnabled public Integer opportunitiesAtRisk;
        @AuraEnabled public Integer opportunitiesFeasible;
        @AuraEnabled public Integer opportunitiesRescued;
        @AuraEnabled public Integer scenariosGenerated;
        @AuraEnabled public Integer scenariosSelected;
        @AuraEnabled public Decimal selectionRate;
        @AuraEnabled public Decimal averageSelectedScore;
        @AuraEnabled public Integer serviceTotal;
        @AuraEnabled public Integer serviceOpen;
        @AuraEnabled public Integer serviceOverdue;
        @AuraEnabled public List<Step> funnel;
        @AuraEnabled public List<Breakdown> scenarioTypes;
        @AuraEnabled public List<Breakdown> servicePriorities;
    }

    public class Step {
        @AuraEnabled public String label;
        @AuraEnabled public Integer value;
        @AuraEnabled public Decimal percent;
    }

    public class Breakdown {
        @AuraEnabled public String label;
        @AuraEnabled public Integer value;
        @AuraEnabled public Decimal percent;
    }

    @AuraEnabled(cacheable=true)
    public static Dashboard getDashboard() {
        Dashboard result = new Dashboard();
        result.requestsTotal = [SELECT COUNT() FROM Customer_Request__c WITH USER_MODE];
        result.requestsValidated = [
            SELECT COUNT()
            FROM Customer_Request__c
            WHERE Validation_Status__c = 'Validated'
            WITH USER_MODE
        ];
        result.requestsToValidate = [
            SELECT COUNT()
            FROM Customer_Request__c
            WHERE Validation_Status__c IN ('Needs Review', 'Ready for Validation')
            WITH USER_MODE
        ];
        result.validationRate = rate(result.requestsValidated, result.requestsTotal);

        result.opportunitiesAtRisk = [
            SELECT COUNT()
            FROM Opportunity
            WHERE Feasibility_Status__c = 'At Risk'
            WITH USER_MODE
        ];
        result.opportunitiesFeasible = [
            SELECT COUNT()
            FROM Opportunity
            WHERE Feasibility_Status__c = 'Feasible'
            WITH USER_MODE
        ];
        result.opportunitiesRescued = [
            SELECT COUNT()
            FROM Opportunity
            WHERE Feasibility_Status__c = 'Rescued'
            WITH USER_MODE
        ];

        result.scenariosGenerated = [SELECT COUNT() FROM Rescue_Scenario__c WITH USER_MODE];
        result.scenariosSelected = [
            SELECT COUNT()
            FROM Rescue_Scenario__c
            WHERE Selected__c = true
            WITH USER_MODE
        ];
        result.selectionRate = rate(result.scenariosSelected, result.scenariosGenerated);

        result.averageSelectedScore = 0;
        for (AggregateResult aggregate : [
            SELECT AVG(Total_Score__c) averageScore
            FROM Rescue_Scenario__c
            WHERE Selected__c = true
            WITH USER_MODE
        ]) {
            Object averageValue = aggregate.get('averageScore');
            if (averageValue != null) {
                result.averageSelectedScore = ((Decimal) averageValue).setScale(1);
            }
        }

        result.serviceTotal = [SELECT COUNT() FROM Service_Request__c WITH USER_MODE];
        result.serviceOpen = [
            SELECT COUNT()
            FROM Service_Request__c
            WHERE Status__c NOT IN ('Resolved', 'Closed')
            WITH USER_MODE
        ];
        result.serviceOverdue = [
            SELECT COUNT()
            FROM Service_Request__c
            WHERE Is_Overdue__c = true
            WITH USER_MODE
        ];

        result.funnel = new List<Step>();
        result.funnel.add(step('Demandes', result.requestsTotal, result.requestsTotal));
        result.funnel.add(step('Validées', result.requestsValidated, result.requestsTotal));
        result.funnel.add(step('À risque', result.opportunitiesAtRisk, result.requestsTotal));
        result.funnel.add(step('Scénarios générés', result.scenariosGenerated, result.requestsTotal));
        result.funnel.add(step('Scénarios sélectionnés', result.scenariosSelected, result.requestsTotal));

        result.scenarioTypes = new List<Breakdown>();
        for (AggregateResult aggregate : [
            SELECT Scenario_Type__c label, COUNT(Id) total
            FROM Rescue_Scenario__c
            WITH USER_MODE
            GROUP BY Scenario_Type__c
            ORDER BY COUNT(Id) DESC
        ]) {
            String label = aggregate.get('label') == null ? 'Non renseigné' : (String) aggregate.get('label');
            Integer value = (Integer) aggregate.get('total');
            result.scenarioTypes.add(breakdown(label, value, result.scenariosGenerated));
        }

        result.servicePriorities = new List<Breakdown>();
        for (AggregateResult aggregate : [
            SELECT Priority__c label, COUNT(Id) total
            FROM Service_Request__c
            WHERE Status__c NOT IN ('Resolved', 'Closed')
            WITH USER_MODE
            GROUP BY Priority__c
            ORDER BY COUNT(Id) DESC
        ]) {
            String label = aggregate.get('label') == null ? 'Non renseignée' : (String) aggregate.get('label');
            Integer value = (Integer) aggregate.get('total');
            result.servicePriorities.add(breakdown(label, value, result.serviceOpen));
        }
        return result;
    }

    private static Step step(String label, Integer value, Integer denominator) {
        Step view = new Step();
        view.label = label;
        view.value = value;
        view.percent = rate(value, denominator);
        return view;
    }

    private static Breakdown breakdown(String label, Integer value, Integer denominator) {
        Breakdown view = new Breakdown();
        view.label = label;
        view.value = value;
        view.percent = rate(value, denominator);
        return view;
    }

    private static Decimal rate(Integer value, Integer denominator) {
        if (denominator == null || denominator == 0) {
            return 0;
        }
        return (Decimal.valueOf(value) * 100 / Decimal.valueOf(denominator)).setScale(1);
    }
}
