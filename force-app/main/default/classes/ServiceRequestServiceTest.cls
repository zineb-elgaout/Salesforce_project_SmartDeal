@IsTest
private class ServiceRequestServiceTest {
    @TestSetup
    static void makeData() {
        Service_Category__c cat = new Service_Category__c(Name = 'Network Issue');
        insert cat;
        Contact customer = new Contact(LastName = 'Testeur', Email = 'testeur@example.com');
        insert customer;
        List<Service_Request__c> reqs = new List<Service_Request__c>{
            new Service_Request__c(Subject__c = 'A', Priority__c = 'High', Status__c = 'New',
                Category__c = cat.Id, Customer__c = customer.Id),
            new Service_Request__c(Subject__c = 'B', Priority__c = 'High', Status__c = 'In Progress',
                Category__c = cat.Id, Customer__c = customer.Id),
            new Service_Request__c(Subject__c = 'C', Priority__c = 'Low', Status__c = 'New',
                Category__c = cat.Id, Customer__c = customer.Id),
            new Service_Request__c(Subject__c = 'D', Priority__c = 'Critical', Status__c = 'New',
                Category__c = cat.Id, Customer__c = customer.Id, Assigned_To__c = UserInfo.getUserId())
        };
        insert reqs;
    }
    @IsTest
    static void getOpenRequestsByPriority_returnsOnlyOpenHigh() {
        Test.startTest();
        List<Service_Request__c> result = ServiceRequestService.getOpenRequestsByPriority('High');
        Test.stopTest();
        Assert.areEqual(2, result.size(), 'Deux demandes High ouvertes attendues');
    }
    @IsTest
    static void countByStatus_groupsCorrectly() {
        Map<String, Integer> counts = ServiceRequestService.countByStatus();
        Assert.areEqual(3, counts.get('New'), 'Trois demandes New (A, C, D)');
        Assert.areEqual(1, counts.get('In Progress'), 'Une demande In Progress (B)');
    }
    @IsTest
    static void assignRequest_setsUserAndMovesToInProgress() {
        Service_Request__c sr = [SELECT Id FROM Service_Request__c WHERE Subject__c = 'A' LIMIT 1];
        Test.startTest();
        ServiceRequestService.assignRequest(sr.Id, UserInfo.getUserId());
        Test.stopTest();
        Service_Request__c after = [SELECT Assigned_To__c, Status__c FROM Service_Request__c WHERE Id = :sr.Id];
        Assert.areEqual(UserInfo.getUserId(), after.Assigned_To__c, 'Assigned To doit être renseigné');
        Assert.areEqual('In Progress', after.Status__c, 'Une demande New passe en In Progress');
    }
    @IsTest
    static void assignRequest_withNullArguments_throws() {
        try {
            ServiceRequestService.assignRequest(null, null);
            Assert.fail('Une exception était attendue');
        } catch (ServiceRequestService.ServiceRequestException e) {
            Assert.isTrue(e.getMessage().contains('obligatoires'), 'Message inattendu : ' + e.getMessage());
        }
    }
    @IsTest
    static void escalateStaleRequests_raisesOldLowPriority() {
        Service_Request__c old = [SELECT Id FROM Service_Request__c WHERE Subject__c = 'C' LIMIT 1];
        Test.setCreatedDate(old.Id, Datetime.now().addDays(-10));
        Test.startTest();
        Integer count = ServiceRequestService.escalateStaleRequests(7);
        Test.stopTest();
        Assert.areEqual(1, count, 'Une seule demande est assez ancienne');
        Assert.areEqual('Medium', [SELECT Priority__c FROM Service_Request__c WHERE Id = :old.Id].Priority__c);
    }
}