@IsTest
private class OpportunityConversionDashboardTest {
    private static final Id FIRST_OPPORTUNITY_ID = (Id) '006000000000001AAA';
    private static final Id SECOND_OPPORTUNITY_ID = (Id) '006000000000002AAA';
    private static final Id THIRD_OPPORTUNITY_ID = (Id) '006000000000003AAA';
    private static final Id FIRST_PRODUCT_ID = (Id) '01t000000000001AAA';
    private static final Id SECOND_PRODUCT_ID = (Id) '01t000000000002AAA';

    @IsTest
    static void countsUniqueConversionsAndRequiresCorrectSequence() {
        List<OpportunityConversionDashboardController.StageEvent> events = new List<OpportunityConversionDashboardController.StageEvent>{
            event(FIRST_OPPORTUNITY_ID, 'Proposal', 2025, 2, 1),
            event(FIRST_OPPORTUNITY_ID, 'Proposal', 2025, 2, 5),
            event(FIRST_OPPORTUNITY_ID, 'Closed Won', 2025, 2, 20),
            event(SECOND_OPPORTUNITY_ID, 'Proposal', 2025, 3, 1),
            event(THIRD_OPPORTUNITY_ID, 'Closed Won', 2025, 4, 1),
            event(THIRD_OPPORTUNITY_ID, 'Proposal', 2025, 4, 2)
        };

        Map<Id, Opportunity> opportunities = new Map<Id, Opportunity>{
            FIRST_OPPORTUNITY_ID => new Opportunity(
                Id = FIRST_OPPORTUNITY_ID,
                Name = 'Converted Opportunity',
                Amount = 125000,
                StageName = 'Closed Won'
            ),
            SECOND_OPPORTUNITY_ID => new Opportunity(
                Id = SECOND_OPPORTUNITY_ID,
                Name = 'Still Open',
                Amount = 50000,
                StageName = 'Negotiation'
            )
        };

        OpportunityConversionDashboardController.PeriodDTO result =
            OpportunityConversionDashboardController.calculatePeriod(
                'proposal-2025',
                '2025 Proposal Conversion',
                'Proposal',
                Date.newInstance(2025, 1, 1),
                Date.newInstance(2025, 12, 31),
                events,
                opportunities
            );

        System.assertEquals(3, result.totalEntered, 'Each Opportunity should be counted only once.');
        System.assertEquals(1, result.totalConverted, 'Closed Won must occur after Proposal.');
        System.assertEquals(33.3, result.conversionRate);
        System.assertEquals(FIRST_OPPORTUNITY_ID, result.convertedOpportunities[0].opportunityId);
        System.assertEquals(19, result.convertedOpportunities[0].daysToConvert);
    }

    @IsTest
    static void excludesEventsOutsidePeriodAndHandlesNoConversions() {
        List<OpportunityConversionDashboardController.StageEvent> events = new List<OpportunityConversionDashboardController.StageEvent>{
            event(FIRST_OPPORTUNITY_ID, 'Verbal', 2025, 12, 31),
            event(FIRST_OPPORTUNITY_ID, 'Closed Won', 2026, 1, 10),
            event(SECOND_OPPORTUNITY_ID, 'Verbal', 2026, 8, 31),
            event(SECOND_OPPORTUNITY_ID, 'Closed Won', 2026, 9, 1)
        };

        OpportunityConversionDashboardController.PeriodDTO result =
            OpportunityConversionDashboardController.calculatePeriod(
                'verbal-2026',
                'Jan–Aug 2026 Verbal Conversion',
                'Verbal',
                Date.newInstance(2026, 1, 1),
                Date.newInstance(2026, 8, 31),
                events,
                new Map<Id, Opportunity>()
            );

        System.assertEquals(1, result.totalEntered);
        System.assertEquals(0, result.totalConverted);
        System.assertEquals(0, result.conversionRate);
        System.assertEquals(0, result.convertedOpportunities.size());
    }

