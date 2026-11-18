public with sharing class ServiceRequestService {
    public class ServiceRequestException extends Exception {}
    private static final Set<String> CLOSED_STATUSES = new Set<String>{ 'Resolved', 'Closed' };
    // 1. Demandes ouvertes pour une priorité donnée
    public static List<Service_Request__c> getOpenRequestsByPriority(String priority) {
        return [
            SELECT Id, Name, Subject__c, Priority__c, Status__c, Days_Open__c,
                   Category__r.Name, Customer__r.Name
            FROM Service_Request__c
            WHERE Priority__c = :priority
              AND Status__c NOT IN :CLOSED_STATUSES
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
    }
    // 2. Nombre de demandes par statut
    public static Map<String, Integer> countByStatus() {
        Map<String, Integer> result = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Status__c statusValue, COUNT(Id) total
            FROM Service_Request__c
            WITH USER_MODE
            GROUP BY Status__c
        ]) {
            result.put((String) ar.get('statusValue'), (Integer) ar.get('total'));
        }
        return result;
    }
    // 3. Assigner une demande à un utilisateur
    public static Service_Request__c assignRequest(Id requestId, Id userId) {
        if (requestId == null || userId == null) {
            throw new ServiceRequestException('requestId et userId sont obligatoires.');
        }
        List<Service_Request__c> found = [
            SELECT Id, Status__c, Assigned_To__c
            FROM Service_Request__c
            WHERE Id = :requestId
            WITH USER_MODE
            LIMIT 1
        ];
        if (found.isEmpty()) {
            throw new ServiceRequestException('Demande introuvable : ' + requestId);
        }
        Service_Request__c sr = found[0];
        sr.Assigned_To__c = userId;
        if (sr.Status__c == 'New') {
            sr.Status__c = 'In Progress';
        }
        Database.SaveResult saved = Database.update(sr, AccessLevel.USER_MODE);
        if (!saved.isSuccess()) {
            throw new ServiceRequestException(saved.getErrors()[0].getMessage());
        }
        return sr;
    }
    // 4. Escalader les demandes ouvertes Low/Medium plus vieilles que daysOld jours
    public static Integer escalateStaleRequests(Integer daysOld) {
        Datetime threshold = Datetime.now().addDays(-daysOld);
        List<Service_Request__c> stale = [
            SELECT Id, Priority__c
            FROM Service_Request__c
            WHERE Status__c NOT IN :CLOSED_STATUSES
              AND Priority__c IN ('Low', 'Medium')
              AND CreatedDate < :threshold
            WITH USER_MODE
        ];
        for (Service_Request__c sr : stale) {
            sr.Priority__c = (sr.Priority__c == 'Low') ? 'Medium' : 'High';
        }
        if (!stale.isEmpty()) {
            Database.update(stale, AccessLevel.USER_MODE);
        }
        return stale.size();
    }
    // 5. Récupérer les demandes d'un client donné
    public static List<Service_Request__c> getRequestsByCustomer(Id contactId) {
    return [
        SELECT Id, Name, Subject__c, Priority__c, Status__c
        FROM Service_Request__c
        WHERE Customer__c = :contactId
        WITH USER_MODE
        ORDER BY CreatedDate DESC
    ];
}
}