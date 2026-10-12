# Opportunity Analytics Dashboards

This Salesforce DX package adds seven year-comparison widgets inside the existing **Opportunity Conversion Explorer**. The Explorer defaults Year A and Year B from its selected date range; both years remain selectable, and comparisons use matching year-to-date periods through the selected end date.

## Year comparison widgets

The embedded comparison dashboard includes:

- Conversion rate by stage for each selected created-Opportunity cohort
- Opportunities created in each matched-YTD period
- Closed-decision win rate: `Closed Won ÷ (Closed Won + Closed Lost)`
- Product breakdown for all created Opportunities, including **No Product**
- Average standard `Opportunity.Amount` for final-stage Opportunities by product line
- Closed Won Opportunity details for both selected years
- Average time to close by product line, measured from Opportunity creation to its first Won/Lost history entry

Final stage means **Closed Won or Closed Lost**. If no close-stage history exists, the average-time calculation falls back to `Opportunity.CloseDate`. Opportunities with Engagement followed by Closed Lost on the same calendar day are excluded. Results are capped at 5,000 Opportunities, and the component displays a warning when the cap is reached.

The comparison widgets use the Explorer's applied Owner and Product filters. Product selection is independent, and Opportunities without products are always included.

## Existing conversion explorer

This Salesforce LWC reports two fixed conversion periods from `OpportunityHistory`:

- **2025:** Entered `Proposal` and subsequently entered `Closed Won` between January 1 and December 31, 2025.
- **January–August 2026:** Entered `Verbal` and subsequently entered `Closed Won` between January 1 and August 31, 2026.

Each Opportunity is counted once per period. A conversion is counted only when the Closed Won history entry occurs on or after the relevant starting-stage entry and both events are inside the same period.

The converted-Opportunity tables are collapsed by default. Each reporting period has its own Expand/Collapse control.

## Included components

- `OpportunityConversionDashboardController.cls`
- `OpportunityConversionDashboardTest.cls`
- `opportunityConversionDashboard` LWC bundle
- `opportunityConversionExplorer` configurable LWC bundle
- `OppYearCompareDashboardController.cls`
- `OppYearCompareDashboardTest.cls`
- `opportunityYearComparisonDashboard` consolidated LWC bundle
- `manifest/explorer-package.xml`

## Configurable explorer

**Opportunity Conversion Explorer** is a separate component that lets the user select a start date, end date, and starting Opportunity stage. The destination stage remains `Closed Won`. It defaults to the current calendar year through today and its result table is collapsed by default.

The explorer includes independent **Won**, **Lost**, and **Open** outcome filters. Won and Lost are selected by default so the chart initially shows closed decisions; Open is optional, and users can select any combination of the three filters.

The Explorer includes **Year A** and **Year B** controls followed by the seven comparison widgets listed above. The defaults follow the selected date range. Comparison close-time uses final-stage Opportunities in those created-year cohorts and includes productless Opportunities under **No Product**.

The explorer has a persistent, hideable left sidebar with three independently collapsible checkbox groups:

- **Sales Team**, populated from `Opportunity.Owner.Sales_Team__c`
- **Opportunity Owner**, populated from the Owners represented in the selected cohort
- **Products**, populated from standard Opportunity Products (`OpportunityLineItem → Product2`)

All available choices are selected by default. Sales Team is a convenience control for the Owner list: unchecking a team immediately unchecks its Owners, while manually re-checking an Owner overrides that team selection. The server-side cohort is determined by the checked Owners. Products remain independent and use OR logic within the Products group, so a product-bearing Opportunity is included when it contains any selected product. Opportunities containing multiple matching products are still counted once. Blank Sales Team values appear as **No Sales Team**. Opportunities without line items are always included in the cohort, regardless of the selected Product checkboxes, and appear as **No Product** in the drill-down table.

Its primary percentage is the closed-decision win rate: `Closed Won ÷ (Closed Won + Closed Lost)`. Open Opportunities are shown separately and never reduce this win rate. The streamlined dashboard places the interactive donut beside a win-rate summary and keeps the detail table collapsed by default. Clicking a slice expands the table with that outcome's Opportunities. Percentage labels appear inside sufficiently large slices and beside every legend item; these chart percentages use the total of the currently included outcome categories.

To prevent rapid stage-clicking from skewing the win/loss result, an Opportunity is excluded from both the entered cohort and Closed Lost count when an **Engagement** history entry and a subsequent **Closed Lost** history entry occur on the same calendar day. Intermediate stage entries on that day do not change this exemption. The dashboard displays the number excluded, and Engagement is available as a starting-stage option.

## Deploy the configurable version to a sandbox

The ready-to-use deployment manifest is `manifest/explorer-package.xml`. From the VS Code terminal:

For an Explorer-only update, use `manifest/explorer-widget-package.xml`.

```bash
sf project deploy start --manifest manifest/explorer-package.xml --target-org cadex-partial --test-level RunSpecifiedTests --tests OpportunityConversionDashboardTest --tests OppYearCompareDashboardTest --wait 30
```

To validate without committing changes first:

```bash
sf project deploy validate --manifest manifest/explorer-package.xml --target-org cadex-partial --test-level RunSpecifiedTests --tests OpportunityConversionDashboardTest --tests OppYearCompareDashboardTest --wait 30
```

## Deploy from VS Code

1. Open this folder in VS Code with Salesforce CLI installed.
2. Authorize the sandbox if it is not already connected:

   ```bash
   sf org login web --instance-url https://test.salesforce.com --alias cadex-partial
   ```

3. In Explorer, right-click `manifest/explorer-package.xml` and select **SFDX: Deploy Source in Manifest to Org**. Alternatively, run:

   ```bash
   sf project deploy start --manifest manifest/explorer-package.xml --target-org cadex-partial --test-level RunSpecifiedTests --tests OpportunityConversionDashboardTest --tests OppYearCompareDashboardTest --wait 30
   ```

4. In Salesforce, open **Setup → Lightning App Builder**.
5. Edit the page containing **Opportunity Conversion Explorer**, save, and activate it. The seven comparison widgets appear within the Explorer after its conversion results load.

## Access requirements

Users need read access to Opportunities, Opportunity History, Opportunity Products, Products, and the fields used by the dashboards: Opportunity Name, Owner, Amount, Stage, Created Date, Close Date, Product Name, and `User.Sales_Team__c`.

## Important data note

The dashboard uses the date/time when Salesforce created each `OpportunityHistory` stage entry. Current-stage reports alone cannot establish whether a Closed Won Opportunity previously passed through Proposal or Verbal.
