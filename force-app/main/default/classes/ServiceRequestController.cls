public with sharing class ServiceRequestController {
    @AuraEnabled(cacheable=true)
    public static List<Service_Request__c> getRequests(String status) {
        if (String.isBlank(status) || status == 'All') {
            return [
                SELECT Id, Name, Subject__c, Priority__c, Status__c, Days_Open__c,
                  Customer__r.Name, Category__r.Name
                FROM Service_Request__c
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT 100
            ];
        }
        return [
            SELECT Id, Name, Subject__c, Priority__c, Status__c, Days_Open__c,
                   Customer__r.Name, Category__r.Name
            FROM Service_Request__c
            WHERE Status__c = :status
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];
    }
}