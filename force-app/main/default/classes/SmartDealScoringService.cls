public with sharing class SmartDealScoringService {
    private static final String FALLBACK_VERSION = 'v1.0';
    private static final Decimal DEFAULT_AVAILABILITY_WEIGHT = 0.30;
    private static final Decimal DEFAULT_SERVICE_WEIGHT = 0.25;
    private static final Decimal DEFAULT_MARGIN_WEIGHT = 0.20;
    private static final Decimal DEFAULT_ECO_WEIGHT = 0.15;
    private static final Decimal DEFAULT_PRIORITY_WEIGHT = 0.10;
    @TestVisible private static SmartDeal_Weight__mdt configurationOverride;
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
        @InvocableVariable(description='Storage version of the scoring configuration.')
        public String version;
    }
    @InvocableMethod(
        label='Calculate SmartDeal Rescue Score'
        description='Returns a deterministic and explainable score.'
    )
    public static List<Result> calculate(List<Factors> inputs) {
        List<Result> outputs = new List<Result>();
        if (inputs == null || inputs.isEmpty()) return outputs;
        SmartDeal_Weight__mdt config = configurationOverride;
        if (config == null) config = SmartDeal_Weight__mdt.getInstance('Default_v1');
        String version = config != null && !String.isBlank(config.Version__c)
            ? config.Version__c
            : FALLBACK_VERSION;
        Decimal availabilityWeight = weight(
            config == null ? null : config.Availability_Weight__c, DEFAULT_AVAILABILITY_WEIGHT);
        Decimal serviceWeight = weight(
            config == null ? null : config.Service_Weight__c, DEFAULT_SERVICE_WEIGHT);
        Decimal marginWeight = weight(
            config == null ? null : config.Margin_Weight__c, DEFAULT_MARGIN_WEIGHT);
        Decimal ecoWeight = weight(
            config == null ? null : config.Eco_Weight__c, DEFAULT_ECO_WEIGHT);
        Decimal priorityWeight = weight(
            config == null ? null : config.Priority_Weight__c, DEFAULT_PRIORITY_WEIGHT);
        for (Factors input : inputs) {
            if (input == null) continue;
            Decimal d = clamp(input.availability);
            Decimal s = clamp(input.service);
            Decimal m = clamp(input.margin);
            Decimal e = clamp(input.eco);
            Decimal p = clamp(input.priority);
            Decimal total = (availabilityWeight*d) + (serviceWeight*s) + (marginWeight*m)
                          + (ecoWeight*e) + (priorityWeight*p);
            Result result = new Result();
            result.version = version;
            result.score = total.setScale(2);
            result.explanation =
                'Availability ' + percent(availabilityWeight) + '=' + d +
                '; Service ' + percent(serviceWeight) + '=' + s +
                '; Margin ' + percent(marginWeight) + '=' + m +
                '; Eco ' + percent(ecoWeight) + '=' + e +
                '; Priority ' + percent(priorityWeight) + '=' + p +
                '. Final=' + result.score;
            outputs.add(result);
        }
        return outputs;
    }
    private static Decimal weight(Decimal configured, Decimal fallback) {
        return configured == null || configured < 0 || configured > 1 ? fallback : configured;
    }
    private static String percent(Decimal value) {
        Decimal pct = value * 100;
        return (pct == pct.round() ? String.valueOf(pct.intValue()) : String.valueOf(pct)) + '%';
    }
    private static Decimal clamp(Decimal value) {
        if (value == null) return 0;
        return Math.max(0, Math.min(100, value));
    }
}
