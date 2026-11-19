public with sharing class SmartDealRequestWorkspaceController {
    public class Workspace {
        @AuraEnabled public RequestView request;
        @AuraEnabled public List<ChecklistItem> checklist;
        @AuraEnabled public InventoryView inventory;
        @AuraEnabled public Boolean canValidate;
        @AuraEnabled public Boolean isValidated;
    }

    public class RequestView {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String customerName;
        @AuraEnabled public String productName;
        @AuraEnabled public String productCode;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal budget;
        @AuraEnabled public String city;
        @AuraEnabled public Date requestedDate;
        @AuraEnabled public String validationStatus;
        @AuraEnabled public String consentStatus;
        @AuraEnabled public String channel;
        @AuraEnabled public String originalMessage;
        @AuraEnabled public String missingInformation;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String feasibilityStatus;
        @AuraEnabled public Datetime validationDate;
        @AuraEnabled public String validatedBy;
    }

    public class ChecklistItem {
        @AuraEnabled public String label;
        @AuraEnabled public Boolean complete;
        @AuraEnabled public String detail;
    }

    public class InventoryView {
        @AuraEnabled public String status;
        @AuraEnabled public String message;
        @AuraEnabled public List<WarehouseView> warehouses;
    }

    public class WarehouseView {
        @AuraEnabled public String warehouseName;
        @AuraEnabled public String warehouseCode;
        @AuraEnabled public String city;
        @AuraEnabled public Decimal usableQuantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Integer leadTimeDays;
        @AuraEnabled public Date estimatedDeliveryDate;
        @AuraEnabled public Decimal estimatedTotal;
        @AuraEnabled public Boolean eligible;
        @AuraEnabled public Boolean inventoryFresh;
        @AuraEnabled public String blockingReasons;
    }

    @AuraEnabled(cacheable=true)
    public static Workspace getWorkspace(Id requestId) {
        if (requestId == null) {
            throw fail('Identifiant de demande manquant.');
        }
        List<Customer_Request__c> rows = [
            SELECT Id, Name, Requested_Product__r.Name, Requested_Product__r.ProductCode,
                Requested_Quantity__c, Budget__c, Delivery_City__c, Requested_Date__c,
                Validation_Status__c, Consent_Status__c, Original_Channel__c,
                Original_Message__c, Missing_Information__c, Opportunity__c,
                Opportunity__r.Name, Opportunity__r.Account.Name,
                Opportunity__r.Feasibility_Status__c, Validation_Date__c,
                Validated_By__r.Name
            FROM Customer_Request__c
            WHERE Id = :requestId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw fail('Demande introuvable ou inaccessible.');
        }

        Customer_Request__c row = rows[0];
        Workspace result = new Workspace();
        result.request = toRequestView(row);
        result.checklist = buildChecklist(row);
        result.isValidated = row.Validation_Status__c == 'Validated';
        result.canValidate = row.Validation_Status__c != 'Validated'
            && row.Validation_Status__c != 'Rejected';
        result.inventory = checkInventory(requestId);
        return result;
    }

    @AuraEnabled
    public static Workspace validateRequest(Id requestId) {
        if (requestId == null) {
            throw fail('Identifiant de demande manquant.');
        }
        List<Customer_Request__c> rows = [
            SELECT Id
            FROM Customer_Request__c
            WHERE Id = :requestId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw fail('Demande introuvable ou inaccessible.');
        }

        Customer_Request__c updateRow = new Customer_Request__c(Id = requestId);
        updateRow.Validation_Status__c = 'Validated';
        updateRow.Validated_By__c = UserInfo.getUserId();
        updateRow.Validation_Date__c = System.now();

        try {
            Database.SaveResult saveResult = Database.update(updateRow, AccessLevel.USER_MODE);
            if (!saveResult.isSuccess()) {
                throw fail(saveResult.getErrors()[0].getMessage());
            }
        } catch (DmlException ex) {
            throw fail(ex.getDmlMessage(0));
        }
        return getWorkspace(requestId);
    }

    private static RequestView toRequestView(Customer_Request__c row) {
        RequestView view = new RequestView();
        view.id = row.Id;
        view.name = row.Name;
        view.customerName = row.Opportunity__r == null || row.Opportunity__r.Account == null
            ? null : row.Opportunity__r.Account.Name;
        view.productName = row.Requested_Product__r == null ? null : row.Requested_Product__r.Name;
        view.productCode = row.Requested_Product__r == null ? null : row.Requested_Product__r.ProductCode;
        view.quantity = row.Requested_Quantity__c;
        view.budget = row.Budget__c;
        view.city = row.Delivery_City__c;
        view.requestedDate = row.Requested_Date__c;
        view.validationStatus = row.Validation_Status__c;
        view.consentStatus = row.Consent_Status__c;
        view.channel = row.Original_Channel__c;
        view.originalMessage = row.Original_Message__c;
        view.missingInformation = row.Missing_Information__c;
        view.opportunityId = row.Opportunity__c;
        view.opportunityName = row.Opportunity__r == null ? null : row.Opportunity__r.Name;
        view.feasibilityStatus = row.Opportunity__r == null ? null : row.Opportunity__r.Feasibility_Status__c;
        view.validationDate = row.Validation_Date__c;
        view.validatedBy = row.Validated_By__r == null ? null : row.Validated_By__r.Name;
        return view;
    }

    private static List<ChecklistItem> buildChecklist(Customer_Request__c row) {
        List<ChecklistItem> items = new List<ChecklistItem>();
        items.add(item('Produit demandé', row.Requested_Product__c != null, 'Produit obligatoire'));
        items.add(item(
            'Quantité positive',
            row.Requested_Quantity__c != null && row.Requested_Quantity__c > 0,
            'La quantité doit être supérieure à zéro'
        ));
        items.add(item('Ville de livraison', String.isNotBlank(row.Delivery_City__c), 'Ville obligatoire'));
        items.add(item(
            'Date souhaitée',
            row.Requested_Date__c != null && row.Requested_Date__c >= Date.today(),
            'La date doit être aujourd’hui ou plus tard'
        ));
        items.add(item('Opportunité liée', row.Opportunity__c != null, 'Opportunité obligatoire'));
        items.add(item(
            'Consentement client',
            row.Consent_Status__c != 'OptOut',
            'Le client ne doit pas être en OptOut'
        ));
        items.add(item(
            'Budget valide',
            row.Budget__c != null && row.Budget__c >= 0,
            'Budget non négatif'
        ));
        return items;
    }

    private static ChecklistItem item(String label, Boolean complete, String detail) {
        ChecklistItem view = new ChecklistItem();
        view.label = label;
        view.complete = complete;
        view.detail = detail;
        return view;
    }

    private static InventoryView checkInventory(Id requestId) {
        InventoryView view = new InventoryView();
        view.warehouses = new List<WarehouseView>();

        SmartDealInventoryService.Input input = new SmartDealInventoryService.Input();
        input.requestId = requestId;
        List<SmartDealInventoryService.Result> results =
            SmartDealInventoryService.check(new List<SmartDealInventoryService.Input>{ input });

        if (results.isEmpty()) {
            view.status = 'NO_DATA';
            view.message = 'Aucun résultat d’inventaire.';
            return view;
        }

        SmartDealInventoryService.Result result = results[0];
        view.status = result.status;
        view.message = result.message;
        for (SmartDealInventoryService.Warehouse warehouse : result.warehouses) {
            WarehouseView item = new WarehouseView();
            item.warehouseName = warehouse.warehouseName;
            item.warehouseCode = warehouse.warehouseCode;
            item.city = warehouse.city;
            item.usableQuantity = warehouse.usableQuantity;
            item.unitPrice = warehouse.unitPrice;
            item.leadTimeDays = warehouse.leadTimeDays;
            item.estimatedDeliveryDate = warehouse.estimatedDeliveryDate;
            item.estimatedTotal = warehouse.estimatedTotal;
            item.eligible = warehouse.eligible;
            item.inventoryFresh = warehouse.inventoryFresh;
            item.blockingReasons = warehouse.blockingReasons == null
                ? null : String.join(warehouse.blockingReasons, '; ');
            view.warehouses.add(item);
        }
        return view;
    }

    private static AuraHandledException fail(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
