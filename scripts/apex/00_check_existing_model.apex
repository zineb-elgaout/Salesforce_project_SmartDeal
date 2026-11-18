// Read-only preflight. Run from the root of the existing Salesforce project.
Map<String,List<String>> requiredFields=new Map<String,List<String>>{
    'Opportunity'=>new List<String>{'SmartDeal_Key__c','Feasibility_Status__c','Rescue_Required__c'},
    'Product2'=>new List<String>{'ERP_Product_ID__c','ProductCode','IsActive'},
    'Inventory__c'=>new List<String>{'Inventory_Key__c','Product__c','Warehouse_Code__c',
        'Warehouse_Name__c','City__c','Available_Quantity__c','Reserved_Quantity__c',
        'Usable_Quantity__c','Unit_Price__c','Lead_Time_Days__c','Is_Reconditioned__c',
        'Is_Active__c','Last_Updated__c','ERP_Source__c'},
    'Customer_Request__c'=>new List<String>{'Original_Message__c','Requested_Product__c',
        'Requested_Quantity__c','Budget__c','Delivery_City__c','Requested_Date__c',
        'Opportunity__c','Validation_Status__c','Consent_Status__c','Original_Channel__c',
        'Extraction_Source__c','Validated_By__c','Validation_Date__c'},
    'Rescue_Scenario__c'=>new List<String>{'Opportunity__c','Scenario_Type__c',
        'Proposed_Product__c','Proposed_Quantity__c','Warehouse_Code__c','Warehouse_Name__c',
        'Estimated_Delivery_Date__c','Is_Reconditioned__c','Assumptions__c','Data_Freshness__c',
        'Availability_Score__c','Service_Score__c','Margin_Score__c','Eco_Score__c',
        'Priority_Score__c','Total_Score__c','Rank__c','Score_Version__c','Explanation__c',
        'Selected__c','Decision_By__c','Decision_Date__c','Decision_Comment__c'},
    'SmartDeal_Weight__mdt'=>new List<String>{'Availability_Weight__c','Service_Weight__c',
        'Margin_Weight__c','Eco_Weight__c','Priority_Weight__c','Minimum_Accepted_Score__c',
        'Maximum_Scenarios__c','Version__c','Active__c'}
};
Map<String,Schema.SObjectType> allTypes=Schema.getGlobalDescribe();
List<String> missing=new List<String>();
for(String objectName:requiredFields.keySet()) {
    if(!allTypes.containsKey(objectName)) {missing.add(objectName); continue;}
    Map<String,Schema.SObjectField> fields=allTypes.get(objectName).getDescribe().fields.getMap();
    for(String fieldName:requiredFields.get(objectName)) {
        if(!fields.containsKey(fieldName)) missing.add(objectName+'.'+fieldName);
    }
}
System.assert(missing.isEmpty(),'Missing API names: '+String.join(missing,', '));
for(String path:new List<String>{'Opportunity.SmartDeal_Key__c',
    'Product2.ERP_Product_ID__c','Inventory__c.Inventory_Key__c'}) {
    List<String> parts=path.split('\\.');
    Schema.DescribeFieldResult field=allTypes.get(parts[0]).getDescribe().fields.getMap()
        .get(parts[1]).getDescribe();
    System.assert(field.isExternalId() && field.isUnique(),path+' must be External ID and Unique.');
}
Map<String,String> lookupTargets=new Map<String,String>{
    'Customer_Request__c.Requested_Product__c'=>'Product2',
    'Customer_Request__c.Opportunity__c'=>'Opportunity',
    'Inventory__c.Product__c'=>'Product2',
    'Rescue_Scenario__c.Opportunity__c'=>'Opportunity',
    'Rescue_Scenario__c.Proposed_Product__c'=>'Product2'
};
for(String path:lookupTargets.keySet()) {
    List<String> parts=path.split('\\.');
    Schema.DescribeFieldResult field=allTypes.get(parts[0]).getDescribe().fields.getMap()
        .get(parts[1]).getDescribe();
    Boolean correctTarget=false;
    for(Schema.SObjectType target:field.getReferenceTo()) {
        if(target.getDescribe().getName()==lookupTargets.get(path)) correctTarget=true;
    }
    System.assert(correctTarget,'Incorrect relationship target: '+path);
}
Map<String,List<String>> expectedPicklists=new Map<String,List<String>>{
    'Customer_Request__c.Validation_Status__c'=>new List<String>{'Draft','Validated'},
    'Customer_Request__c.Consent_Status__c'=>new List<String>{'Unknown'},
    'Customer_Request__c.Original_Channel__c'=>new List<String>{'Manual'},
    'Customer_Request__c.Extraction_Source__c'=>new List<String>{'Manual'},
    'Opportunity.Feasibility_Status__c'=>new List<String>{'Not Checked','Feasible','At Risk','Rescued'},
    'Rescue_Scenario__c.Scenario_Type__c'=>new List<String>{'Reconditioned Product','Partial Delivery'}
};
for(String path:expectedPicklists.keySet()) {
    List<String> parts=path.split('\\.');
    Schema.DescribeFieldResult field=allTypes.get(parts[0]).getDescribe().fields.getMap()
        .get(parts[1]).getDescribe();
    Set<String> activeValues=new Set<String>();
    for(Schema.PicklistEntry entry:field.getPicklistValues()) {
        if(entry.isActive()) activeValues.add(entry.getValue());
    }
    for(String value:expectedPicklists.get(path)) {
        System.assert(activeValues.contains(value),'Missing active picklist API value: '+path+'='+value);
    }
}
System.assert(allTypes.get('Inventory__c').getDescribe().fields.getMap()
    .get('Usable_Quantity__c').getDescribe().isCalculated(),
    'Usable_Quantity__c must be the existing available-minus-reserved formula.');
List<SObject> configs=Database.query('SELECT DeveloperName,Active__c,Version__c,'+
    'Availability_Weight__c,Service_Weight__c,Margin_Weight__c,Eco_Weight__c,'+
    'Priority_Weight__c,Minimum_Accepted_Score__c FROM SmartDeal_Weight__mdt '+
    'WHERE DeveloperName = \'Default_v1\'');
System.assertEquals(1,configs.size(),'Create only the missing Default_v1 record in Setup.');
SObject config=configs[0];
System.assertEquals(true,config.get('Active__c'),'Default_v1 must be active.');
System.assert(!String.isBlank((String)config.get('Version__c')),'A score version is required.');
Decimal threshold=(Decimal)config.get('Minimum_Accepted_Score__c');
System.assert(threshold!=null && threshold>=0 && threshold<=100,'Threshold must be between 0 and 100.');
Decimal sum=0;
for(String name:new List<String>{'Availability_Weight__c','Service_Weight__c',
    'Margin_Weight__c','Eco_Weight__c','Priority_Weight__c'}) {
    Decimal value=(Decimal)config.get(name);
    System.assert(value!=null && value>=0 && value<=1,'Invalid weight: '+name); sum+=value;
}
System.assert(sum==1,'Weights must sum to 1.');
Set<String> keys=new Set<String>{'OPP-DEMO-ATLAS-001','OPP-DEMO-EDUNOVA-001',
    'OPP-DEMO-GREENBUILD-001'};
List<SObject> opps=Database.query('SELECT Id,Name,SmartDeal_Key__c FROM Opportunity '+
    'WHERE SmartDeal_Key__c IN :keys');
System.assertEquals(3,opps.size(),'Expected the 3 imported opportunities. Do not recreate them.');
System.debug(LoggingLevel.ERROR,'SMARTDEAL PREFLIGHT OK. Existing model and 3 opportunities found.');
