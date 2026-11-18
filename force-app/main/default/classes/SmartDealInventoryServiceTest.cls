@IsTest
private class SmartDealInventoryServiceTest {
    private static final String FEASIBLE_SKU = 'SD-INV-FEAS';
    private static final String SHORT_SKU = 'SD-INV-SHORT';
    private static final String MISSING_SKU = 'SD-INV-NONE';
    private static final String STALE_SKU = 'SD-INV-STALE';

    @TestSetup
    static void setupData() {
        Account account = new Account(Name='SD inventory test'); insert account;
        String stage;
        for (Schema.PicklistEntry entry : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (entry.isActive()) { stage=entry.getValue(); break; }
        }
        Opportunity opp = new Opportunity(Name='SD inventory test', AccountId=account.Id,
            StageName=stage, CloseDate=Date.today().addDays(30), SmartDeal_Key__c='SD-INV-OPP');
        insert opp;

        List<Product2> products = new List<Product2>();
        for (String sku : new List<String>{FEASIBLE_SKU, SHORT_SKU, MISSING_SKU, STALE_SKU}) {
            products.add(new Product2(Name=sku, ProductCode=sku, ERP_Product_ID__c=sku, IsActive=true));
        }
        insert products;

        Map<String, Product2> bySku = new Map<String, Product2>();
        for (Product2 product : products) bySku.put(product.ProductCode, product);

        insert new List<Inventory__c>{
            new Inventory__c(Inventory_Key__c='SD-INV-FEAS|AGADIR', Product__c=bySku.get(FEASIBLE_SKU).Id,
                Warehouse_Code__c='SD-INV-AGA', Warehouse_Name__c='Agadir test', City__c='Agadir',
                Available_Quantity__c=25, Reserved_Quantity__c=5, Unit_Price__c=100,
                Lead_Time_Days__c=2, Is_Active__c=true, Last_Updated__c=System.now()),
            new Inventory__c(Inventory_Key__c='SD-INV-FEAS|CASA', Product__c=bySku.get(FEASIBLE_SKU).Id,
                Warehouse_Code__c='SD-INV-CAS', Warehouse_Name__c='Casa test', City__c='Casablanca',
                Available_Quantity__c=25, Reserved_Quantity__c=0, Unit_Price__c=90,
                Lead_Time_Days__c=2, Is_Active__c=true, Last_Updated__c=System.now()),
            new Inventory__c(Inventory_Key__c='SD-INV-SHORT|AGADIR', Product__c=bySku.get(SHORT_SKU).Id,
                Warehouse_Code__c='SD-INV-AGA', Warehouse_Name__c='Agadir test', City__c='Agadir',
                Available_Quantity__c=3, Reserved_Quantity__c=0, Unit_Price__c=100,
                Lead_Time_Days__c=2, Is_Active__c=true, Last_Updated__c=System.now()),
            new Inventory__c(Inventory_Key__c='SD-INV-STALE|AGADIR', Product__c=bySku.get(STALE_SKU).Id,
                Warehouse_Code__c='SD-INV-AGA', Warehouse_Name__c='Agadir test', City__c='Agadir',
                Available_Quantity__c=25, Reserved_Quantity__c=0, Unit_Price__c=100,
                Lead_Time_Days__c=2, Is_Active__c=true, Last_Updated__c=System.now().addHours(-25)),
            new Inventory__c(Inventory_Key__c='SD-INV-STALE|CASA', Product__c=bySku.get(STALE_SKU).Id,
                Warehouse_Code__c='SD-INV-CAS', Warehouse_Name__c='Casa test', City__c='Casablanca',
                Available_Quantity__c=25, Reserved_Quantity__c=0, Unit_Price__c=100,
                Lead_Time_Days__c=2, Is_Active__c=false, Last_Updated__c=System.now())
        };

        List<Customer_Request__c> requests = new List<Customer_Request__c>();
        for (String sku : new List<String>{FEASIBLE_SKU, SHORT_SKU, MISSING_SKU, STALE_SKU}) {
            requests.add(new Customer_Request__c(Opportunity__c=opp.Id,
                Requested_Product__c=bySku.get(sku).Id, Requested_Quantity__c=10,
                Budget__c=2000, Delivery_City__c='Agadir',
                Requested_Date__c=Date.today().addDays(10), Validation_Status__c='Validated',
                Consent_Status__c='Unknown', Original_Channel__c='Manual',
                Extraction_Source__c='Manual', Validated_By__c=UserInfo.getUserId(),
                Validation_Date__c=System.now()));
        }
        insert requests;
    }