    @IsTest
    static void dashboardMethodReturnsBothConfiguredPeriods() {
        Test.startTest();
        OpportunityConversionDashboardController.DashboardDTO result =
            OpportunityConversionDashboardController.getDashboardData();
        Test.stopTest();

        System.assertNotEquals(null, result.generatedAt);
        System.assertEquals(2, result.periods.size());
        System.assertEquals('Proposal', result.periods[0].sourceStage);
        System.assertEquals('Verbal', result.periods[1].sourceStage);
    }

    @IsTest
    static void customDashboardAcceptsValidFilters() {
        Test.startTest();
        OpportunityConversionDashboardController.PeriodDTO result =
            OpportunityConversionDashboardController.getCustomConversionData(
                Date.newInstance(2026, 1, 1),
                Date.newInstance(2026, 8, 31),
                'Verbal',
                null,
                null
            );
        Test.stopTest();

        System.assertEquals('Verbal', result.sourceStage);
        System.assertEquals(Date.newInstance(2026, 1, 1), result.startDate);
        System.assertEquals(Date.newInstance(2026, 8, 31), result.endDate);
        System.assertEquals(0, result.totalEntered);
        System.assertEquals(0, result.availableProducts.size());
        System.assertEquals(false, result.hasNoProduct);
        System.assertEquals(0, result.noProductOpportunityCount);
    }

    @IsTest
    static void customDashboardRejectsInvalidFilters() {
        Boolean invalidDatesRejected = false;
        Boolean invalidStageRejected = false;

        try {
            OpportunityConversionDashboardController.getCustomConversionData(
                Date.newInstance(2026, 9, 1),
                Date.newInstance(2026, 1, 1),
                'Proposal',
                null,
                null
            );
        } catch (AuraHandledException expectedError) {
            invalidDatesRejected = true;
        }

        try {
            OpportunityConversionDashboardController.getCustomConversionData(
                Date.newInstance(2026, 1, 1),
                Date.newInstance(2026, 8, 31),
                'Closed Won',
                null,
                null
            );
        } catch (AuraHandledException expectedError) {
            invalidStageRejected = true;
        }

        System.assertEquals(true, invalidDatesRejected);
        System.assertEquals(true, invalidStageRejected);
    }

    @IsTest
    static void classifiesWonLostAndOpenOutcomes() {
        List<OpportunityConversionDashboardController.StageEvent> events = new List<OpportunityConversionDashboardController.StageEvent>{
            event(FIRST_OPPORTUNITY_ID, 'Proposal', 2026, 1, 2),
            event(FIRST_OPPORTUNITY_ID, 'Closed Won', 2026, 1, 12),
            event(SECOND_OPPORTUNITY_ID, 'Proposal', 2026, 2, 1),
            event(SECOND_OPPORTUNITY_ID, 'Closed Lost', 2026, 2, 8),
            event(THIRD_OPPORTUNITY_ID, 'Proposal', 2026, 3, 1)
        };

        OpportunityConversionDashboardController.PeriodDTO result =
            OpportunityConversionDashboardController.calculatePeriod(
                'outcomes',
                'Outcome Test',
                'Proposal',
                Date.newInstance(2026, 1, 1),
                Date.newInstance(2026, 8, 31),
                events,
                new Map<Id, Opportunity>(),
                true
            );

        System.assertEquals(3, result.totalEntered);
        System.assertEquals(1, result.totalConverted);
        System.assertEquals(1, result.totalLost);
        System.assertEquals(1, result.totalOpen);
        System.assertEquals(2, result.totalClosed);
        System.assertEquals(50.0, result.closedWinRate);
        System.assertEquals(3, result.opportunities.size());
        System.assertEquals('Won', result.opportunities[0].outcome);
        System.assertEquals('Lost', result.opportunities[1].outcome);
        System.assertEquals('Open', result.opportunities[2].outcome);
    }

