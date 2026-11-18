public with sharing class SmartDealInventoryAction {
    public class Request {
        @InvocableVariable(required=true label='Customer Request Id')
        public Id requestId;
    }

    public class Response {
        @InvocableVariable public String status;
        @InvocableVariable public String message;
        @InvocableVariable public Boolean requiresHumanReview;
        @InvocableVariable public String warehousesJson;
    }

    @InvocableMethod(
        label='Check SmartDeal Inventory'
        description='Read-only inventory check for a Customer Request.'
    )
    public static List<Response> execute(List<Request> requests) {
        List<Response> outputs = new List<Response>();
        if (requests == null || requests.isEmpty()) return outputs;

        List<SmartDealInventoryService.Input> inputs =
            new List<SmartDealInventoryService.Input>();

        for (Request req : requests) {
            SmartDealInventoryService.Input input =
                new SmartDealInventoryService.Input();
            input.requestId = req == null ? null : req.requestId;
            inputs.add(input);
        }

        List<SmartDealInventoryService.Result> results =
            SmartDealInventoryService.check(inputs);

        for (SmartDealInventoryService.Result result : results) {
            Response output = new Response();
            output.status = result.status;
            output.message = result.message;
            output.requiresHumanReview = result.requiresHumanReview;
            output.warehousesJson = JSON.serialize(result.warehouses);
            outputs.add(output);
        }
        return outputs;
    }
}