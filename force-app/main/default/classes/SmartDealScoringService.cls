public with sharing class SmartDealScoringService {
    public class Factors {
        @InvocableVariable(required=true label='Availability 0-100')
        public Decimal availability;
        @InvocableVariable(required=true label='Service 0-100')
        public Decimal service;
        @InvocableVariable(required=true label='Margin 0-100')
        public Decimal margin;
        @InvocableVariable(required=true label='Eco efficiency 0-100')
        public Decimal eco;
        @InvocableVariable(required=true label='Customer priority 0-100')
        public Decimal priority;
    }
    public class Result {
        @InvocableVariable public Decimal score;
        @InvocableVariable public String explanation;
    }
    @InvocableMethod(
        label='Calculate SmartDeal Rescue Score'
        description='Returns a deterministic and explainable score.'
    )
    public static List<Result> calculate(List<Factors> inputs) {
        List<Result> outputs = new List<Result>();
        for (Factors input : inputs) {
            Decimal d = clamp(input.availability);
            Decimal s = clamp(input.service);
            Decimal m = clamp(input.margin);
            Decimal e = clamp(input.eco);
            Decimal p = clamp(input.priority);
            Decimal total = (0.30*d) + (0.25*s) + (0.20*m)
                          + (0.15*e) + (0.10*p);
            Result result = new Result();
            result.score = total.setScale(2);
            result.explanation =
                'Availability 30%=' + d + '; Service 25%=' + s +
                '; Margin 20%=' + m + '; Eco 15%=' + e +
                '; Priority 10%=' + p + '. Final=' + result.score;
            outputs.add(result);
        }
        return outputs;
    }
    private static Decimal clamp(Decimal value) {
        if (value == null) return 0;
        return Math.max(0, Math.min(100, value));
    }
}