    @IsTest
    static void excludesSameDayEngagementToLostFromTheCohort() {
        List<OpportunityConversionDashboardController.StageEvent> events =
            new List<OpportunityConversionDashboardController.StageEvent>{
                eventAt(FIRST_OPPORTUNITY_ID, 'Engagement', 2026, 1, 2, 9),
                eventAt(FIRST_OPPORTUNITY_ID, 'Define Needs', 2026, 1, 2, 10),
                eventAt(FIRST_OPPORTUNITY_ID, 'Solutioning', 2026, 1, 2, 11),
                eventAt(FIRST_OPPORTUNITY_ID, 'Proposal', 2026, 1, 2, 12),
                eventAt(FIRST_OPPORTUNITY_ID, 'Closed Lost', 2026, 1, 2, 17),
                eventAt(SECOND_OPPORTUNITY_ID, 'Engagement', 2026, 1, 3, 9),
                eventAt(SECOND_OPPORTUNITY_ID, 'Define Needs', 2026, 1, 3, 10),
                eventAt(SECOND_OPPORTUNITY_ID, 'Closed Lost', 2026, 1, 4, 10)
            };

        OpportunityConversionDashboardController.PeriodDTO result =
            OpportunityConversionDashboardController.calculatePeriod(
                'rapid-loss-exclusion',
                'Rapid Loss Exclusion',
                'Define Needs',
                Date.newInstance(2026, 1, 1),
                Date.newInstance(2026, 1, 31),
                events,
                new Map<Id, Opportunity>(),
                true
            );

        System.assertEquals(1, result.rapidLossExcluded);
        System.assertEquals(1, result.totalEntered);
        System.assertEquals(1, result.totalLost);
        System.assertEquals(1, result.totalClosed);
        System.assertEquals(1, result.opportunities.size());
        System.assertEquals(SECOND_OPPORTUNITY_ID, result.opportunities[0].opportunityId);
    }

    @IsTest
    static void productFilterIncludesAnyMatchAndCountsOpportunityOnce() {
        Set<Id> opportunityIds = new Set<Id>{
            FIRST_OPPORTUNITY_ID,
            SECOND_OPPORTUNITY_ID,
            THIRD_OPPORTUNITY_ID
        };
        Map<Id, Set<Id>> productsByOpportunity = new Map<Id, Set<Id>>{
            FIRST_OPPORTUNITY_ID => new Set<Id>{ FIRST_PRODUCT_ID, SECOND_PRODUCT_ID },
            SECOND_OPPORTUNITY_ID => new Set<Id>{ SECOND_PRODUCT_ID }
        };

        Set<Id> secondProductMatches =
            OpportunityConversionDashboardController.resolveProductFilteredOpportunityIds(
                opportunityIds,
                productsByOpportunity,
                new List<Id>{ SECOND_PRODUCT_ID }
            );
        Set<Id> firstProductAndNoProductMatches =
            OpportunityConversionDashboardController.resolveProductFilteredOpportunityIds(
                opportunityIds,
                productsByOpportunity,
                new List<Id>{ FIRST_PRODUCT_ID }
            );

        System.assertEquals(
            new Set<Id>{ FIRST_OPPORTUNITY_ID, SECOND_OPPORTUNITY_ID, THIRD_OPPORTUNITY_ID },
            secondProductMatches,
            'Productless Opportunities are always included, and matches are counted once.'
        );
        System.assertEquals(
            new Set<Id>{ FIRST_OPPORTUNITY_ID, THIRD_OPPORTUNITY_ID },
            firstProductAndNoProductMatches
        );
    }

    @IsTest
    static void ownerFilterControlsTheIncludedCohort() {
        Id firstOwnerId = (Id) '005000000000001AAA';
        Id secondOwnerId = (Id) '005000000000002AAA';
        Set<Id> opportunityIds = new Set<Id>{
            FIRST_OPPORTUNITY_ID,
            SECOND_OPPORTUNITY_ID,
            THIRD_OPPORTUNITY_ID
        };
        Map<Id, Id> ownersByOpportunity = new Map<Id, Id>{
            FIRST_OPPORTUNITY_ID => firstOwnerId,
            SECOND_OPPORTUNITY_ID => secondOwnerId,
            THIRD_OPPORTUNITY_ID => firstOwnerId
        };

        Set<Id> matches =
            OpportunityConversionDashboardController.resolveOwnerFilteredOpportunityIds(
                opportunityIds,
                ownersByOpportunity,
                new List<Id>{ firstOwnerId }
            );

        System.assertEquals(
            new Set<Id>{ FIRST_OPPORTUNITY_ID, THIRD_OPPORTUNITY_ID },
            matches
        );
    }

