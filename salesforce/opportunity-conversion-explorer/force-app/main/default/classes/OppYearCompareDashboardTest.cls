@IsTest
private class OppYearCompareDashboardTest {
    private static final Id OWNER_ID = UserInfo.getUserId();
    private static final Id PRODUCT_A_ID = '01t000000000001';
    private static final Id PRODUCT_B_ID = '01t000000000002';

    @IsTest
    static void buildsMatchedYearComparisonAndExcludesRapidLoss() {
        User owner = [SELECT Id, Name, Sales_Team__c FROM User WHERE Id = :OWNER_ID];
        List<Opportunity> opportunities = new List<Opportunity>{
            opportunity('006000000000001', '2025 Won', 'Closed Won', '2025-01-10T00:00:00.000Z', '2025-02-09', 150000, owner),
            opportunity('006000000000002', 'Rapid Loss', 'Closed Lost', '2025-03-01T00:00:00.000Z', '2025-03-01', 9000, owner),
            opportunity('006000000000003', '2026 Lost', 'Closed Lost', '2026-02-01T00:00:00.000Z', '2026-02-21', 50000, owner),
            opportunity('006000000000004', '2026 Open No Product', 'Proposal', '2026-02-15T00:00:00.000Z', '2026-08-31', 25000, owner),
            opportunity('006000000000005', '2026 Won', 'Closed Won', '2026-03-01T00:00:00.000Z', '2026-04-01', 200000, owner)
        };
        List<OppYearCompareDashboardController.StageEvent> events = new List<OppYearCompareDashboardController.StageEvent>{
            event('006000000000001', 'Engagement', 2025, 1, 10),
            event('006000000000001', 'Define Needs', 2025, 1, 12),
            event('006000000000001', 'Proposal', 2025, 1, 20),
            event('006000000000001', 'Closed Won', 2025, 2, 9),
            event('006000000000002', 'Engagement', 2025, 3, 1),
            event('006000000000002', 'Define Needs', 2025, 3, 1),
            event('006000000000002', 'Closed Lost', 2025, 3, 1),
            event('006000000000003', 'Engagement', 2026, 2, 1),
            event('006000000000003', 'Closed Lost', 2026, 2, 21),
            event('006000000000005', 'Engagement', 2026, 3, 1),
            event('006000000000005', 'Closed Won', 2026, 4, 1)
        };
        Map<Id, List<OppYearCompareDashboardController.ProductLink>> productMap = new Map<Id, List<OppYearCompareDashboardController.ProductLink>>{
            (Id)'006000000000001' => products(PRODUCT_A_ID, 'Platform'),
            (Id)'006000000000002' => products(PRODUCT_A_ID, 'Platform'),
            (Id)'006000000000003' => products(PRODUCT_B_ID, 'Services'),
            (Id)'006000000000005' => products(PRODUCT_A_ID, 'Platform')
        };

        Test.startTest();
        OppYearCompareDashboardController.DashboardDTO result =
            OppYearCompareDashboardController.buildDashboard(
                opportunities, events, productMap, Date.newInstance(2026, 8, 31), null, null, false
            );
        Test.stopTest();

        System.assertEquals(1, result.years[0].createdCount);
        System.assertEquals(1, result.years[0].rapidLossExcluded);
        System.assertEquals(100, result.years[0].winRate);
        System.assertEquals(3, result.years[1].createdCount);
        System.assertEquals(1, result.years[1].wonCount);
        System.assertEquals(1, result.years[1].lostCount);
        System.assertEquals(1, result.years[1].openCount);
        System.assertEquals(50, result.years[1].winRate);
        System.assertEquals(150000, result.years[0].averageFinalDealValue);
        System.assertEquals(125000, result.years[1].averageFinalDealValue);
        Decimal expected2025CloseDays = Decimal.valueOf(String.valueOf(
            opportunities[0].CreatedDate.date().daysBetween(Date.newInstance(2025, 2, 9))
        ));
        Decimal expected2026CloseDays = Decimal.valueOf(String.valueOf(
            opportunities[2].CreatedDate.date().daysBetween(Date.newInstance(2026, 2, 21)) +
            opportunities[4].CreatedDate.date().daysBetween(Date.newInstance(2026, 4, 1))
        )) / 2;
        System.assertEquals(expected2025CloseDays, result.years[0].averageDaysToClose);
        System.assertEquals(expected2026CloseDays.setScale(1), result.years[1].averageDaysToClose);
        System.assertEquals(1, result.noProductOpportunityCount);
        System.assertEquals(2, result.closedWonOpportunities.size());
        System.assertEquals(1, result.availableOwners.size());
        System.assertEquals(2, result.availableProducts.size());
        System.assertEquals(3, result.products.size());
        System.assertEquals('Platform', result.products[1].productName);
        System.assertEquals(1, result.products[1].closedCount2025);
        System.assertEquals(1, result.products[1].closedCount2026);
        System.assertEquals('Jan 1–Aug 31 matched YTD', result.comparisonLabel);

        OppYearCompareDashboardController.StageComparisonDTO proposal = result.stages[3];
        System.assertEquals('Proposal', proposal.stageName);
        System.assertEquals(1, proposal.count2025);
        System.assertEquals(1, proposal.count2026);
    }

