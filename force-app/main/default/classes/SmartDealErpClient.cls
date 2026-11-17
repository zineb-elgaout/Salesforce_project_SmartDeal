public with sharing class SmartDealErpClient {

    public class ErpException extends Exception {}

    public class StockItem {
        public String warehouseCode;
        public String name;
        public Integer quantity;
        public Integer leadTimeDays;
        public Decimal unitPrice;
        public Boolean reconditioned;
    }

    public class StockResponse {
        public String sku;
        public List<StockItem> warehouses;
        public Datetime lastUpdated;
    }

    public static StockResponse getStock(String sku, String city) {

        // 1. Vérifier les paramètres.
        if (String.isBlank(sku) || String.isBlank(city)) {
            throw new ErpException(
                'SKU and delivery city are required.'
            );
        }

        String cleanSku = sku.trim();

        // 2. Préparer l'appel via la Named Credential.
        HttpRequest request = new HttpRequest();

        request.setEndpoint(
            'callout:SmartDeal_ERP/api/inventory?sku=' +
            EncodingUtil.urlEncode(cleanSku, 'UTF-8') +
            '&city=' +
            EncodingUtil.urlEncode(city.trim(), 'UTF-8')
        );

        request.setMethod('GET');
        request.setHeader('Accept', 'application/json');
        request.setTimeout(10000);

        // 3. Exécuter l'appel.
        HttpResponse response;

        try {
            response = new Http().send(request);
        } catch (CalloutException ex) {
            throw new ErpException(
                'ERP callout failed. Stock is not verified.'
            );
        }

        // 4. Contrôler le statut HTTP.
        if (response.getStatusCode() == 404) {
            throw new ErpException(
                'ERP inventory not found. Check the SKU and endpoint.'
            );
        }

        if (response.getStatusCode() != 200) {
            throw new ErpException(
                'ERP unavailable. HTTP status=' +
                response.getStatusCode()
            );
        }

        if (String.isBlank(response.getBody())) {
            throw new ErpException('Empty ERP response.');
        }

        // 5. Convertir le JSON en objets Apex.
        StockResponse result;

        try {
            result = (StockResponse) JSON.deserialize(
                response.getBody(),
                StockResponse.class
            );
        } catch (JSONException ex) {
            throw new ErpException(
                'Invalid ERP JSON response.'
            );
        }

        // 6. Vérifier la structure de la réponse.
        if (
            result == null ||
            result.sku != cleanSku ||
            result.warehouses == null ||
            result.lastUpdated == null
        ) {
            throw new ErpException(
                'Incomplete or mismatched ERP response.'
            );
        }

        // 7. Refuser les données de stock invalides.
        for (StockItem item : result.warehouses) {
            if (
                item == null ||
                String.isBlank(item.name) ||
                item.quantity == null ||
                item.quantity < 0 ||
                item.leadTimeDays == null ||
                item.leadTimeDays < 0 ||
                item.unitPrice == null ||
                item.unitPrice < 0 ||
                item.reconditioned == null
            ) {
                throw new ErpException(
                    'Invalid ERP warehouse data.'
                );
            }
        }

        return result;
    }
}