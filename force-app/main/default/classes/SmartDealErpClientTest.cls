@IsTest
private class SmartDealErpClientTest {

    // Simule une réponse HTTP.
    private class ErpMock implements HttpCalloutMock {

        private Integer statusCode;
        private String body;

        public String expectedEndpoint;

        public ErpMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest request) {

            System.assertEquals(
                'GET',
                request.getMethod()
            );

            System.assertEquals(
                'application/json',
                request.getHeader('Accept')
            );

           

            if (expectedEndpoint != null) {
                System.assertEquals(
                    expectedEndpoint,
                    request.getEndpoint()
                );
            }

            HttpResponse response = new HttpResponse();

            response.setStatusCode(statusCode);
            response.setHeader(
                'Content-Type',
                'application/json'
            );
            response.setBody(body);

            return response;
        }
    }

    // Simule un timeout.
    private class TimeoutMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {
            throw new CalloutException('Read timed out');
        }
    }

    // Données fictives cohérentes avec Atlas Office.
    private static Map<String, Object> payload(String sku) {

        return new Map<String, Object>{
            'sku' => sku,

            'warehouses' => new List<Object>{

                new Map<String, Object>{
                    'warehouseCode' => 'SD-CASA',
                    'name' => 'Demo Casa',
                    'quantity' => 4,
                    'leadTimeDays' => 3,
                    'unitPrice' => 2200,
                    'reconditioned' => false
                },

                new Map<String, Object>{
                    'warehouseCode' => 'SD-MARR',
                    'name' => 'Demo Marrakech',
                    'quantity' => 2,
                    'leadTimeDays' => 4,
                    'unitPrice' => 2180,
                    'reconditioned' => false
                }
            },

            'lastUpdated' => '2026-11-17T18:00:00Z'
        };
    }

    // Vérifie qu'une erreur métier est bien déclenchée.
    private static void assertFailure(
        String sku,
        String city,
        String expected
    ) {
        Boolean failed = false;

        try {
            SmartDealErpClient.getStock(sku, city);

        } catch (SmartDealErpClient.ErpException ex) {

            failed = true;

            System.assert(
                ex.getMessage().contains(expected),
                ex.getMessage()
            );
        }

        System.assert(
            failed,
            'Expected an ERP exception.'
        );
    }

    // Test 1 : réponse valide.
    @IsTest
    static void parsesErpResponse() {

        ErpMock mock = new ErpMock(
            200,
            JSON.serialize(payload('PP-X100'))
        );

        mock.expectedEndpoint =
            'callout:SmartDeal_ERP/api/inventory' +
            '?sku=PP-X100&city=Agadir';

        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();

        SmartDealErpClient.StockResponse result =
            SmartDealErpClient.getStock(
                'PP-X100',
                'Agadir'
            );

        Test.stopTest();

        System.assertEquals('PP-X100', result.sku);
        System.assertEquals(2, result.warehouses.size());
        System.assertEquals(4, result.warehouses[0].quantity);
        System.assertEquals(2200, result.warehouses[0].unitPrice);

        System.assertEquals(
            false,
            result.warehouses[0].reconditioned
        );

        System.assertEquals(
            Datetime.newInstanceGmt(
                2026, 11, 17, 18, 0, 0
            ),
            result.lastUpdated
        );
    }

    // Test 2 : nettoyage et encodage des paramètres.
    @IsTest
    static void trimsAndEncodesParameters() {

        String sku = 'PP X/100';

        ErpMock mock = new ErpMock(
            200,
            JSON.serialize(payload(sku))
        );

        mock.expectedEndpoint =
            'callout:SmartDeal_ERP/api/inventory?sku=' +
            EncodingUtil.urlEncode(sku, 'UTF-8') +
            '&city=Agadir+Centre';

        Test.setMock(HttpCalloutMock.class, mock);

        SmartDealErpClient.StockResponse result =
            SmartDealErpClient.getStock(
                ' PP X/100 ',
                ' Agadir Centre '
            );

        System.assertEquals(sku, result.sku);
    }

    // Test 3 : erreurs HTTP.
    @IsTest
    static void handlesHttpErrors() {

        Test.setMock(
            HttpCalloutMock.class,
            new ErpMock(500, '{}')
        );

        assertFailure(
            'PP-X100',
            'Agadir',
            'HTTP status=500'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new ErpMock(404, '{}')
        );

        assertFailure(
            'PP-X100',
            'Agadir',
            'not found'
        );
    }

    // Test 4 : réponses vides, incorrectes ou incohérentes.
    @IsTest
    static void rejectsInvalidResponses() {

        Test.setMock(
            HttpCalloutMock.class,
            new ErpMock(200, '')
        );

        assertFailure(
            'PP-X100',
            'Agadir',
            'Empty ERP response'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new ErpMock(200, 'not JSON')
        );

        assertFailure(
            'PP-X100',
            'Agadir',
            'Invalid ERP JSON'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new ErpMock(200, '{}')
        );

        assertFailure(
            'PP-X100',
            'Agadir',
            'Incomplete or mismatched'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new ErpMock(
                200,
                JSON.serialize(payload('OTHER-SKU'))
            )
        );

        assertFailure(
            'PP-X100',
            'Agadir',
            'Incomplete or mismatched'
        );

        Map<String, Object> invalid = payload('PP-X100');

        List<Object> warehouses =
            (List<Object>) invalid.get('warehouses');

        Map<String, Object> firstWarehouse =
            (Map<String, Object>) warehouses[0];

        firstWarehouse.put('quantity', -1);

        Test.setMock(
            HttpCalloutMock.class,
            new ErpMock(
                200,
                JSON.serialize(invalid)
            )
        );

        assertFailure(
            'PP-X100',
            'Agadir',
            'Invalid ERP warehouse'
        );
    }

    // Test 5 : paramètres manquants.
    @IsTest
    static void rejectsMissingInputs() {

        assertFailure(
            null,
            'Agadir',
            'required'
        );

        assertFailure(
            'PP-X100',
            ' ',
            'required'
        );
    }

    // Test 6 : timeout ou échec du callout.
    @IsTest
    static void handlesTimeout() {

        Test.setMock(
            HttpCalloutMock.class,
            new TimeoutMock()
        );

        assertFailure(
            'PP-X100',
            'Agadir',
            'callout failed'
        );
    }
}