    @IsTest
    static void buildsSidebarChoicesAndDecoratesRows() {
        User owner = [
            SELECT Id, Name, Sales_Team__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
        Opportunity firstOpportunity = new Opportunity(
            Id = FIRST_OPPORTUNITY_ID,
            Name = 'First Opportunity',
            OwnerId = owner.Id,
            StageName = 'Proposal'
        );
        Opportunity secondOpportunity = new Opportunity(
            Id = SECOND_OPPORTUNITY_ID,
            Name = 'Second Opportunity',
            OwnerId = owner.Id,
            StageName = 'Proposal'
        );
        firstOpportunity.putSObject('Owner', owner);
        secondOpportunity.putSObject('Owner', owner);
        Map<Id, Opportunity> opportunities = new Map<Id, Opportunity>{
            firstOpportunity.Id => firstOpportunity,
            secondOpportunity.Id => secondOpportunity
        };

        OpportunityConversionDashboardController.DimensionContext context =
            OpportunityConversionDashboardController.buildDimensionContext(opportunities);
        Map<Id, Opportunity> subset =
            OpportunityConversionDashboardController.subsetOpportunities(
                opportunities,
                new Set<Id>{ FIRST_OPPORTUNITY_ID }
            );
        List<OpportunityConversionDashboardController.ConvertedOpportunityDTO> rows =
            new List<OpportunityConversionDashboardController.ConvertedOpportunityDTO>{
                new OpportunityConversionDashboardController.ConvertedOpportunityDTO(),
                new OpportunityConversionDashboardController.ConvertedOpportunityDTO()
            };
        rows[0].opportunityId = FIRST_OPPORTUNITY_ID;
        rows[1].opportunityId = SECOND_OPPORTUNITY_ID;
        OpportunityConversionDashboardController.addProductNames(
            rows,
            new Map<Id, String>{ FIRST_OPPORTUNITY_ID => 'Analytics' },
            new Map<Id, List<String>>{
                FIRST_OPPORTUNITY_ID => new List<String>{ 'Analytics' }
            }
        );

        System.assertEquals(1, context.availableOwners.size());
        System.assertEquals(2, context.availableOwners[0].opportunityCount);
        System.assertEquals(String.valueOf(owner.Id), context.availableOwners[0].value);
        System.assertEquals(1, context.availableSalesTeams.size());
        System.assertEquals(2, context.availableSalesTeams[0].opportunityCount);
        System.assertEquals(context.availableSalesTeams[0].value, context.availableOwners[0].parentValue);
        System.assertEquals(1, subset.size());
        System.assertEquals(true, subset.containsKey(FIRST_OPPORTUNITY_ID));
        System.assertEquals('Analytics', rows[0].productNames);
        System.assertEquals('No Product', rows[1].productNames);
        System.assertEquals(new List<String>{ 'Analytics' }, rows[0].productLines);
        System.assertEquals(new List<String>{ 'No Product' }, rows[1].productLines);
    }

    private static OpportunityConversionDashboardController.StageEvent event(
        Id opportunityId,
        String stageName,
        Integer year,
        Integer month,
        Integer day
    ) {
        return new OpportunityConversionDashboardController.StageEvent(
            opportunityId,
            stageName,
            Datetime.newInstance(year, month, day, 12, 0, 0)
        );
    }

    private static OpportunityConversionDashboardController.StageEvent eventAt(
        Id opportunityId,
        String stageName,
        Integer year,
        Integer month,
        Integer day,
        Integer hour
    ) {
        return new OpportunityConversionDashboardController.StageEvent(
            opportunityId,
            stageName,
            Datetime.newInstance(year, month, day, hour, 0, 0)
        );
    }
}
