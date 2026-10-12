public with sharing class OpportunityConversionDashboardController {
    private static final String ENGAGEMENT_STAGE = 'Engagement';
    private static final String CLOSED_WON_STAGE = 'Closed Won';
    private static final String CLOSED_LOST_STAGE = 'Closed Lost';
    private static final String NO_SALES_TEAM_FILTER = '__NO_SALES_TEAM__';
    private static final Set<String> SUPPORTED_SOURCE_STAGES = new Set<String>{
        ENGAGEMENT_STAGE,
        'Define Needs',
        'Solutioning',
        'Proposal',
        'Negotiation',
        'Verbal',
        'MSA/SOW Review'
    };
    private static final Integer MAX_CUSTOM_RANGE_DAYS = 1826;

    public class DashboardDTO {
        @AuraEnabled public Datetime generatedAt;
        @AuraEnabled public List<PeriodDTO> periods;
    }

    public class PeriodDTO {
        @AuraEnabled public String key;
        @AuraEnabled public String title;
        @AuraEnabled public String sourceStage;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Integer totalEntered;
        @AuraEnabled public Integer totalConverted;
        @AuraEnabled public Integer totalLost;
        @AuraEnabled public Integer totalOpen;
        @AuraEnabled public Integer totalClosed;
        @AuraEnabled public Integer rapidLossExcluded;
        @AuraEnabled public Decimal conversionRate;
        @AuraEnabled public Decimal closedWinRate;
        @AuraEnabled public List<ConvertedOpportunityDTO> convertedOpportunities;
        @AuraEnabled public List<ConvertedOpportunityDTO> opportunities;
        @AuraEnabled public List<ProductOptionDTO> availableProducts;
        @AuraEnabled public List<FilterOptionDTO> availableSalesTeams;
        @AuraEnabled public List<FilterOptionDTO> availableOwners;
        @AuraEnabled public Boolean hasNoProduct;
        @AuraEnabled public Integer noProductOpportunityCount;
    }

    public class ProductOptionDTO {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public Integer opportunityCount;
    }

    public class FilterOptionDTO {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public String parentValue;
        @AuraEnabled public Integer opportunityCount;
    }

    public class ConvertedOpportunityDTO {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String salesTeam;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String currentStage;
        @AuraEnabled public String productNames;
        @AuraEnabled public List<String> productLines;
        @AuraEnabled public Datetime createdAt;
        @AuraEnabled public Datetime enteredSourceStageAt;
        @AuraEnabled public Datetime enteredClosedWonAt;
        @AuraEnabled public Datetime enteredClosedLostAt;
        @AuraEnabled public Datetime outcomeAt;
        @AuraEnabled public String outcome;
        @AuraEnabled public Integer daysToConvert;
        @AuraEnabled public Integer daysToOutcome;
        @AuraEnabled public Integer daysToClose;
    }

    @TestVisible
    private class StageEvent {
        Id opportunityId;
        String stageName;
        Datetime occurredAt;

        public StageEvent(Id opportunityId, String stageName, Datetime occurredAt) {
            this.opportunityId = opportunityId;
            this.stageName = stageName;
            this.occurredAt = occurredAt;
        }
    }

    private class ProductContext {
        Map<Id, Set<Id>> productIdsByOpportunity = new Map<Id, Set<Id>>();
        Map<Id, String> productNameById = new Map<Id, String>();
        Map<Id, Integer> opportunityCountByProduct = new Map<Id, Integer>();
        Map<Id, String> productNamesByOpportunity = new Map<Id, String>();
        Map<Id, List<String>> productNameListByOpportunity = new Map<Id, List<String>>();
        List<ProductOptionDTO> availableProducts = new List<ProductOptionDTO>();
        Set<Id> opportunitiesWithoutProducts = new Set<Id>();
    }

    @TestVisible
    private class DimensionContext {
        @TestVisible Map<Id, Id> ownerIdByOpportunity = new Map<Id, Id>();
        @TestVisible List<FilterOptionDTO> availableSalesTeams = new List<FilterOptionDTO>();
        @TestVisible List<FilterOptionDTO> availableOwners = new List<FilterOptionDTO>();
    }

    @AuraEnabled(cacheable=true)
    public static DashboardDTO getDashboardData() {
        Date queryStartDate = Date.newInstance(2025, 1, 1);
        Date queryEndExclusive = Date.newInstance(2026, 9, 1);
        Datetime queryStart = startOfDay(queryStartDate);
        Datetime queryEnd = startOfDay(queryEndExclusive);
        Set<String> relevantStages = new Set<String>{
            'Proposal',
            'Verbal',
            CLOSED_WON_STAGE
        };

        List<StageEvent> events = new List<StageEvent>();
        Set<Id> opportunityIds = new Set<Id>();

        for (OpportunityHistory historyRow : [
            SELECT OpportunityId, StageName, CreatedDate
            FROM OpportunityHistory
            WHERE StageName IN :relevantStages
                AND CreatedDate >= :queryStart
                AND CreatedDate < :queryEnd
            ORDER BY CreatedDate ASC
        ]) {
            events.add(new StageEvent(
                historyRow.OpportunityId,
                historyRow.StageName,
                historyRow.CreatedDate
            ));
            opportunityIds.add(historyRow.OpportunityId);
        }

        Map<Id, Opportunity> opportunitiesById = new Map<Id, Opportunity>();
        if (!opportunityIds.isEmpty()) {
            try {
                opportunitiesById = new Map<Id, Opportunity>([
                    SELECT Id, Name, Owner.Name, Owner.Sales_Team__c, Amount, StageName, CreatedDate
                    FROM Opportunity
                    WHERE Id IN :opportunityIds
                    WITH SECURITY_ENFORCED
                ]);
            } catch (QueryException queryError) {
                throw new AuraHandledException(
                    'You do not have access to one or more Opportunity fields required by this dashboard.'
                );
            }
        }

        DashboardDTO dashboard = new DashboardDTO();
        dashboard.generatedAt = System.now();
        dashboard.periods = new List<PeriodDTO>{
            calculatePeriod(
                'proposal-2025',
                '2025 Proposal Conversion',
                'Proposal',
                Date.newInstance(2025, 1, 1),
                Date.newInstance(2025, 12, 31),
                events,
                opportunitiesById
            ),
            calculatePeriod(
                'verbal-2026',
                'Jan–Aug 2026 Verbal Conversion',
                'Verbal',
                Date.newInstance(2026, 1, 1),
                Date.newInstance(2026, 8, 31),
                events,
                opportunitiesById
            )
        };
        return dashboard;
    }

    @AuraEnabled(cacheable=true)
    public static PeriodDTO getCustomConversionData(
        Date startDate,
        Date endDate,
        String sourceStage,
        List<Id> selectedProductIds,
        List<Id> selectedOwnerIds
    ) {
        validateCustomFilters(startDate, endDate, sourceStage);

        Datetime queryStart = startOfDay(startDate);
        Datetime queryEnd = startOfDay(endDate.addDays(1));
        Set<String> relevantStages = new Set<String>{
            ENGAGEMENT_STAGE,
            sourceStage,
            CLOSED_WON_STAGE,
            CLOSED_LOST_STAGE
        };
        List<StageEvent> events = new List<StageEvent>();
        Set<Id> sourceOpportunityIds = new Set<Id>();

        for (OpportunityHistory historyRow : [
            SELECT OpportunityId, StageName, CreatedDate
            FROM OpportunityHistory
            WHERE StageName IN :relevantStages
                AND CreatedDate >= :queryStart
                AND CreatedDate < :queryEnd
            ORDER BY CreatedDate ASC
        ]) {
            events.add(new StageEvent(
                historyRow.OpportunityId,
                historyRow.StageName,
                historyRow.CreatedDate
            ));
            if (historyRow.StageName == sourceStage) {
                sourceOpportunityIds.add(historyRow.OpportunityId);
            }
        }

        Map<Id, Opportunity> cohortOpportunities = loadOpportunities(sourceOpportunityIds);
        DimensionContext dimensionContext = buildDimensionContext(cohortOpportunities);
        ProductContext productContext = loadProductContext(sourceOpportunityIds);
        Set<Id> includedOpportunityIds = resolveOwnerFilteredOpportunityIds(
            sourceOpportunityIds,
            dimensionContext.ownerIdByOpportunity,
            selectedOwnerIds
        );
        includedOpportunityIds.retainAll(resolveProductFilteredOpportunityIds(
            sourceOpportunityIds,
            productContext.productIdsByOpportunity,
            selectedProductIds
        ));
        List<StageEvent> filteredEvents = new List<StageEvent>();
        for (StageEvent event : events) {
            if (includedOpportunityIds.contains(event.opportunityId)) {
                filteredEvents.add(event);
            }
        }

        PeriodDTO result = calculatePeriod(
            'custom-conversion',
            sourceStage + ' to Closed Won Conversion',
            sourceStage,
            startDate,
            endDate,
            filteredEvents,
            subsetOpportunities(cohortOpportunities, includedOpportunityIds),
            true
        );
        result.availableProducts = productContext.availableProducts;
        result.availableSalesTeams = dimensionContext.availableSalesTeams;
        result.availableOwners = dimensionContext.availableOwners;
        result.hasNoProduct = !productContext.opportunitiesWithoutProducts.isEmpty();
        result.noProductOpportunityCount = productContext.opportunitiesWithoutProducts.size();
        addProductNames(
            result.opportunities,
            productContext.productNamesByOpportunity,
            productContext.productNameListByOpportunity
        );
        return result;
    }

    @TestVisible
    private static DimensionContext buildDimensionContext(
        Map<Id, Opportunity> opportunitiesById
    ) {
        DimensionContext context = new DimensionContext();
        Map<String, Integer> countBySalesTeam = new Map<String, Integer>();
        Map<Id, Integer> countByOwner = new Map<Id, Integer>();
        Map<Id, String> ownerNameById = new Map<Id, String>();
        Map<Id, String> salesTeamByOwnerId = new Map<Id, String>();

        for (Opportunity opportunity : opportunitiesById.values()) {
            Id ownerId = opportunity.OwnerId;
            String salesTeam = opportunity.Owner == null
                ? null
                : opportunity.Owner.Sales_Team__c;
            String salesTeamValue = String.isBlank(salesTeam)
                ? NO_SALES_TEAM_FILTER
                : salesTeam;

            context.ownerIdByOpportunity.put(opportunity.Id, ownerId);
            countBySalesTeam.put(
                salesTeamValue,
                (countBySalesTeam.containsKey(salesTeamValue) ? countBySalesTeam.get(salesTeamValue) : 0) + 1
            );
            countByOwner.put(
                ownerId,
                (countByOwner.containsKey(ownerId) ? countByOwner.get(ownerId) : 0) + 1
            );
            ownerNameById.put(
                ownerId,
                opportunity.Owner == null ? 'Unknown Owner' : opportunity.Owner.Name
            );
            salesTeamByOwnerId.put(ownerId, salesTeamValue);
        }

        for (String salesTeamValue : countBySalesTeam.keySet()) {
            FilterOptionDTO option = new FilterOptionDTO();
            option.value = salesTeamValue;
            option.label = salesTeamValue == NO_SALES_TEAM_FILTER
                ? 'No Sales Team'
                : salesTeamValue;
            option.opportunityCount = countBySalesTeam.get(salesTeamValue);
            context.availableSalesTeams.add(option);
        }
        for (Id ownerId : countByOwner.keySet()) {
            FilterOptionDTO option = new FilterOptionDTO();
            option.value = String.valueOf(ownerId);
            option.label = ownerNameById.get(ownerId);
            option.parentValue = salesTeamByOwnerId.get(ownerId);
            option.opportunityCount = countByOwner.get(ownerId);
            context.availableOwners.add(option);
        }
        context.availableSalesTeams.sort(new FilterOptionComparator());
        context.availableOwners.sort(new FilterOptionComparator());
        return context;
    }

    @TestVisible
    private static Set<Id> resolveOwnerFilteredOpportunityIds(
        Set<Id> opportunityIds,
        Map<Id, Id> ownerIdByOpportunity,
        List<Id> selectedOwnerIds
    ) {
        Set<Id> ownerIds = selectedOwnerIds == null
            ? null
            : new Set<Id>(selectedOwnerIds);
        Set<Id> includedOpportunityIds = new Set<Id>();

        for (Id opportunityId : opportunityIds) {
            if (ownerIds != null && !ownerIds.contains(ownerIdByOpportunity.get(opportunityId))) {
                continue;
            }
            includedOpportunityIds.add(opportunityId);
        }
        return includedOpportunityIds;
    }

    @TestVisible
    private static Map<Id, Opportunity> subsetOpportunities(
        Map<Id, Opportunity> opportunitiesById,
        Set<Id> includedOpportunityIds
    ) {
        Map<Id, Opportunity> result = new Map<Id, Opportunity>();
        for (Id opportunityId : includedOpportunityIds) {
            if (opportunitiesById.containsKey(opportunityId)) {
                result.put(opportunityId, opportunitiesById.get(opportunityId));
            }
        }
        return result;
    }

    private static void validateCustomFilters(
        Date startDate,
        Date endDate,
        String sourceStage
    ) {
        if (startDate == null || endDate == null || String.isBlank(sourceStage)) {
            throw new AuraHandledException('Start date, end date, and starting stage are required.');
        }
        if (startDate > endDate) {
            throw new AuraHandledException('Start date cannot be after end date.');
        }
        if (startDate.daysBetween(endDate) > MAX_CUSTOM_RANGE_DAYS) {
            throw new AuraHandledException('Select a date range of five years or less.');
        }
        if (!SUPPORTED_SOURCE_STAGES.contains(sourceStage)) {
            throw new AuraHandledException('Select a supported Opportunity starting stage.');
        }
    }

    private static ProductContext loadProductContext(Set<Id> opportunityIds) {
        ProductContext context = new ProductContext();
        if (opportunityIds.isEmpty()) {
            return context;
        }

        List<OpportunityLineItem> lineItems;
        try {
            lineItems = [
                SELECT OpportunityId, Product2Id, Product2.Name
                FROM OpportunityLineItem
                WHERE OpportunityId IN :opportunityIds
                WITH SECURITY_ENFORCED
            ];
        } catch (QueryException queryError) {
            throw new AuraHandledException(
                'You do not have access to Opportunity Products required by this dashboard.'
            );
        }

        for (OpportunityLineItem lineItem : lineItems) {
            if (!context.productIdsByOpportunity.containsKey(lineItem.OpportunityId)) {
                context.productIdsByOpportunity.put(lineItem.OpportunityId, new Set<Id>());
            }
            context.productIdsByOpportunity.get(lineItem.OpportunityId).add(lineItem.Product2Id);
            context.productNameById.put(lineItem.Product2Id, lineItem.Product2.Name);
        }

        for (Id opportunityId : opportunityIds) {
            Set<Id> productIds = context.productIdsByOpportunity.get(opportunityId);
            if (productIds == null || productIds.isEmpty()) {
                context.opportunitiesWithoutProducts.add(opportunityId);
                continue;
            }

            List<String> productNames = new List<String>();
            for (Id productId : productIds) {
                productNames.add(context.productNameById.get(productId));
                Integer currentCount = context.opportunityCountByProduct.get(productId);
                context.opportunityCountByProduct.put(
                    productId,
                    currentCount == null ? 1 : currentCount + 1
                );
            }
            productNames.sort();
            context.productNamesByOpportunity.put(opportunityId, String.join(productNames, ', '));
            context.productNameListByOpportunity.put(opportunityId, productNames);
        }

        for (Id productId : context.productNameById.keySet()) {
            ProductOptionDTO option = new ProductOptionDTO();
            option.productId = productId;
            option.productName = context.productNameById.get(productId);
            option.opportunityCount = context.opportunityCountByProduct.get(productId);
            context.availableProducts.add(option);
        }
        context.availableProducts.sort(new ProductOptionComparator());
        return context;
    }

    @TestVisible
    private static Set<Id> resolveProductFilteredOpportunityIds(
        Set<Id> opportunityIds,
        Map<Id, Set<Id>> productIdsByOpportunity,
        List<Id> selectedProductIds
    ) {
        if (selectedProductIds == null) {
            return opportunityIds.clone();
        }

        Set<Id> selectedProducts = new Set<Id>(selectedProductIds);
        Set<Id> includedOpportunityIds = new Set<Id>();
        for (Id opportunityId : opportunityIds) {
            Set<Id> opportunityProductIds = productIdsByOpportunity.get(opportunityId);
            if (opportunityProductIds == null || opportunityProductIds.isEmpty()) {
                includedOpportunityIds.add(opportunityId);
                continue;
            }

            for (Id productId : opportunityProductIds) {
                if (selectedProducts.contains(productId)) {
                    includedOpportunityIds.add(opportunityId);
                    break;
                }
            }
        }
        return includedOpportunityIds;
    }

    @TestVisible
    private static void addProductNames(
        List<ConvertedOpportunityDTO> rows,
        Map<Id, String> productNamesByOpportunity,
        Map<Id, List<String>> productNameListByOpportunity
    ) {
        for (ConvertedOpportunityDTO row : rows) {
            String productNames = productNamesByOpportunity.get(row.opportunityId);
            row.productNames = String.isBlank(productNames) ? 'No Product' : productNames;
            List<String> productLines = productNameListByOpportunity == null
                ? null
                : productNameListByOpportunity.get(row.opportunityId);
            row.productLines = productLines == null || productLines.isEmpty()
                ? new List<String>{ 'No Product' }
                : new List<String>(productLines);
        }
    }

    private static Map<Id, Opportunity> loadOpportunities(Set<Id> opportunityIds) {
        if (opportunityIds.isEmpty()) {
            return new Map<Id, Opportunity>();
        }

        try {
            return new Map<Id, Opportunity>([
                SELECT Id, Name, OwnerId, Owner.Name, Owner.Sales_Team__c,
                    Amount, StageName, CreatedDate
                FROM Opportunity
                WHERE Id IN :opportunityIds
                WITH SECURITY_ENFORCED
            ]);
        } catch (QueryException queryError) {
            throw new AuraHandledException(
                'You do not have access to one or more Opportunity fields required by this dashboard.'
            );
        }
    }

    @TestVisible
    private static PeriodDTO calculatePeriod(
        String key,
        String title,
        String sourceStage,
        Date startDate,
        Date endDate,
        List<StageEvent> events,
        Map<Id, Opportunity> opportunitiesById
    ) {
        return calculatePeriod(
            key,
            title,
            sourceStage,
            startDate,
            endDate,
            events,
            opportunitiesById,
            false
        );
    }

    @TestVisible
    private static PeriodDTO calculatePeriod(
        String key,
        String title,
        String sourceStage,
        Date startDate,
        Date endDate,
        List<StageEvent> events,
        Map<Id, Opportunity> opportunitiesById,
        Boolean includeAllOutcomes
    ) {
        Datetime periodStart = startOfDay(startDate);
        Datetime periodEndExclusive = startOfDay(endDate.addDays(1));
        Map<Id, Datetime> firstSourceEntryByOpportunity = new Map<Id, Datetime>();
        Map<Id, List<Datetime>> engagementEntriesByOpportunity = new Map<Id, List<Datetime>>();
        Map<Id, List<Datetime>> wonEntriesByOpportunity = new Map<Id, List<Datetime>>();
        Map<Id, List<Datetime>> lostEntriesByOpportunity = new Map<Id, List<Datetime>>();

        for (StageEvent event : events) {
            if (event == null || event.opportunityId == null || event.occurredAt == null) {
                continue;
            }
            if (event.occurredAt < periodStart || event.occurredAt >= periodEndExclusive) {
                continue;
            }

            if (event.stageName == ENGAGEMENT_STAGE) {
                if (!engagementEntriesByOpportunity.containsKey(event.opportunityId)) {
                    engagementEntriesByOpportunity.put(event.opportunityId, new List<Datetime>());
                }
                engagementEntriesByOpportunity.get(event.opportunityId).add(event.occurredAt);
            }

            if (event.stageName == sourceStage) {
                Datetime existingEntry = firstSourceEntryByOpportunity.get(event.opportunityId);
                if (existingEntry == null || event.occurredAt < existingEntry) {
                    firstSourceEntryByOpportunity.put(event.opportunityId, event.occurredAt);
                }
            } else if (event.stageName == CLOSED_WON_STAGE) {
                if (!wonEntriesByOpportunity.containsKey(event.opportunityId)) {
                    wonEntriesByOpportunity.put(event.opportunityId, new List<Datetime>());
                }
                wonEntriesByOpportunity.get(event.opportunityId).add(event.occurredAt);
            } else if (event.stageName == CLOSED_LOST_STAGE) {
                if (!lostEntriesByOpportunity.containsKey(event.opportunityId)) {
                    lostEntriesByOpportunity.put(event.opportunityId, new List<Datetime>());
                }
                lostEntriesByOpportunity.get(event.opportunityId).add(event.occurredAt);
            }
        }

        List<ConvertedOpportunityDTO> convertedRows = new List<ConvertedOpportunityDTO>();
        List<ConvertedOpportunityDTO> outcomeRows = new List<ConvertedOpportunityDTO>();
        Integer totalLost = 0;
        Integer totalOpen = 0;
        Integer rapidLossExcluded = 0;
        for (Id opportunityId : firstSourceEntryByOpportunity.keySet()) {
            Datetime sourceEntry = firstSourceEntryByOpportunity.get(opportunityId);
            Datetime firstWonAfterSource;
            Datetime firstLostAfterSource;

            if (wonEntriesByOpportunity.containsKey(opportunityId)) {
                for (Datetime wonEntry : wonEntriesByOpportunity.get(opportunityId)) {
                    if (wonEntry >= sourceEntry &&
                        (firstWonAfterSource == null || wonEntry < firstWonAfterSource)) {
                        firstWonAfterSource = wonEntry;
                    }
                }
            }

            if (firstWonAfterSource == null && lostEntriesByOpportunity.containsKey(opportunityId)) {
                for (Datetime lostEntry : lostEntriesByOpportunity.get(opportunityId)) {
                    if (lostEntry >= sourceEntry &&
                        (firstLostAfterSource == null || lostEntry < firstLostAfterSource)) {
                        firstLostAfterSource = lostEntry;
                    }
                }
            }

            Boolean isSameDayRapidLoss = false;
            if (firstLostAfterSource != null && engagementEntriesByOpportunity.containsKey(opportunityId)) {
                for (Datetime engagementEntry : engagementEntriesByOpportunity.get(opportunityId)) {
                    if (engagementEntry <= firstLostAfterSource &&
                        engagementEntry.date() == firstLostAfterSource.date()) {
                        isSameDayRapidLoss = true;
                        break;
                    }
                }
            }
            if (isSameDayRapidLoss) {
                rapidLossExcluded++;
                continue;
            }

            if (!includeAllOutcomes && firstWonAfterSource == null) {
                continue;
            }

            Opportunity opportunity = opportunitiesById.get(opportunityId);
            ConvertedOpportunityDTO row = new ConvertedOpportunityDTO();
            row.opportunityId = opportunityId;
            row.opportunityName = opportunity == null ? 'Opportunity' : opportunity.Name;
            row.ownerName = opportunity == null || opportunity.Owner == null
                ? null
                : opportunity.Owner.Name;
            row.salesTeam = opportunity == null || opportunity.Owner == null
                ? null
                : opportunity.Owner.Sales_Team__c;
            row.amount = opportunity == null ? null : opportunity.Amount;
            row.currentStage = opportunity == null ? null : opportunity.StageName;
            row.createdAt = opportunity == null ? null : opportunity.CreatedDate;
            row.enteredSourceStageAt = sourceEntry;
            row.enteredClosedWonAt = firstWonAfterSource;
            row.enteredClosedLostAt = firstLostAfterSource;

            if (firstWonAfterSource != null) {
                row.outcome = 'Won';
                row.outcomeAt = firstWonAfterSource;
                row.daysToConvert = sourceEntry.date().daysBetween(firstWonAfterSource.date());
                row.daysToOutcome = row.daysToConvert;
                convertedRows.add(row);
            } else if (firstLostAfterSource != null) {
                row.outcome = 'Lost';
                row.outcomeAt = firstLostAfterSource;
                row.daysToOutcome = sourceEntry.date().daysBetween(firstLostAfterSource.date());
                totalLost++;
            } else {
                row.outcome = 'Open';
                totalOpen++;
            }

            if (row.outcomeAt != null && row.createdAt != null) {
                row.daysToClose = row.createdAt.date().daysBetween(row.outcomeAt.date());
            }

            if (includeAllOutcomes) {
                outcomeRows.add(row);
            }
        }

        convertedRows.sort(new ConvertedOpportunityComparator());
        if (includeAllOutcomes) {
            outcomeRows.sort(new OpportunityOutcomeComparator());
        }

        PeriodDTO period = new PeriodDTO();
        period.key = key;
        period.title = title;
        period.sourceStage = sourceStage;
        period.startDate = startDate;
        period.endDate = endDate;
        period.rapidLossExcluded = rapidLossExcluded;
        period.totalEntered = firstSourceEntryByOpportunity.size() - rapidLossExcluded;
        period.totalConverted = convertedRows.size();
        period.totalLost = totalLost;
        period.totalOpen = totalOpen;
        period.totalClosed = period.totalConverted + period.totalLost;
        period.conversionRate = period.totalEntered == 0
            ? 0
            : (Decimal.valueOf(String.valueOf(period.totalConverted)) * 100 / period.totalEntered).setScale(1);
        period.closedWinRate = period.totalClosed == 0
            ? 0
            : (Decimal.valueOf(String.valueOf(period.totalConverted)) * 100 / period.totalClosed).setScale(1);
        period.convertedOpportunities = convertedRows;
        period.opportunities = outcomeRows;
        return period;
    }

    private static Datetime startOfDay(Date value) {
        return Datetime.newInstance(value, Time.newInstance(0, 0, 0, 0));
    }

    private class ConvertedOpportunityComparator implements Comparator<ConvertedOpportunityDTO> {
        public Integer compare(ConvertedOpportunityDTO first, ConvertedOpportunityDTO second) {
            if (first.enteredClosedWonAt == second.enteredClosedWonAt) {
                return first.opportunityName.toLowerCase().compareTo(
                    second.opportunityName.toLowerCase()
                );
            }
            return first.enteredClosedWonAt < second.enteredClosedWonAt ? -1 : 1;
        }
    }

    private class OpportunityOutcomeComparator implements Comparator<ConvertedOpportunityDTO> {
        public Integer compare(ConvertedOpportunityDTO first, ConvertedOpportunityDTO second) {
            if (first.enteredSourceStageAt == second.enteredSourceStageAt) {
                return first.opportunityName.toLowerCase().compareTo(
                    second.opportunityName.toLowerCase()
                );
            }
            return first.enteredSourceStageAt < second.enteredSourceStageAt ? -1 : 1;
        }
    }

    private class ProductOptionComparator implements Comparator<ProductOptionDTO> {
        public Integer compare(ProductOptionDTO first, ProductOptionDTO second) {
            return first.productName.toLowerCase().compareTo(second.productName.toLowerCase());
        }
    }

    private class FilterOptionComparator implements Comparator<FilterOptionDTO> {
        public Integer compare(FilterOptionDTO first, FilterOptionDTO second) {
            return first.label.toLowerCase().compareTo(second.label.toLowerCase());
        }
    }
}