    private static SmartDealInventoryService.Input input(Id requestId) {
        SmartDealInventoryService.Input value = new SmartDealInventoryService.Input();
        value.requestId = requestId;
        return value;
    }

    private static Id requestId(String sku) {
        for (Customer_Request__c request : [SELECT Id, Requested_Product__r.ProductCode
            FROM Customer_Request__c WHERE Opportunity__r.SmartDeal_Key__c='SD-INV-OPP']) {
            if (request.Requested_Product__r.ProductCode == sku) return request.Id;
        }
        return null;
    }

    @IsTest
    static void returnsFeasibleWhenAllConstraintsAreMet() {
        SmartDealInventoryService.Result result = SmartDealInventoryService.check(
            new List<SmartDealInventoryService.Input>{input(requestId(FEASIBLE_SKU))})[0];
        System.assertEquals('FEASIBLE', result.status);
        System.assertEquals(FEASIBLE_SKU, result.productCode);
        System.assertEquals(10, result.requestedQuantity);
        System.assertEquals(2, result.warehouses.size());
        Boolean foundEligible = false;
        for (SmartDealInventoryService.Warehouse warehouse : result.warehouses) {
            if (warehouse.eligible) {
                foundEligible = true;
                System.assertEquals('SD-INV-AGA', warehouse.warehouseCode);
                System.assertEquals(20, warehouse.usableQuantity);
                System.assertEquals(1000, warehouse.estimatedTotal);
                System.assertEquals(0, warehouse.blockingReasons.size());
            }
        }
        System.assert(foundEligible);
        System.assert(result.requiresHumanReview);
    }

    @IsTest
    static void reportsAtRiskWhenStockIsTooLow() {
        SmartDealInventoryService.Result result = SmartDealInventoryService.check(
            new List<SmartDealInventoryService.Input>{input(requestId(SHORT_SKU))})[0];
        System.assertEquals('AT_RISK', result.status);
        System.assertEquals(1, result.warehouses.size());
        System.assert(!result.warehouses[0].stockCovers);
        System.assert(result.warehouses[0].blockingReasons.size() > 0);
    }

    @IsTest
    static void reportsNoStockForMissingProductInventory() {
        SmartDealInventoryService.Result result = SmartDealInventoryService.check(
            new List<SmartDealInventoryService.Input>{input(requestId(MISSING_SKU))})[0];
        System.assertEquals('NO_STOCK', result.status);
        System.assertEquals(0, result.warehouses.size());
    }

    @IsTest
    static void rejectsStaleAndIgnoresInactiveInventory() {
        SmartDealInventoryService.Result result = SmartDealInventoryService.check(
            new List<SmartDealInventoryService.Input>{input(requestId(STALE_SKU))})[0];
        System.assertEquals('AT_RISK', result.status);
        System.assertEquals(1, result.warehouses.size());
        System.assert(!result.warehouses[0].inventoryFresh);
        System.assert(!result.warehouses[0].eligible);
    }

    @IsTest
    static void preservesOrderAndRejectsInvalidInputs() {
        System.assertEquals(0, SmartDealInventoryService.check(null).size());
        System.assertEquals(0, SmartDealInventoryService.check(
            new List<SmartDealInventoryService.Input>()).size());
        SmartDealInventoryService.Input wrong = new SmartDealInventoryService.Input();
        wrong.requestId = UserInfo.getUserId();
        List<SmartDealInventoryService.Result> results = SmartDealInventoryService.check(
            new List<SmartDealInventoryService.Input>{
                null, wrong, new SmartDealInventoryService.Input(), input(requestId(FEASIBLE_SKU)),
                input(requestId(FEASIBLE_SKU))
            });
        System.assertEquals(5, results.size());
        System.assertEquals('INVALID_REQUEST', results[0].status);
        System.assertEquals('INVALID_REQUEST', results[1].status);
        System.assertEquals('INVALID_REQUEST', results[2].status);
        System.assertEquals('FEASIBLE', results[3].status);
        System.assertEquals('FEASIBLE', results[4].status);
        System.assertEquals(results[3].requestId, results[4].requestId);
    }

    @IsTest
    static void doesNotWriteData() {
        Integer dmlBefore = Limits.getDmlStatements();
        SmartDealInventoryService.check(new List<SmartDealInventoryService.Input>{
            input(requestId(FEASIBLE_SKU)), input(requestId(SHORT_SKU))});
        System.assertEquals(0, Limits.getDmlStatements() - dmlBefore);
    }
}
