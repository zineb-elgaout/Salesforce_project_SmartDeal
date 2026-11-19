public with sharing class SmartDealCockpitController {
    public class Cockpit {
        @AuraEnabled public Counts counts;
        @AuraEnabled public List<WorkItem> workQueue;
        @AuraEnabled public List<DecisionItem> recentDecisions;
    }

    public class Counts {
        @AuraEnabled public Integer requestsToValidate;
        @AuraEnabled public Integer opportunitiesAtRisk;
        @AuraEnabled public Integer scenariosToDecide;
        @AuraEnabled public Integer scenariosSelected;
        @AuraEnabled public Integer serviceOpen;
        @AuraEnabled public Integer serviceOverdue;
    }

    public class WorkItem implements Comparable {
        @AuraEnabled public Id requestId;
        @AuraEnabled public String requestName;
        @AuraEnabled public String customerName;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public String city;
        @AuraEnabled public Date requestedDate;
        @AuraEnabled public String validationStatus;
        @AuraEnabled public String feasibilityStatus;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;

        public Integer compareTo(Object other) {
            WorkItem candidate = (WorkItem) other;
            Integer thisRank = riskRank(feasibilityStatus);
            Integer otherRank = riskRank(candidate.feasibilityStatus);
            if (thisRank != otherRank) {
                return thisRank - otherRank;
            }
            if (requestedDate == null && candidate.requestedDate == null) {
                return 0;
            }
            if (requestedDate == null) {
                return 1;
            }
            if (candidate.requestedDate == null) {
                return -1;
            }
            return requestedDate.daysBetween(candidate.requestedDate);
        }

        private Integer riskRank(String status) {
            if (status == 'At Risk') {
                return 0;
            }
            if (status == 'Feasible') {
                return 2;
            }
            return 1;
        }
    }

    public class DecisionItem {
        @AuraEnabled public Id scenarioId;
        @AuraEnabled public String scenarioName;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public Decimal score;
        @AuraEnabled public String decisionBy;
        @AuraEnabled public Datetime decisionDate;
    }

    @AuraEnabled(cacheable=true)
    public static Cockpit getCockpit() {
        Cockpit result = new Cockpit();
        result.counts = new Counts();
        result.counts.requestsToValidate = [
            SELECT COUNT()
            FROM Customer_Request__c
            WHERE Validation_Status__c IN ('Needs Review', 'Ready for Validation')
            WITH USER_MODE
        ];
        result.counts.opportunitiesAtRisk = [
            SELECT COUNT()
            FROM Opportunity
            WHERE Feasibility_Status__c = 'At Risk'
            WITH USER_MODE
        ];
        Datetime cutoff = System.now().addHours(-24);
        result.counts.scenariosToDecide = [
            SELECT COUNT()
            FROM Rescue_Scenario__c
            WHERE Selected__c = false
              AND Data_Freshness__c >= :cutoff
            WITH USER_MODE
        ];
        result.counts.scenariosSelected = [
            SELECT COUNT()
            FROM Rescue_Scenario__c
            WHERE Selected__c = true
            WITH USER_MODE
        ];
        result.counts.serviceOpen = [
            SELECT COUNT()
            FROM Service_Request__c
            WHERE Status__c NOT IN ('Resolved', 'Closed')
            WITH USER_MODE
        ];
        result.counts.serviceOverdue = [
            SELECT COUNT()
            FROM Service_Request__c
            WHERE Is_Overdue__c = true
            WITH USER_MODE
        ];

        result.workQueue = new List<WorkItem>();
        for (Customer_Request__c row : [
            SELECT Id, Name, Requested_Product__r.Name, Requested_Quantity__c,
                Delivery_City__c, Requested_Date__c, Validation_Status__c,
                Opportunity__c, Opportunity__r.Name, Opportunity__r.Account.Name,
                Opportunity__r.Feasibility_Status__c
            FROM Customer_Request__c
            WHERE Validation_Status__c IN ('Needs Review', 'Ready for Validation', 'Validated')
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 20
        ]) {
            WorkItem item = new WorkItem();
            item.requestId = row.Id;
            item.requestName = row.Name;
            item.customerName = row.Opportunity__r == null || row.Opportunity__r.Account == null
                ? null : row.Opportunity__r.Account.Name;
            item.productName = row.Requested_Product__r == null ? null : row.Requested_Product__r.Name;
            item.quantity = row.Requested_Quantity__c;
            item.city = row.Delivery_City__c;
            item.requestedDate = row.Requested_Date__c;
            item.validationStatus = row.Validation_Status__c;
            item.feasibilityStatus = row.Opportunity__r == null ? null : row.Opportunity__r.Feasibility_Status__c;
            item.opportunityId = row.Opportunity__c;
            item.opportunityName = row.Opportunity__r == null ? null : row.Opportunity__r.Name;
            result.workQueue.add(item);
        }
        result.workQueue.sort();

        result.recentDecisions = new List<DecisionItem>();
        for (Rescue_Scenario__c row : [
            SELECT Id, Name, Opportunity__c, Opportunity__r.Name, Total_Score__c,
                Decision_By__r.Name, Decision_Date__c
            FROM Rescue_Scenario__c
            WHERE Selected__c = true AND Decision_Date__c != null
            WITH USER_MODE
            ORDER BY Decision_Date__c DESC
            LIMIT 5
        ]) {
            DecisionItem item = new DecisionItem();
            item.scenarioId = row.Id;
            item.scenarioName = row.Name;
            item.opportunityId = row.Opportunity__c;
            item.opportunityName = row.Opportunity__r == null ? null : row.Opportunity__r.Name;
            item.score = row.Total_Score__c;
            item.decisionBy = row.Decision_By__r == null ? null : row.Decision_By__r.Name;
            item.decisionDate = row.Decision_Date__c;
            result.recentDecisions.add(item);
        }
        return result;
    }
}