    @IsTest
    static void appliesOwnerAndProductFiltersWhileKeepingProductless() {
        User owner = [SELECT Id, Name, Sales_Team__c FROM User WHERE Id = :OWNER_ID];
        List<Opportunity> opportunities = new List<Opportunity>{
            opportunity('006000000000011', 'Product A', 'Closed Won', '2026-01-02T00:00:00.000Z', '2026-01-20', 100, owner),
            opportunity('006000000000012', 'Product B', 'Closed Lost', '2026-01-03T00:00:00.000Z', '2026-01-21', 200, owner),
            opportunity('006000000000013', 'No Product', 'Proposal', '2026-01-04T00:00:00.000Z', '2026-02-01', 300, owner)
        };
        Map<Id, List<OppYearCompareDashboardController.ProductLink>> productMap = new Map<Id, List<OppYearCompareDashboardController.ProductLink>>{
            (Id)'006000000000011' => products(PRODUCT_A_ID, 'Platform'),
            (Id)'006000000000012' => products(PRODUCT_B_ID, 'Services')
        };

        OppYearCompareDashboardController.DashboardDTO productFiltered =
            OppYearCompareDashboardController.buildDashboard(
                opportunities,
                new List<OppYearCompareDashboardController.StageEvent>(),
                productMap,
                Date.newInstance(2026, 12, 31),
                null,
                new Set<Id>{ PRODUCT_B_ID },
                true
            );
        System.assertEquals(2, productFiltered.years[1].createdCount, 'Selected product plus productless');
        System.assertEquals(true, productFiltered.isTruncated);

        OppYearCompareDashboardController.DashboardDTO ownerFiltered =
            OppYearCompareDashboardController.buildDashboard(
                opportunities,
                new List<OppYearCompareDashboardController.StageEvent>(),
                productMap,
                Date.newInstance(2026, 12, 31),
                new Set<Id>(),
                null,
                false
            );
        System.assertEquals(0, ownerFiltered.years[1].createdCount);
        System.assertEquals(2, ownerFiltered.availableProducts.size());
        System.assertEquals(1, ownerFiltered.noProductOpportunityCount);
    }

    @IsTest
    static void publicMethodReturnsDashboardForIsolatedTestData() {
        Test.startTest();
        OppYearCompareDashboardController.DashboardDTO result =
            OppYearCompareDashboardController.getDashboardData(
                Date.newInstance(2026, 2, 28), null, null
            );
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assertEquals(2, result.years.size());
        System.assertEquals(9, result.stages.size());
    }

    private static Opportunity opportunity(
        String opportunityId,
        String name,
        String stage,
        String createdDate,
        String closeDate,
        Decimal amount,
        User owner
    ) {
        String jsonValue = '{"attributes":{"type":"Opportunity"},' +
            '"Id":"' + opportunityId + '",' +
            '"Name":"' + name + '",' +
            '"OwnerId":"' + owner.Id + '",' +
            '"StageName":"' + stage + '",' +
            '"CreatedDate":"' + createdDate + '",' +
            '"CloseDate":"' + closeDate + '",' +
            '"Amount":' + amount + '}';
        Opportunity result = (Opportunity)JSON.deserialize(jsonValue, Opportunity.class);
        result.putSObject('Owner', owner);
        return result;
    }

    private static OppYearCompareDashboardController.StageEvent event(
        String opportunityId,
        String stage,
        Integer year,
        Integer month,
        Integer day
    ) {
        return new OppYearCompareDashboardController.StageEvent(
            (Id)opportunityId,
            stage,
            Datetime.newInstance(year, month, day, 12, 0, 0)
        );
    }

    private static List<OppYearCompareDashboardController.ProductLink> products(
        Id productId,
        String productName
    ) {
        return new List<OppYearCompareDashboardController.ProductLink>{
            new OppYearCompareDashboardController.ProductLink(productId, productName)
        };
    }
}
