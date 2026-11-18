/**
 * This class contains unit tests for validating the behavior of Apex classes
 * and triggers.
 *
 * Unit tests are class methods that verify whether a particular piece
 * of code is working properly. Unit test methods take no arguments,
 * commit no data to the database, and are flagged with the testMethod
 * keyword in the method definition.
 *
 * All test methods in an org are executed whenever Apex code is deployed
 * to a production org to confirm correctness, ensure code
 * coverage, and prevent regressions. All Apex classes are
 * required to have at least 75% code coverage in order to be deployed
 * to a production org. In addition, all triggers must have some code coverage.
 * 
 * The @isTest class annotation indicates this class only contains test
 * methods. Classes defined with the @isTest annotation do not count against
 * the org size limit for all Apex scripts.
 *
 * See the Apex Language Reference for more information about Testing and Code Coverage.
 */
@IsTest
private class SmartDealScoringServiceTest {
    @IsTest
    static void calculatesExpectedScore() {
        SmartDealScoringService.configurationOverride = new SmartDeal_Weight__mdt(
            Availability_Weight__c=0.30, Service_Weight__c=0.25, Margin_Weight__c=0.20,
            Eco_Weight__c=0.15, Priority_Weight__c=0.10, Version__c='test-v1'
        );
        SmartDealScoringService.Factors f =
            new SmartDealScoringService.Factors();
        f.availability = 100;
        f.service = 80;
        f.margin = 70;
        f.eco = 90;
        f.priority = 60;
        Test.startTest();
        List<SmartDealScoringService.Result> results =
            SmartDealScoringService.calculate(
                new List<SmartDealScoringService.Factors>{ f }
            );
        Test.stopTest();
        System.assertEquals(1, results.size());
        System.assertEquals(83.50, results[0].score);
        System.assert(String.isNotBlank(results[0].version));
        System.assert(results[0].explanation.contains('Availability'));
    }
    @IsTest
    static void usesConfiguredWeightsAndVersion() {
        SmartDealScoringService.configurationOverride = new SmartDeal_Weight__mdt(
            Availability_Weight__c=1, Service_Weight__c=0, Margin_Weight__c=0,
            Eco_Weight__c=0, Priority_Weight__c=0, Version__c='test-v2'
        );
        SmartDealScoringService.Factors f = new SmartDealScoringService.Factors();
        f.availability = 100;
        f.service = 0;
        f.margin = 0;
        f.eco = 0;
        f.priority = 0;
        List<SmartDealScoringService.Result> results =
            SmartDealScoringService.calculate(
                new List<SmartDealScoringService.Factors>{ f }
            );
        System.assertEquals(100, results[0].score);
        System.assertEquals('test-v2', results[0].version);
        System.assert(results[0].explanation.contains('Availability 100%'));
    }
    @IsTest
    static void clampsInvalidValues() {
        SmartDealScoringService.Factors f =
            new SmartDealScoringService.Factors();
        f.availability = 150;
        f.service = -20;
        f.margin = null;
        f.eco = 50;
        f.priority = 50;
        List<SmartDealScoringService.Result> results =
            SmartDealScoringService.calculate(
                new List<SmartDealScoringService.Factors>{ f }
            );
        System.assert(results[0].score >= 0);
        System.assert(results[0].score <= 100);
    }
}

