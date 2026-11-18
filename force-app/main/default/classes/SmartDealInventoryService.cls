public with sharing class SmartDealInventoryService {
    private static final Integer MAX_INPUTS = 200;
    private static final Integer FRESH_HOURS = 24;

    public class Input {
        public Id requestId;
    }

    public class Warehouse {
        public String inventoryKey;
        public String warehouseCode;
        public String warehouseName;
        public String city;
        public Decimal usableQuantity;
        public Decimal unitPrice;
        public Integer leadTimeDays;
        public Boolean reconditioned;
        public Date estimatedDeliveryDate;
        public Decimal estimatedTotal;
        public Datetime lastUpdated;
        public Boolean inventoryFresh;
        public Boolean cityMatches;
        public Boolean stockCovers;
        public Boolean deliveryOnTime;
        public Boolean budgetCovers;
        public Boolean eligible;
        public List<String> blockingReasons;
    }

    public class Result {
        public Id requestId;
        public Id opportunityId;
        public String opportunityKey;
        public String productCode;
        public String status;
        public Integer requestedQuantity;
        public Decimal budget;
        public String deliveryCity;
        public Date requestedDate;
        public Boolean requiresHumanReview;
        public String message;
        public List<Warehouse> warehouses;

        public Result() {
            requiresHumanReview = true;
            warehouses = new List<Warehouse>();
        }
    }

    public static List<Result> check(List<Input> inputs) {
        List<Result> outputs = new List<Result>();
        if (inputs == null || inputs.isEmpty()) return outputs;
        if (inputs.size() > MAX_INPUTS) {
            return failAll(inputs, 'LIMIT_EXCEEDED', 'At most 200 requests are checked per call.');
        }

        Set<Id> requestIds = new Set<Id>();
        for (Input item : inputs) {
            if (item == null || item.requestId == null ||
                item.requestId.getSObjectType() != Customer_Request__c.SObjectType) continue;
            requestIds.add(item.requestId);
        }

        Map<Id, Customer_Request__c> requests = new Map<Id, Customer_Request__c>();
        if (!requestIds.isEmpty()) {
            requests = new Map<Id, Customer_Request__c>([
                SELECT Id, Opportunity__c, Opportunity__r.SmartDeal_Key__c,
                    Requested_Product__c, Requested_Product__r.ProductCode,
                    Requested_Quantity__c, Budget__c, Delivery_City__c,
                    Requested_Date__c
                FROM Customer_Request__c
                WHERE Id IN :requestIds
                WITH USER_MODE
            ]);
        }

        Set<Id> productIds = new Set<Id>();
        for (Customer_Request__c request : requests.values()) {
            if (request.Requested_Product__c != null) productIds.add(request.Requested_Product__c);
        }

        Map<Id, List<Inventory__c>> stocks = new Map<Id, List<Inventory__c>>();
        if (!productIds.isEmpty()) {
            for (Inventory__c stock : [
                SELECT Id, Product__c, Inventory_Key__c, Warehouse_Code__c,
                    Warehouse_Name__c, City__c, Usable_Quantity__c, Unit_Price__c,
                    Lead_Time_Days__c, Is_Reconditioned__c, Last_Updated__c
                FROM Inventory__c
                WHERE Product__c IN :productIds AND Is_Active__c = true
                WITH USER_MODE
                ORDER BY Product__c, Warehouse_Code__c
            ]) {
                if (!stocks.containsKey(stock.Product__c)) {
                    stocks.put(stock.Product__c, new List<Inventory__c>());
                }
                stocks.get(stock.Product__c).add(stock);
            }
        }

        Datetime nowValue = System.now();
        for (Input item : inputs) {
            Result result = new Result();
            if (item == null || item.requestId == null ||
                item.requestId.getSObjectType() != Customer_Request__c.SObjectType) {
                result.status = 'INVALID_REQUEST';
                result.message = 'Provide an accessible Customer Request Id.';
                outputs.add(result);
                continue;
            }

            result.requestId = item.requestId;
            Customer_Request__c request = requests.get(item.requestId);
            if (request == null) {
                result.status = 'INVALID_REQUEST';
                result.message = 'Request not found or not accessible.';
                outputs.add(result);
                continue;
            }

            result.opportunityId = request.Opportunity__c;
            result.opportunityKey = request.Opportunity__r == null ? null : request.Opportunity__r.SmartDeal_Key__c;
            result.productCode = request.Requested_Product__r == null ? null : request.Requested_Product__r.ProductCode;
            result.requestedQuantity = request.Requested_Quantity__c == null ? null : request.Requested_Quantity__c.intValue();
            result.budget = request.Budget__c;
            result.deliveryCity = request.Delivery_City__c;
            result.requestedDate = request.Requested_Date__c;

            if (request.Requested_Product__c == null || request.Requested_Quantity__c == null ||
                request.Requested_Quantity__c <= 0) {
                result.status = 'NO_DATA';
                result.message = 'Request is missing a product or a positive quantity. Read-only check; no reservation created.';
                outputs.add(result);
                continue;
            }

            List<Inventory__c> productStocks = stocks.get(request.Requested_Product__c);
            if (productStocks == null || productStocks.isEmpty()) {
                result.status = 'NO_STOCK';
                result.message = 'No active inventory row exists for this product. Read-only check; no reservation created.';
                outputs.add(result);
                continue;
            }

            Boolean anyEligible = false;
            for (Inventory__c stock : productStocks) {
                Warehouse view = evaluate(stock, request, nowValue);
                result.warehouses.add(view);
                if (view.eligible) anyEligible = true;
            }

            result.status = anyEligible ? 'FEASIBLE' : 'AT_RISK';
            result.message = anyEligible
                ? 'A fresh warehouse satisfies quantity, city, delivery date and budget. Read-only check; no reservation created.'
                : 'Stock exists but no warehouse satisfies every constraint. Review blockingReasons. Read-only check; no reservation created.';
            outputs.add(result);
        }
        return outputs;
    }

    private static Warehouse evaluate(Inventory__c stock, Customer_Request__c request, Datetime nowValue) {
        Warehouse view = new Warehouse();
        view.inventoryKey = stock.Inventory_Key__c;
        view.warehouseCode = stock.Warehouse_Code__c;
        view.warehouseName = stock.Warehouse_Name__c;
        view.city = stock.City__c;
        view.usableQuantity = stock.Usable_Quantity__c;
        view.unitPrice = stock.Unit_Price__c;
        view.leadTimeDays = stock.Lead_Time_Days__c == null ? null : stock.Lead_Time_Days__c.intValue();
        view.reconditioned = stock.Is_Reconditioned__c;
        view.lastUpdated = stock.Last_Updated__c;
        view.blockingReasons = new List<String>();

        view.inventoryFresh = stock.Last_Updated__c != null &&
            stock.Last_Updated__c >= nowValue.addHours(-FRESH_HOURS) &&
            stock.Last_Updated__c <= nowValue.addMinutes(5);
        if (!view.inventoryFresh) view.blockingReasons.add('Inventory snapshot is missing, stale or incorrectly dated.');

        view.cityMatches = String.isNotBlank(request.Delivery_City__c) &&
            String.isNotBlank(stock.City__c) &&
            stock.City__c.equalsIgnoreCase(request.Delivery_City__c);
        if (!view.cityMatches) {
            view.blockingReasons.add('Warehouse city ' + stock.City__c + ' does not match delivery city ' + request.Delivery_City__c + '.');
        }

        view.stockCovers = view.usableQuantity != null &&
            view.usableQuantity >= request.Requested_Quantity__c;
        if (!view.stockCovers) {
            view.blockingReasons.add('Usable quantity ' + view.usableQuantity + ' is below requested quantity ' + request.Requested_Quantity__c + '.');
        }

        view.deliveryOnTime = view.leadTimeDays != null &&
            request.Requested_Date__c != null &&
            Date.today().addDays(view.leadTimeDays) <= request.Requested_Date__c;
        if (view.leadTimeDays == null) {
            view.blockingReasons.add('Lead time is missing.');
        } else if (request.Requested_Date__c == null) {
            view.blockingReasons.add('Requested date is missing.');
        } else {
            view.estimatedDeliveryDate = Date.today().addDays(view.leadTimeDays);
            if (!view.deliveryOnTime) view.blockingReasons.add('Estimated delivery ' + view.estimatedDeliveryDate + ' is after the requested date ' + request.Requested_Date__c + '.');
        }

        if (view.unitPrice != null) view.estimatedTotal = view.unitPrice * request.Requested_Quantity__c;
        view.budgetCovers = request.Budget__c != null && view.estimatedTotal != null &&
            view.estimatedTotal <= request.Budget__c;
        if (!view.budgetCovers) {
            view.blockingReasons.add('Estimated total ' + view.estimatedTotal + ' exceeds the budget ' + request.Budget__c + '.');
        }

        view.eligible = view.inventoryFresh && view.cityMatches && view.stockCovers &&
            view.deliveryOnTime && view.budgetCovers;
        return view;
    }

    private static List<Result> failAll(List<Input> inputs, String status, String message) {
        List<Result> outputs = new List<Result>();
        for (Input item : inputs) {
            Result result = new Result();
            result.requestId = item == null ? null : item.requestId;
            result.status = status;
            result.message = message;
            outputs.add(result);
        }
        return outputs;
    }
}
