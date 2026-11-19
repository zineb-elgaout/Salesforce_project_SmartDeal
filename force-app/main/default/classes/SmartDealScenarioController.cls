public with sharing class SmartDealScenarioController {
    public class Board {
        @AuraEnabled public OpportunityView opportunity;
        @AuraEnabled public List<ScenarioView> scenarios;
        @AuraEnabled public Integer selectedCount;
        @AuraEnabled public Id relatedRequestId;
        @AuraEnabled public String warning;
    }

    public class OpportunityView {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String accountName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String stageName;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String feasibilityStatus;
        @AuraEnabled public Boolean rescueRequired;
    }

    public class ScenarioView {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String scenarioType;
        @AuraEnabled public String productName;
        @AuraEnabled public String productCode;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public String warehouseCode;
        @AuraEnabled public String warehouseName;
        @AuraEnabled public Date estimatedDeliveryDate;
        @AuraEnabled public Decimal estimatedMargin;
        @AuraEnabled public Decimal availabilityScore;
        @AuraEnabled public Decimal serviceScore;
        @AuraEnabled public Decimal marginScore;
        @AuraEnabled public Decimal ecoScore;
        @AuraEnabled public Decimal priorityScore;
        @AuraEnabled public Decimal totalScore;
        @AuraEnabled public String explanation;
        @AuraEnabled public String assumptions;
        @AuraEnabled public Datetime dataFreshness;
        @AuraEnabled public String scoreVersion;
        @AuraEnabled public Boolean selected;
        @AuraEnabled public Boolean stale;
        @AuraEnabled public Integer displayRank;
        @AuraEnabled public String decisionBy;
        @AuraEnabled public Datetime decisionDate;
        @AuraEnabled public String decisionComment;
        @AuraEnabled public String rejectionReason;
        @AuraEnabled public List<ScoreFactor> factors;
    }

    public class ScoreFactor {
        @AuraEnabled public String label;
        @AuraEnabled public Decimal value;
        @AuraEnabled public String weightLabel;
    }

    @AuraEnabled(cacheable=true)
    public static Board getBoard(Id opportunityId) {
        if (opportunityId == null) {
            throw fail('Identifiant d’opportunité manquant.');
        }

        List<Opportunity> opportunities = [
            SELECT Id, Name, Account.Name, Amount, StageName, Owner.Name,
                Feasibility_Status__c, Rescue_Required__c
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];
        if (opportunities.isEmpty()) {
            throw fail('Opportunité introuvable ou inaccessible.');
        }

        Opportunity opportunity = opportunities[0];
        Board board = new Board();
        board.opportunity = new OpportunityView();
        board.opportunity.id = opportunity.Id;
        board.opportunity.name = opportunity.Name;
        board.opportunity.accountName = opportunity.Account == null ? null : opportunity.Account.Name;
        board.opportunity.amount = opportunity.Amount;
        board.opportunity.stageName = opportunity.StageName;
        board.opportunity.ownerName = opportunity.Owner == null ? null : opportunity.Owner.Name;
        board.opportunity.feasibilityStatus = opportunity.Feasibility_Status__c;
        board.opportunity.rescueRequired = opportunity.Rescue_Required__c;

        List<Customer_Request__c> requests = [
            SELECT Id
            FROM Customer_Request__c
            WHERE Opportunity__c = :opportunityId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        board.relatedRequestId = requests.isEmpty() ? null : requests[0].Id;

        board.scenarios = new List<ScenarioView>();
        Datetime nowValue = System.now();
        Integer staleCount = 0;
        board.selectedCount = 0;
        Integer rank = 1;
        for (Rescue_Scenario__c row : [
            SELECT Id, Name, Scenario_Type__c, Proposed_Product__r.Name,
                Proposed_Product__r.ProductCode, Proposed_Quantity__c,
                Warehouse_Code__c, Warehouse_Name__c, Estimated_Delivery_Date__c,
                Estimated_Margin__c, Availability_Score__c, Service_Score__c,
                Margin_Score__c, Eco_Score__c, Priority_Score__c, Total_Score__c,
                Explanation__c, Assumptions__c, Data_Freshness__c, Score_Version__c,
                Selected__c, Decision_By__r.Name, Decision_Date__c,
                Decision_Comment__c, Rejection_Reason__c
            FROM Rescue_Scenario__c
            WHERE Opportunity__c = :opportunityId
            WITH USER_MODE
            ORDER BY Total_Score__c DESC NULLS LAST, Id ASC
        ]) {
            ScenarioView view = new ScenarioView();
            view.id = row.Id;
            view.name = row.Name;
            view.scenarioType = row.Scenario_Type__c;
            view.productName = row.Proposed_Product__r == null ? null : row.Proposed_Product__r.Name;
            view.productCode = row.Proposed_Product__r == null ? null : row.Proposed_Product__r.ProductCode;
            view.quantity = row.Proposed_Quantity__c;
            view.warehouseCode = row.Warehouse_Code__c;
            view.warehouseName = row.Warehouse_Name__c;
            view.estimatedDeliveryDate = row.Estimated_Delivery_Date__c;
            view.estimatedMargin = row.Estimated_Margin__c;
            view.availabilityScore = safe(row.Availability_Score__c);
            view.serviceScore = safe(row.Service_Score__c);
            view.marginScore = safe(row.Margin_Score__c);
            view.ecoScore = safe(row.Eco_Score__c);
            view.priorityScore = safe(row.Priority_Score__c);
            view.totalScore = safe(row.Total_Score__c);
            view.explanation = row.Explanation__c;
            view.assumptions = row.Assumptions__c;
            view.dataFreshness = row.Data_Freshness__c;
            view.scoreVersion = row.Score_Version__c;
            view.selected = row.Selected__c;
            view.decisionBy = row.Decision_By__r == null ? null : row.Decision_By__r.Name;
            view.decisionDate = row.Decision_Date__c;
            view.decisionComment = row.Decision_Comment__c;
            view.rejectionReason = row.Rejection_Reason__c;
            view.displayRank = rank++;
            view.stale = row.Data_Freshness__c == null
                || row.Data_Freshness__c < nowValue.addHours(-24)
                || row.Data_Freshness__c > nowValue.addMinutes(5);
            if (view.stale) {
                staleCount++;
            }
            if (view.selected) {
                board.selectedCount++;
            }
            view.factors = new List<ScoreFactor>{
                factor('Disponibilité', view.availabilityScore, '30 %'),
                factor('Service', view.serviceScore, '25 %'),
                factor('Marge', view.marginScore, '20 %'),
                factor('Écologie', view.ecoScore, '15 %'),
                factor('Priorité', view.priorityScore, '10 %')
            };
            board.scenarios.add(view);
        }

        List<String> warnings = new List<String>();
        if (board.scenarios.isEmpty()) {
            warnings.add('Aucun scénario de sauvetage enregistré pour cette opportunité.');
        }
        if (staleCount > 0) {
            warnings.add(staleCount + ' scénario(s) ont des données absentes ou de plus de 24 h. Ne pas confirmer sans revérification.');
        }
        if (board.selectedCount > 1) {
            warnings.add('Plusieurs scénarios sont sélectionnés. Une seule décision doit être retenue.');
        }
        board.warning = String.join(warnings, ' ');
        return board;
    }

    @AuraEnabled
    public static Board selectScenario(Id scenarioId, String comment) {
        if (scenarioId == null) {
            throw fail('Scénario manquant.');
        }
        if (String.isBlank(comment)) {
            throw fail('Un commentaire de décision est obligatoire.');
        }

        List<Rescue_Scenario__c> scenarios = [
            SELECT Id, Opportunity__c
            FROM Rescue_Scenario__c
            WHERE Id = :scenarioId
            WITH USER_MODE
            LIMIT 1
        ];
        if (scenarios.isEmpty()) {
            throw fail('Scénario introuvable ou inaccessible.');
        }
        Id opportunityId = scenarios[0].Opportunity__c;

        List<Rescue_Scenario__c> updates = new List<Rescue_Scenario__c>();
        for (Rescue_Scenario__c row : [
            SELECT Id, Selected__c
            FROM Rescue_Scenario__c
            WHERE Opportunity__c = :opportunityId AND Selected__c = true
            WITH USER_MODE
        ]) {
            if (row.Id != scenarioId) {
                updates.add(new Rescue_Scenario__c(Id = row.Id, Selected__c = false));
            }
        }

        Rescue_Scenario__c chosen = new Rescue_Scenario__c(Id = scenarioId);
        chosen.Selected__c = true;
        chosen.Decision_By__c = UserInfo.getUserId();
        chosen.Decision_Date__c = System.now();
        chosen.Decision_Comment__c = abbreviate(comment);
        chosen.Rejection_Reason__c = null;
        updates.add(chosen);

        Database.SaveResult[] scenarioResults =
            Database.update(updates, true, AccessLevel.USER_MODE);
        for (Database.SaveResult saveResult : scenarioResults) {
            if (!saveResult.isSuccess()) {
                throw fail(saveResult.getErrors()[0].getMessage());
            }
        }

        Opportunity opportunity = new Opportunity(Id = opportunityId);
        opportunity.Feasibility_Status__c = 'Rescued';
        opportunity.Rescue_Required__c = false;
        Database.SaveResult opportunityResult =
            Database.update(opportunity, true, AccessLevel.USER_MODE);
        if (!opportunityResult.isSuccess()) {
            throw fail(opportunityResult.getErrors()[0].getMessage());
        }

        return getBoard(opportunityId);
    }

    @AuraEnabled
    public static Board rejectScenario(Id scenarioId, String reason) {
        if (scenarioId == null) {
            throw fail('Scénario manquant.');
        }
        if (String.isBlank(reason)) {
            throw fail('Un motif de rejet est obligatoire.');
        }

        List<Rescue_Scenario__c> scenarios = [
            SELECT Id, Opportunity__c
            FROM Rescue_Scenario__c
            WHERE Id = :scenarioId
            WITH USER_MODE
            LIMIT 1
        ];
        if (scenarios.isEmpty()) {
            throw fail('Scénario introuvable ou inaccessible.');
        }

        Rescue_Scenario__c updateRow = new Rescue_Scenario__c(Id = scenarioId);
        updateRow.Selected__c = false;
        updateRow.Rejection_Reason__c = abbreviate(reason);
        updateRow.Decision_By__c = UserInfo.getUserId();
        updateRow.Decision_Date__c = System.now();

        Database.SaveResult saveResult =
            Database.update(updateRow, true, AccessLevel.USER_MODE);
        if (!saveResult.isSuccess()) {
            throw fail(saveResult.getErrors()[0].getMessage());
        }

        return getBoard(scenarios[0].Opportunity__c);
    }

    private static ScoreFactor factor(String label, Decimal value, String weightLabel) {
        ScoreFactor view = new ScoreFactor();
        view.label = label;
        view.value = value;
        view.weightLabel = weightLabel;
        return view;
    }

    private static Decimal safe(Decimal value) {
        return value == null ? 0 : value;
    }

    private static String abbreviate(String value) {
        if (value == null) {
            return null;
        }
        return value.length() <= 1000 ? value : value.substring(0, 1000);
    }

    private static AuraHandledException fail(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
