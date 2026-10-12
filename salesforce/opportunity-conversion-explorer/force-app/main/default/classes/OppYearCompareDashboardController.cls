public with sharing class OppYearCompareDashboardController {
    private static final Integer FIRST_YEAR = 2025;
    private static final Integer SECOND_YEAR = 2026;
    private static final Integer MAX_OPPORTUNITIES = 5000;
    private static final String CLOSED_WON = 'Closed Won';
    private static final String CLOSED_LOST = 'Closed Lost';
    private static final String NO_PRODUCT = 'No Product';
    private static final String NO_TEAM = '__NO_SALES_TEAM__';
    private static final List<String> STAGES = new List<String>{
        'Engagement',
        'Define Needs',
        'Solutioning',
        'Proposal',
        'Negotiation',
        'Verbal',
        'MSA/SOW Review',
        CLOSED_WON,
        CLOSED_LOST
    };

    public class DashboardDTO {
        @AuraEnabled public Date compareThroughDate;
        @AuraEnabled public String comparisonLabel;
        @AuraEnabled public Boolean isTruncated;
        @AuraEnabled public List<YearSummaryDTO> years;
        @AuraEnabled public List<StageComparisonDTO> stages;
        @AuraEnabled public List<ProductComparisonDTO> products;
        @AuraEnabled public List<ClosedWonRowDTO> closedWonOpportunities;
        @AuraEnabled public List<FilterOptionDTO> availableSalesTeams;
        @AuraEnabled public List<FilterOptionDTO> availableOwners;
        @AuraEnabled public List<FilterOptionDTO> availableProducts;
        @AuraEnabled public Integer noProductOpportunityCount;
    }

    public class YearSummaryDTO {
        @AuraEnabled public Integer year;
        @AuraEnabled public Date periodEnd;
        @AuraEnabled public Integer createdCount = 0;
        @AuraEnabled public Integer wonCount = 0;
        @AuraEnabled public Integer lostCount = 0;
        @AuraEnabled public Integer openCount = 0;
        @AuraEnabled public Integer rapidLossExcluded = 0;
        @AuraEnabled public Decimal winRate = 0;
        @AuraEnabled public Decimal averageFinalDealValue = 0;
        @AuraEnabled public Decimal averageDaysToClose = 0;
    }

    public class StageComparisonDTO {
        @AuraEnabled public String stageName;
        @AuraEnabled public Integer count2025 = 0;
        @AuraEnabled public Integer count2026 = 0;
        @AuraEnabled public Decimal rate2025 = 0;
        @AuraEnabled public Decimal rate2026 = 0;
    }

    public class ProductComparisonDTO {
        @AuraEnabled public String productName;
        @AuraEnabled public Integer created2025 = 0;
        @AuraEnabled public Integer created2026 = 0;
        @AuraEnabled public Decimal averageDealValue2025 = 0;
        @AuraEnabled public Decimal averageDealValue2026 = 0;
        @AuraEnabled public Decimal averageCloseDays2025 = 0;
        @AuraEnabled public Decimal averageCloseDays2026 = 0;
        @AuraEnabled public Integer closedCount2025 = 0;
        @AuraEnabled public Integer closedCount2026 = 0;
    }

    public class ClosedWonRowDTO {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public Integer cohortYear;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String salesTeam;
        @AuraEnabled public String productNames;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Decimal twelveMonthDealValue;
        @AuraEnabled public Date createdDate;
        @AuraEnabled public Date closedDate;
        @AuraEnabled public Integer daysToClose;
    }

    public class FilterOptionDTO {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public String parentValue;
        @AuraEnabled public Integer opportunityCount = 0;
    }

    @TestVisible
    public class StageEvent {
        public Id opportunityId;
        public String stageName;
        public Datetime occurredAt;

        public StageEvent(Id opportunityId, String stageName, Datetime occurredAt) {
            this.opportunityId = opportunityId;
            this.stageName = stageName;
            this.occurredAt = occurredAt;
        }
    }

    @TestVisible
    public class ProductLink {
        public Id productId;
        public String productName;

        public ProductLink(Id productId, String productName) {
            this.productId = productId;
            this.productName = productName;
        }
    }

    private class ProductAccumulator {
        String productName;
        Integer created2025 = 0;
        Integer created2026 = 0;
        Decimal dealValueSum2025 = 0;
        Decimal dealValueSum2026 = 0;
        Integer dealValueCount2025 = 0;
        Integer dealValueCount2026 = 0;
        Decimal closeDaysSum2025 = 0;
        Decimal closeDaysSum2026 = 0;
        Integer closeDaysCount2025 = 0;
        Integer closeDaysCount2026 = 0;
    }

    @AuraEnabled(cacheable=true)
    public static DashboardDTO getDashboardData(
        Integer yearA,
        Integer yearB,
        Date compareThroughDate,
        List<Id> selectedOwnerIds,
        List<Id> selectedProductIds
    ) {
        yearA = yearA == null ? FIRST_YEAR : yearA;
        yearB = yearB == null ? SECOND_YEAR : yearB;
        if (yearA == yearB || yearA < 2000 || yearB < 2000 || yearA > 2100 || yearB > 2100) {
            throw new AuraHandledException('Choose two different comparison years between 2000 and 2100.');
        }
        Date effectiveDate = compareThroughDate == null ? Date.today() : compareThroughDate;
        Date queryStartA = Date.newInstance(yearA, 1, 1);
        Date queryEndA = Date.newInstance(yearA + 1, 1, 1);
        Date queryStartB = Date.newInstance(yearB, 1, 1);
        Date queryEndB = Date.newInstance(yearB + 1, 1, 1);
        Datetime queryStartADatetime = startOfDay(queryStartA);
        Datetime queryEndADatetime = startOfDay(queryEndA);
        Datetime queryStartBDatetime = startOfDay(queryStartB);
        Datetime queryEndBDatetime = startOfDay(queryEndB);

        List<Opportunity> opportunities;
        try {
            opportunities = [
                SELECT Id, Name, OwnerId, Owner.Name, Owner.Sales_Team__c,
                    Amount, StageName, CreatedDate, CloseDate
                FROM Opportunity
                WHERE (
                    (CreatedDate >= :queryStartADatetime AND CreatedDate < :queryEndADatetime)
                    OR (CreatedDate >= :queryStartBDatetime AND CreatedDate < :queryEndBDatetime)
                )
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate, Id
                LIMIT :MAX_OPPORTUNITIES
            ];
        } catch (QueryException queryError) {
            throw new AuraHandledException(
                'You do not have access to one or more Opportunity fields required by this dashboard.'
            );
        }

        Set<Id> opportunityIds = new Map<Id, Opportunity>(opportunities).keySet();
        List<StageEvent> stageEvents = new List<StageEvent>();
        Map<Id, List<ProductLink>> productsByOpportunity = new Map<Id, List<ProductLink>>();

        if (!opportunityIds.isEmpty()) {
            for (OpportunityHistory historyRow : [
                SELECT OpportunityId, StageName, CreatedDate
                FROM OpportunityHistory
                WHERE OpportunityId IN :opportunityIds
                    AND StageName IN :STAGES
                ORDER BY OpportunityId, CreatedDate
            ]) {
                stageEvents.add(new StageEvent(
                    historyRow.OpportunityId,
                    historyRow.StageName,
                    historyRow.CreatedDate
                ));
            }

            try {
                for (OpportunityLineItem lineItem : [
                    SELECT OpportunityId, Product2Id, Product2.Name
                    FROM OpportunityLineItem
                    WHERE OpportunityId IN :opportunityIds
                    WITH SECURITY_ENFORCED
                ]) {
                    if (!productsByOpportunity.containsKey(lineItem.OpportunityId)) {
                        productsByOpportunity.put(lineItem.OpportunityId, new List<ProductLink>());
                    }
                    productsByOpportunity.get(lineItem.OpportunityId).add(
                        new ProductLink(lineItem.Product2Id, lineItem.Product2.Name)
                    );
                }
            } catch (QueryException queryError) {
                throw new AuraHandledException(
                    'You do not have access to Opportunity Products required by this dashboard.'
                );
            }
        }

        return buildDashboardForYears(
            opportunities,
            stageEvents,
            productsByOpportunity,
            effectiveDate,
            yearA,
            yearB,
            selectedOwnerIds == null ? null : new Set<Id>(selectedOwnerIds),
            selectedProductIds == null ? null : new Set<Id>(selectedProductIds),
            opportunities.size() == MAX_OPPORTUNITIES
        );
    }

    @TestVisible
    private static DashboardDTO buildDashboard(
        List<Opportunity> opportunities,
        List<StageEvent> stageEvents,
        Map<Id, List<ProductLink>> productsByOpportunity,
        Date compareThroughDate,
        Set<Id> selectedOwnerIds,
        Set<Id> selectedProductIds,
        Boolean isTruncated
    ) {
        return buildDashboardForYears(
            opportunities,
            stageEvents,
            productsByOpportunity,
            compareThroughDate,
            FIRST_YEAR,
            SECOND_YEAR,
            selectedOwnerIds,
            selectedProductIds,
            isTruncated
        );
    }

    @TestVisible
    private static DashboardDTO buildDashboardForYears(
        List<Opportunity> opportunities,
        List<StageEvent> stageEvents,
        Map<Id, List<ProductLink>> productsByOpportunity,
        Date compareThroughDate,
        Integer yearA,
        Integer yearB,
        Set<Id> selectedOwnerIds,
        Set<Id> selectedProductIds,
        Boolean isTruncated
    ) {
        Map<Id, List<StageEvent>> eventsByOpportunity = groupEvents(stageEvents);
        Date endA = matchingEndDate(yearA, compareThroughDate);
        Date endB = matchingEndDate(yearB, compareThroughDate);
        Map<Integer, YearSummaryDTO> yearByNumber = new Map<Integer, YearSummaryDTO>{
            yearA => newYearSummary(yearA, endA),
            yearB => newYearSummary(yearB, endB)
        };
        Map<String, StageComparisonDTO> stageByName = new Map<String, StageComparisonDTO>();
        Map<String, ProductAccumulator> productByName = new Map<String, ProductAccumulator>();
        List<ClosedWonRowDTO> closedWonRows = new List<ClosedWonRowDTO>();
        Map<String, FilterOptionDTO> teamOptions = new Map<String, FilterOptionDTO>();
        Map<Id, FilterOptionDTO> ownerOptions = new Map<Id, FilterOptionDTO>();
        Map<Id, FilterOptionDTO> productOptions = new Map<Id, FilterOptionDTO>();
        Integer noProductCount = 0;
        Map<Integer, Decimal> finalDealValueSum = new Map<Integer, Decimal>{ yearA => 0, yearB => 0 };
        Map<Integer, Integer> finalDealValueCount = new Map<Integer, Integer>{ yearA => 0, yearB => 0 };
        Map<Integer, Decimal> closeDaysSum = new Map<Integer, Decimal>{ yearA => 0, yearB => 0 };
        Map<Integer, Integer> closeDaysCount = new Map<Integer, Integer>{ yearA => 0, yearB => 0 };

        for (String stageName : STAGES) {
            StageComparisonDTO item = new StageComparisonDTO();
            item.stageName = stageName;
            stageByName.put(stageName, item);
        }

        for (Opportunity opportunity : opportunities) {
            Integer year = opportunity.CreatedDate.year();
            if (!yearByNumber.containsKey(year)) {
                continue;
            }
            Date periodEnd = year == yearA ? endA : endB;
            if (opportunity.CreatedDate.date() > periodEnd) {
                continue;
            }

            List<StageEvent> opportunityEvents = eventsByOpportunity.get(opportunity.Id);
            if (opportunityEvents == null) {
                opportunityEvents = new List<StageEvent>();
            }
            List<ProductLink> opportunityProducts = productsByOpportunity.get(opportunity.Id);
            addFilterOptions(opportunity, opportunityProducts, teamOptions, ownerOptions, productOptions);
            if (opportunityProducts == null || opportunityProducts.isEmpty()) {
                noProductCount++;
            }

            if (selectedOwnerIds != null && !selectedOwnerIds.contains(opportunity.OwnerId)) {
                continue;
            }
            if (!matchesProductFilter(opportunityProducts, selectedProductIds)) {
                continue;
            }

            YearSummaryDTO summary = yearByNumber.get(year);
            if (isSameDayEngagementToLost(opportunity, opportunityEvents)) {
                summary.rapidLossExcluded++;
                continue;
            }

            summary.createdCount++;
            if (opportunity.StageName == CLOSED_WON) {
                summary.wonCount++;
            } else if (opportunity.StageName == CLOSED_LOST) {
                summary.lostCount++;
            } else {
                summary.openCount++;
            }

            Set<String> reachedStages = new Set<String>{ opportunity.StageName };
            for (StageEvent event : opportunityEvents) {
                reachedStages.add(event.stageName);
            }
            for (String stageName : reachedStages) {
                StageComparisonDTO stageItem = stageByName.get(stageName);
                if (stageItem == null) {
                    continue;
                }
                if (year == yearA) {
                    stageItem.count2025++;
                } else {
                    stageItem.count2026++;
                }
            }

            Boolean isFinal = opportunity.StageName == CLOSED_WON || opportunity.StageName == CLOSED_LOST;
            Date closedDate = isFinal ? findClosedDate(opportunity, opportunityEvents) : null;
            Integer daysToClose = closedDate == null
                ? null
                : opportunity.CreatedDate.date().daysBetween(closedDate);
            Decimal twelveMonthValue = opportunity.Amount;
            if (isFinal && twelveMonthValue != null) {
                finalDealValueSum.put(year, finalDealValueSum.get(year) + twelveMonthValue);
                finalDealValueCount.put(year, finalDealValueCount.get(year) + 1);
            }
            if (isFinal && daysToClose != null) {
                closeDaysSum.put(year, closeDaysSum.get(year) + daysToClose);
                closeDaysCount.put(year, closeDaysCount.get(year) + 1);
            }

            List<String> productNames = uniqueProductNames(opportunityProducts);
            for (String productName : productNames) {
                if (!productByName.containsKey(productName)) {
                    ProductAccumulator accumulator = new ProductAccumulator();
                    accumulator.productName = productName;
                    productByName.put(productName, accumulator);
                }
                addProductMetric(
                    productByName.get(productName),
                    year,
                    isFinal,
                    twelveMonthValue,
                    daysToClose,
                    yearA
                );
            }

            if (opportunity.StageName == CLOSED_WON) {
                ClosedWonRowDTO row = new ClosedWonRowDTO();
                row.opportunityId = opportunity.Id;
                row.opportunityName = opportunity.Name;
                row.cohortYear = year;
                row.ownerName = opportunity.Owner == null ? null : opportunity.Owner.Name;
                row.salesTeam = opportunity.Owner == null ? null : opportunity.Owner.Sales_Team__c;
                row.productNames = String.join(productNames, ', ');
                row.amount = opportunity.Amount;
                row.twelveMonthDealValue = twelveMonthValue;
                row.createdDate = opportunity.CreatedDate.date();
                row.closedDate = closedDate;
                row.daysToClose = daysToClose;
                closedWonRows.add(row);
            }
        }

        for (Integer year : yearByNumber.keySet()) {
            YearSummaryDTO summary = yearByNumber.get(year);
            Integer decisions = summary.wonCount + summary.lostCount;
            summary.winRate = percent(summary.wonCount, decisions);
            summary.averageFinalDealValue = average(
                finalDealValueSum.get(year), finalDealValueCount.get(year)
            );
            summary.averageDaysToClose = average(closeDaysSum.get(year), closeDaysCount.get(year));
        }
        for (StageComparisonDTO stageItem : stageByName.values()) {
            stageItem.rate2025 = percent(stageItem.count2025, yearByNumber.get(yearA).createdCount);
            stageItem.rate2026 = percent(stageItem.count2026, yearByNumber.get(yearB).createdCount);
        }

        DashboardDTO result = new DashboardDTO();
        result.compareThroughDate = compareThroughDate;
        result.comparisonLabel = 'Jan 1–' + monthDayLabel(compareThroughDate) + ' matched YTD';
        result.isTruncated = isTruncated;
        result.years = new List<YearSummaryDTO>{
            yearByNumber.get(yearA), yearByNumber.get(yearB)
        };
        result.stages = orderedStages(stageByName);
        result.products = buildProductComparisons(productByName);
        result.closedWonOpportunities = closedWonRows;
        result.availableSalesTeams = sortedOptions(teamOptions.values());
        result.availableOwners = sortedOptions(ownerOptions.values());
        result.availableProducts = sortedOptions(productOptions.values());
        result.noProductOpportunityCount = noProductCount;
        return result;
    }

    private static Map<Id, List<StageEvent>> groupEvents(List<StageEvent> events) {
        Map<Id, List<StageEvent>> result = new Map<Id, List<StageEvent>>();
        for (StageEvent event : events) {
            if (!result.containsKey(event.opportunityId)) {
                result.put(event.opportunityId, new List<StageEvent>());
            }
            result.get(event.opportunityId).add(event);
        }
        return result;
    }

    private static void addFilterOptions(
        Opportunity opportunity,
        List<ProductLink> products,
        Map<String, FilterOptionDTO> teamOptions,
        Map<Id, FilterOptionDTO> ownerOptions,
        Map<Id, FilterOptionDTO> productOptions
    ) {
        String teamValue = opportunity.Owner == null || String.isBlank(opportunity.Owner.Sales_Team__c)
            ? NO_TEAM
            : opportunity.Owner.Sales_Team__c;
        if (!teamOptions.containsKey(teamValue)) {
            FilterOptionDTO team = new FilterOptionDTO();
            team.value = teamValue;
            team.label = teamValue == NO_TEAM ? 'No Sales Team' : teamValue;
            teamOptions.put(teamValue, team);
        }
        teamOptions.get(teamValue).opportunityCount++;

        if (!ownerOptions.containsKey(opportunity.OwnerId)) {
            FilterOptionDTO owner = new FilterOptionDTO();
            owner.value = String.valueOf(opportunity.OwnerId);
            owner.label = opportunity.Owner == null ? 'Unknown Owner' : opportunity.Owner.Name;
            owner.parentValue = teamValue;
            ownerOptions.put(opportunity.OwnerId, owner);
        }
        ownerOptions.get(opportunity.OwnerId).opportunityCount++;

        if (products != null) {
            Set<Id> countedProducts = new Set<Id>();
            for (ProductLink product : products) {
                if (countedProducts.contains(product.productId)) {
                    continue;
                }
                countedProducts.add(product.productId);
                if (!productOptions.containsKey(product.productId)) {
                    FilterOptionDTO option = new FilterOptionDTO();
                    option.value = String.valueOf(product.productId);
                    option.label = product.productName;
                    productOptions.put(product.productId, option);
                }
                productOptions.get(product.productId).opportunityCount++;
            }
        }
    }

    private static Boolean matchesProductFilter(
        List<ProductLink> products,
        Set<Id> selectedProductIds
    ) {
        if (products == null || products.isEmpty() || selectedProductIds == null) {
            return true;
        }
        for (ProductLink product : products) {
            if (selectedProductIds.contains(product.productId)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isSameDayEngagementToLost(
        Opportunity opportunity,
        List<StageEvent> events
    ) {
        if (opportunity.StageName != CLOSED_LOST) {
            return false;
        }
        List<Datetime> engagements = new List<Datetime>();
        List<Datetime> losses = new List<Datetime>();
        for (StageEvent event : events) {
            if (event.stageName == 'Engagement') {
                engagements.add(event.occurredAt);
            } else if (event.stageName == CLOSED_LOST) {
                losses.add(event.occurredAt);
            }
        }
        for (Datetime loss : losses) {
            for (Datetime engagement : engagements) {
                if (engagement <= loss && engagement.date() == loss.date()) {
                    return true;
                }
            }
        }
        return false;
    }

    private static Date findClosedDate(Opportunity opportunity, List<StageEvent> events) {
        Datetime firstClose;
        for (StageEvent event : events) {
            if ((event.stageName == CLOSED_WON || event.stageName == CLOSED_LOST) &&
                (firstClose == null || event.occurredAt < firstClose)) {
                firstClose = event.occurredAt;
            }
        }
        return firstClose == null ? opportunity.CloseDate : firstClose.date();
    }

    private static List<String> uniqueProductNames(List<ProductLink> products) {
        if (products == null || products.isEmpty()) {
            return new List<String>{ NO_PRODUCT };
        }
        Set<String> names = new Set<String>();
        for (ProductLink product : products) {
            names.add(product.productName);
        }
        List<String> result = new List<String>(names);
        result.sort();
        return result;
    }

    private static void addProductMetric(
        ProductAccumulator metric,
        Integer year,
        Boolean isFinal,
        Decimal dealValue,
        Integer daysToClose,
        Integer yearA
    ) {
        if (year == yearA) {
            metric.created2025++;
            if (isFinal && dealValue != null) {
                metric.dealValueSum2025 += dealValue;
                metric.dealValueCount2025++;
            }
            if (isFinal && daysToClose != null) {
                metric.closeDaysSum2025 += daysToClose;
                metric.closeDaysCount2025++;
            }
        } else {
            metric.created2026++;
            if (isFinal && dealValue != null) {
                metric.dealValueSum2026 += dealValue;
                metric.dealValueCount2026++;
            }
            if (isFinal && daysToClose != null) {
                metric.closeDaysSum2026 += daysToClose;
                metric.closeDaysCount2026++;
            }
        }
    }

    private static List<ProductComparisonDTO> buildProductComparisons(
        Map<String, ProductAccumulator> productByName
    ) {
        List<ProductComparisonDTO> result = new List<ProductComparisonDTO>();
        List<String> names = new List<String>(productByName.keySet());
        names.sort();
        for (String name : names) {
            ProductAccumulator source = productByName.get(name);
            ProductComparisonDTO row = new ProductComparisonDTO();
            row.productName = name;
            row.created2025 = source.created2025;
            row.created2026 = source.created2026;
            row.averageDealValue2025 = average(source.dealValueSum2025, source.dealValueCount2025);
            row.averageDealValue2026 = average(source.dealValueSum2026, source.dealValueCount2026);
            row.averageCloseDays2025 = average(source.closeDaysSum2025, source.closeDaysCount2025);
            row.averageCloseDays2026 = average(source.closeDaysSum2026, source.closeDaysCount2026);
            row.closedCount2025 = source.closeDaysCount2025;
            row.closedCount2026 = source.closeDaysCount2026;
            result.add(row);
        }
        return result;
    }

    private static List<StageComparisonDTO> orderedStages(
        Map<String, StageComparisonDTO> stageByName
    ) {
        List<StageComparisonDTO> result = new List<StageComparisonDTO>();
        for (String stageName : STAGES) {
            result.add(stageByName.get(stageName));
        }
        return result;
    }

    private static List<FilterOptionDTO> sortedOptions(List<FilterOptionDTO> options) {
        options.sort(new FilterOptionComparator());
        return options;
    }

    private static YearSummaryDTO newYearSummary(Integer year, Date endDate) {
        YearSummaryDTO result = new YearSummaryDTO();
        result.year = year;
        result.periodEnd = endDate;
        return result;
    }

    private static Date matchingEndDate(Integer year, Date compareThroughDate) {
        Integer month = compareThroughDate.month();
        Integer day = compareThroughDate.day();
        while (day > 28) {
            try {
                return Date.newInstance(year, month, day);
            } catch (Exception invalidDate) {
                day--;
            }
        }
        return Date.newInstance(year, month, day);
    }

    private static Decimal percent(Integer numerator, Integer denominator) {
        return denominator == null || denominator == 0
            ? 0
            : (Decimal.valueOf(String.valueOf(numerator)) * 100 / denominator).setScale(1);
    }

    private static Decimal average(Decimal total, Integer count) {
        return count == null || count == 0 || total == null
            ? 0
            : (total / count).setScale(1);
    }

    private static String monthDayLabel(Date value) {
        return DateTime.newInstance(value, Time.newInstance(0, 0, 0, 0)).format('MMM d');
    }

    private static Datetime startOfDay(Date value) {
        return Datetime.newInstance(value, Time.newInstance(0, 0, 0, 0));
    }

    private class FilterOptionComparator implements Comparator<FilterOptionDTO> {
        public Integer compare(FilterOptionDTO first, FilterOptionDTO second) {
            return first.label.toLowerCase().compareTo(second.label.toLowerCase());
        }
    }
}
