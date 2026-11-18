@IsTest
private class SmartDealInventoryActionTest {
    private static final String FEASIBLE_SKU = 'SD-ACT-FEAS';
    private static final String EMPTY_SKU = 'SD-ACT-EMPTY';

    @TestSetup
    static void setupData() {
        Account account = new Account(Name = 'SD action test');
        insert account;

        String stage;
        for (Schema.PicklistEntry entry : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                stage = entry.getValue();
                break;
            }
        }

        Opportunity opp = new Opportunity(
            Name = 'SD action test',
            AccountId = account.Id,
            StageName = stage,
            CloseDate = Date.today().addDays(30),
            SmartDeal_Key__c = 'SD-ACT-OPP'
        );
        insert opp;

        List<Product2> products = new List<Product2>{
            new Product2(
                Name = FEASIBLE_SKU,
                ProductCode = FEASIBLE_SKU,
                ERP_Product_ID__c = FEASIBLE_SKU,
                IsActive = true
            ),
            new Product2(
                Name = EMPTY_SKU,
                ProductCode = EMPTY_SKU,
                ERP_Product_ID__c = EMPTY_SKU,
                IsActive = true
            )
        };
        insert products;

        Map<String, Product2> bySku = new Map<String, Product2>();
        for (Product2 product : products) {
            bySku.put(product.ProductCode, product);
        }

        insert new List<Inventory__c>{
            new Inventory__c(
                Inventory_Key__c = 'SD-ACT-FEAS|AGADIR',
                Product__c = bySku.get(FEASIBLE_SKU).Id,
                Warehouse_Code__c = 'SD-ACT-AGA',
                Warehouse_Name__c = 'Agadir test',
                City__c = 'Agadir',
                Available_Quantity__c = 25,
                Reserved_Quantity__c = 5,
                Unit_Price__c = 100,
                Lead_Time_Days__c = 2,
                Is_Active__c = true,
                Last_Updated__c = System.now()
            ),
            new Inventory__c(
                Inventory_Key__c = 'SD-ACT-FEAS|CASA',
                Product__c = bySku.get(FEASIBLE_SKU).Id,
                Warehouse_Code__c = 'SD-ACT-CAS',
                Warehouse_Name__c = 'Casa test',
                City__c = 'Casablanca',
                Available_Quantity__c = 25,
                Reserved_Quantity__c = 0,
                Unit_Price__c = 90,
                Lead_Time_Days__c = 2,
                Is_Active__c = true,
                Last_Updated__c = System.now()
            )
        };

        insert new List<Customer_Request__c>{
            new Customer_Request__c(
                Opportunity__c = opp.Id,
                Requested_Product__c = bySku.get(FEASIBLE_SKU).Id,
                Requested_Quantity__c = 10,
                Budget__c = 2000,
                Delivery_City__c = 'Agadir',
                Requested_Date__c = Date.today().addDays(10),
                Validation_Status__c = 'Validated',
                Consent_Status__c = 'Unknown',
                Original_Channel__c = 'Manual',
                Extraction_Source__c = 'Manual',
                Validated_By__c = UserInfo.getUserId(),
                Validation_Date__c = System.now()
            ),
            new Customer_Request__c(
                Opportunity__c = opp.Id,
                Requested_Product__c = bySku.get(EMPTY_SKU).Id,
                Requested_Quantity__c = 10,
                Budget__c = 2000,
                Delivery_City__c = 'Agadir',
                Requested_Date__c = Date.today().addDays(10),
                Validation_Status__c = 'Validated',
                Consent_Status__c = 'Unknown',
                Original_Channel__c = 'Manual',
                Extraction_Source__c = 'Manual',
                Validated_By__c = UserInfo.getUserId(),
                Validation_Date__c = System.now()
            )
        };
    }

    private static Id requestId(String sku) {
        return [
            SELECT Id
            FROM Customer_Request__c
            WHERE Requested_Product__r.ProductCode = :sku
            LIMIT 1
        ].Id;
    }

    private static SmartDealInventoryAction.Request request(Id requestId) {
        SmartDealInventoryAction.Request value = new SmartDealInventoryAction.Request();
        value.requestId = requestId;
        return value;
    }

    @IsTest
    static void returnsEmptyForNullAndEmptyInput() {
        System.assertEquals(0, SmartDealInventoryAction.execute(null).size());
        System.assertEquals(
            0,
            SmartDealInventoryAction.execute(
                new List<SmartDealInventoryAction.Request>()
            ).size()
        );
    }

    @IsTest
    static void returnsFeasibleAndSerializesWarehouses() {
        SmartDealInventoryAction.Response result = SmartDealInventoryAction.execute(
            new List<SmartDealInventoryAction.Request>{
                request(requestId(FEASIBLE_SKU))
            }
        )[0];

        System.assertEquals('FEASIBLE', result.status);
        System.assert(result.requiresHumanReview);
        System.assert(result.message.contains('no reservation'));

        List<Object> warehouses =
            (List<Object>) JSON.deserializeUntyped(result.warehousesJson);

        System.assertEquals(2, warehouses.size());
        System.assert(result.warehousesJson.contains('SD-ACT-AGA'));
    }

    @IsTest
    static void returnsNoStockWithEmptyWarehouseJson() {
        SmartDealInventoryAction.Response result = SmartDealInventoryAction.execute(
            new List<SmartDealInventoryAction.Request>{
                request(requestId(EMPTY_SKU))
            }
        )[0];

        System.assertEquals('NO_STOCK', result.status);
        System.assert(result.requiresHumanReview);
        System.assertEquals('[]', result.warehousesJson);
    }

    @IsTest
    static void rejectsNullWrongAndMissingRequestIds() {
        List<SmartDealInventoryAction.Request> requests =
            new List<SmartDealInventoryAction.Request>{
                null,
                new SmartDealInventoryAction.Request(),
                request(UserInfo.getUserId())
            };

        List<SmartDealInventoryAction.Response> results =
            SmartDealInventoryAction.execute(requests);

        System.assertEquals(3, results.size());
        for (SmartDealInventoryAction.Response result : results) {
            System.assertEquals('INVALID_REQUEST', result.status);
            System.assertEquals('[]', result.warehousesJson);
            System.assert(result.requiresHumanReview);
        }
    }

    @IsTest
    static void preservesOrderAndDoesNotWrite() {
        Id feasibleId = requestId(FEASIBLE_SKU);
        Integer dmlBefore = Limits.getDmlStatements();

        List<SmartDealInventoryAction.Response> results =
            SmartDealInventoryAction.execute(
                new List<SmartDealInventoryAction.Request>{
                    request(feasibleId),
                    new SmartDealInventoryAction.Request(),
                    request(feasibleId)
                }
            );

        System.assertEquals(3, results.size());
        System.assertEquals('FEASIBLE', results[0].status);
        System.assertEquals('INVALID_REQUEST', results[1].status);
        System.assertEquals('FEASIBLE', results[2].status);
        System.assertEquals(results[0].warehousesJson, results[2].warehousesJson);
        System.assertEquals(0, Limits.getDmlStatements() - dmlBefore);
    }
}