import { LightningElement } from 'lwc';
import getCustomConversionData from '@salesforce/apex/OpportunityConversionDashboardController.getCustomConversionData';

const SOURCE_STAGE_OPTIONS = [
    { label: 'Engagement', value: 'Engagement' },
    { label: 'Define Needs', value: 'Define Needs' },
    { label: 'Solutioning', value: 'Solutioning' },
    { label: 'Proposal', value: 'Proposal' },
    { label: 'Negotiation', value: 'Negotiation' },
    { label: 'Verbal', value: 'Verbal' },
    { label: 'MSA/SOW Review', value: 'MSA/SOW Review' }
];

const COLUMNS = [
    {
        label: 'Opportunity',
        fieldName: 'opportunityUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'opportunityName' }, target: '_self' }
    },
    { label: 'Owner', fieldName: 'ownerName', type: 'text' },
    { label: 'Sales Team', fieldName: 'salesTeam', type: 'text' },
    { label: 'Products', fieldName: 'productNames', type: 'text', wrapText: true },
    {
        label: 'Amount',
        fieldName: 'amount',
        type: 'currency',
        typeAttributes: { maximumFractionDigits: 0 }
    },
    { label: 'Current Stage', fieldName: 'currentStage', type: 'text' },
    { label: 'Outcome', fieldName: 'outcome', type: 'text' },
    { label: 'Entered From Stage', fieldName: 'sourceDateLabel', type: 'text' },
    { label: 'Outcome Date', fieldName: 'outcomeDateLabel', type: 'text' },
    { label: 'Days to Outcome', fieldName: 'daysToOutcome', type: 'number' }
];

const OUTCOME_CONFIG = [
    { outcome: 'Won', property: 'includeWon', color: '#2e844a' },
    { outcome: 'Lost', property: 'includeLost', color: '#ba0517' },
    { outcome: 'Open', property: 'includeOpen', color: '#2f6fed' }
];

export default class OpportunityConversionExplorer extends LightningElement {
    columns = COLUMNS;
    stageOptions = SOURCE_STAGE_OPTIONS;
    sourceStage = 'Proposal';
    startDate;
    endDate;
    result;
    errorMessage;
    isLoading = false;
    isExpanded = false;
    includeWon = true;
    includeLost = true;
    includeOpen = false;
    comparisonYearA;
    comparisonYearB;
    selectedPieOutcome;
    salesTeamOptions = [];
    ownerOptions = [];
    productOptions = [];
    hasNoProduct = false;
    isSidebarVisible = true;
    isSalesTeamExpanded = true;
    isOwnerExpanded = true;
    isProductsExpanded = true;
    dimensionFiltersNeedReset = true;

    connectedCallback() {
        const today = new Date();
        this.startDate = `${today.getFullYear()}-01-01`;
        this.endDate = this.toDateInputValue(today);
        this.syncComparisonYearsFromDates();
        this.loadConversionData(true);
    }

    get hasResult() {
        return Boolean(this.result);
    }

    get toggleLabel() {
        return this.isExpanded ? 'Collapse' : 'Expand';
    }

    get toggleIcon() {
        return this.isExpanded ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get hasIncludedOpportunities() {
        return this.filteredOpportunities.length > 0;
    }

    get filteredOpportunities() {
        if (this.selectedPieOutcome) {
            return (this.result?.opportunities || []).filter(
                (row) => row.outcome === this.selectedPieOutcome
            );
        }

        return (this.result?.opportunities || []).filter((row) =>
            (row.outcome === 'Won' && this.includeWon) ||
            (row.outcome === 'Lost' && this.includeLost) ||
            (row.outcome === 'Open' && this.includeOpen)
        );
    }

    get productCloseRows() {
        const yearA = Number(this.comparisonYearA);
        const yearB = Number(this.comparisonYearB);
        const metrics = new Map();
        this.filteredOpportunities
            .filter((row) => row.daysToClose !== null && row.daysToClose !== undefined)
            .forEach((row) => {
                const year = new Date(row.createdAt).getFullYear();
                if (year !== yearA && year !== yearB) {
                    return;
                }
                const productLines = row.productLines?.length ? row.productLines : ['No Product'];
                productLines.forEach((productName) => {
                    if (!metrics.has(productName)) {
                        metrics.set(productName, {
                            productName,
                            sumA: 0,
                            countA: 0,
                            sumB: 0,
                            countB: 0
                        });
                    }
                    const metric = metrics.get(productName);
                    const suffix = year === yearA ? 'A' : 'B';
                    metric[`sum${suffix}`] += Number(row.daysToClose);
                    metric[`count${suffix}`] += 1;
                });
            });

        const rows = [...metrics.values()].map((metric) => ({
            ...metric,
            averageA: metric.countA ? metric.sumA / metric.countA : null,
            averageB: metric.countB ? metric.sumB / metric.countB : null
        }));
        const maxDays = Math.max(
            1,
            ...rows.flatMap((row) => [row.averageA || 0, row.averageB || 0])
        );
        return rows
            .sort((first, second) => first.productName.localeCompare(second.productName))
            .map((row) => ({
                ...row,
                averageALabel: row.averageA === null ? '—' : `${row.averageA.toFixed(1)} days`,
                averageBLabel: row.averageB === null ? '—' : `${row.averageB.toFixed(1)} days`,
                barAStyle: `width:${row.averageA === null ? 0 : (row.averageA / maxDays) * 100}%`,
                barBStyle: `width:${row.averageB === null ? 0 : (row.averageB / maxDays) * 100}%`
            }));
    }

    get hasProductCloseData() {
        return this.productCloseRows.length > 0;
    }

    get comparisonTitle() {
        return `Average Time to Close: ${this.comparisonYearA} vs ${this.comparisonYearB}`;
    }

    get comparisonYearAOptions() {
        return this.comparisonYearOptions.filter((option) => option.value !== this.comparisonYearB);
    }

    get comparisonYearBOptions() {
        return this.comparisonYearOptions.filter((option) => option.value !== this.comparisonYearA);
    }

    get comparisonYearOptions() {
        const currentYear = new Date().getFullYear();
        const startYear = Number((this.startDate || '').slice(0, 4)) || currentYear;
        const endYear = Number((this.endDate || '').slice(0, 4)) || currentYear;
        const minimumYear = Math.min(startYear, endYear, currentYear) - 5;
        const maximumYear = Math.max(startYear, endYear, currentYear) + 1;
        const options = [];
        for (let year = maximumYear; year >= minimumYear; year -= 1) {
            options.push({ label: String(year), value: String(year) });
        }
        return options;
    }

    get comparisonEmptyMessage() {
        return `No closed ${this.comparisonYearA} or ${this.comparisonYearB} Opportunities match the current filters and date range.`;
    }

    get includedBadge() {
        return this.selectedPieOutcome
            ? `${this.filteredOpportunities.length} ${this.selectedPieOutcome}`
            : `${this.filteredOpportunities.length} included`;
    }

    get tableTitle() {
        return this.selectedPieOutcome
            ? `${this.selectedPieOutcome} Opportunities`
            : 'Opportunity Outcomes';
    }

    get tableDescription() {
        return this.selectedPieOutcome
            ? `Showing the Opportunities represented by the ${this.selectedPieOutcome} chart slice.`
            : 'Displayed rows follow the Include Won, Lost, and Open selections.';
    }

    get selectedOutcomeItems() {
        if (!this.result) {
            return [];
        }

        const countByOutcome = {
            Won: Number(this.result.totalConverted || 0),
            Lost: Number(this.result.totalLost || 0),
            Open: Number(this.result.totalOpen || 0)
        };

        const selectedItems = OUTCOME_CONFIG
            .filter((config) => this[config.property])
            .map((config) => ({
                ...config,
                count: countByOutcome[config.outcome],
                style: `--outcome-color: ${config.color}`,
                className: this.selectedPieOutcome === config.outcome
                    ? 'legend-item active'
                    : 'legend-item'
            }));
        const selectedTotal = selectedItems.reduce((total, item) => total + item.count, 0);

        return selectedItems.map((item) => ({
            ...item,
            percentageLabel: selectedTotal === 0
                ? '0.0%'
                : `${((item.count / selectedTotal) * 100).toFixed(1)}%`
        }));
    }

    get chartTotal() {
        return this.selectedOutcomeItems.reduce((total, item) => total + item.count, 0);
    }

    get hasChartData() {
        return this.chartTotal > 0;
    }

    get chartSegments() {
        const positiveItems = this.selectedOutcomeItems.filter((item) => item.count > 0);
        const total = positiveItems.reduce((sum, item) => sum + item.count, 0);
        let startAngle = 0;

        return positiveItems.map((item) => {
            const fraction = item.count / total;
            const sweep = fraction * 359.999;
            const endAngle = startAngle + sweep;
            const labelPoint = this.polarPoint(30, startAngle + (sweep / 2));
            const segment = {
                ...item,
                path: this.createDonutPath(startAngle, endAngle),
                ariaLabel: `${item.outcome}: ${item.count} Opportunities`,
                percentageLabel: `${(fraction * 100).toFixed(1)}%`,
                labelX: labelPoint.x,
                labelY: labelPoint.y,
                showLabel: fraction >= 0.07
            };
            startAngle = endAngle;
            return segment;
        });
    }

    get chartAriaLabel() {
        const summary = this.selectedOutcomeItems
            .map((item) => `${item.outcome} ${item.count}`)
            .join(', ');
        return `Opportunity outcomes chart. ${summary || 'No outcomes selected.'}`;
    }

    get donutCenterLabel() {
        if (this.selectedPieOutcome) {
            return this.selectedPieOutcome;
        }
        if (this.includeWon && this.includeLost && !this.includeOpen) {
            return 'Closed';
        }
        return 'Included';
    }

    get detailsSectionClass() {
        return this.isExpanded ? 'details-panel expanded' : 'details-panel';
    }

    get workspaceClass() {
        return this.isSidebarVisible ? 'workspace' : 'workspace sidebar-hidden';
    }

    get sidebarToggleLabel() {
        return this.isSidebarVisible ? 'Hide filters' : 'Show filters';
    }

    get sidebarToggleIcon() {
        return this.isSidebarVisible ? 'utility:chevronleft' : 'utility:chevronright';
    }

    get salesTeamChevron() {
        return this.isSalesTeamExpanded ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get ownerChevron() {
        return this.isOwnerExpanded ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get productsChevron() {
        return this.isProductsExpanded ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get selectedSalesTeams() {
        return this.salesTeamOptions.filter((option) => option.checked).map((option) => option.value);
    }

    get selectedOwnerIds() {
        return this.ownerOptions.filter((option) => option.checked).map((option) => option.value);
    }

    get selectedProductIds() {
        return this.productOptions
            .filter((product) => product.checked)
            .map((product) => product.productId);
    }

    get selectedProductCount() {
        return this.selectedProductIds.length;
    }

    get totalProductChoiceCount() {
        return this.productOptions.length;
    }

    get noProductLabel() {
        const count = Number(this.result?.noProductOpportunityCount || 0);
        return `No Product (${count})`;
    }

    get disableSidebarApply() {
        return this.isLoading || this.dimensionFiltersNeedReset;
    }

    get salesTeamSelectionLabel() {
        return `${this.selectedSalesTeams.length}/${this.salesTeamOptions.length}`;
    }

    get ownerSelectionLabel() {
        return `${this.selectedOwnerIds.length}/${this.ownerOptions.length}`;
    }

    get productSelectionLabel() {
        return `${this.selectedProductCount}/${this.totalProductChoiceCount}`;
    }

    get dimensionSelectionSummary() {
        if (this.dimensionFiltersNeedReset) {
            return 'Apply the period filters to refresh sidebar choices';
        }
        return `${this.selectedSalesTeams.length} teams · ${this.selectedOwnerIds.length} owners · ${this.selectedProductCount} product choices`;
    }

    handleFilterChange(event) {
        this[event.target.name] = event.detail?.value ?? event.target.value;
        if (event.target.name === 'startDate' || event.target.name === 'endDate') {
            this.syncComparisonYearsFromDates();
        }
        this.dimensionFiltersNeedReset = true;
    }

    handleComparisonYearChange(event) {
        this[event.target.name] = event.detail.value;
        this.refreshYearComparison();
    }

    syncComparisonYearsFromDates() {
        const startYear = Number((this.startDate || '').slice(0, 4));
        const endYear = Number((this.endDate || '').slice(0, 4));
        if (!endYear) {
            return;
        }
        this.comparisonYearB = String(endYear);
        this.comparisonYearA = String(startYear && startYear !== endYear ? startYear : endYear - 1);
    }

    handleOutcomeChange(event) {
        this[event.target.name] = event.target.checked;
        this.selectedPieOutcome = undefined;
    }

    handleSidebarToggle() {
        this.isSidebarVisible = !this.isSidebarVisible;
    }

    handleFilterGroupToggle(event) {
        const section = event.currentTarget.dataset.section;
        if (section === 'salesTeam') {
            this.isSalesTeamExpanded = !this.isSalesTeamExpanded;
        } else if (section === 'owner') {
            this.isOwnerExpanded = !this.isOwnerExpanded;
        } else if (section === 'products') {
            this.isProductsExpanded = !this.isProductsExpanded;
        }
    }

    handleDimensionChange(event) {
        const group = event.currentTarget.dataset.group;
        const value = event.currentTarget.dataset.value;
        const checked = event.target.checked;
        if (group === 'salesTeam') {
            this.salesTeamOptions = this.salesTeamOptions.map((option) => ({
                ...option,
                checked: option.value === value ? checked : option.checked
            }));
            this.ownerOptions = this.ownerOptions.map((option) => ({
                ...option,
                checked: option.parentValue === value ? checked : option.checked
            }));
        } else {
            this.ownerOptions = this.ownerOptions.map((option) => ({
                ...option,
                checked: option.value === value ? checked : option.checked
            }));
        }
    }

    handleProductChange(event) {
        const productId = event.currentTarget.dataset.value;
        this.productOptions = this.productOptions.map((product) => ({
            ...product,
            checked: product.productId === productId ? event.target.checked : product.checked
        }));
    }

    handleSelectAll(event) {
        this.setGroupSelection(event.currentTarget.dataset.group, true);
    }

    handleClearGroup(event) {
        this.setGroupSelection(event.currentTarget.dataset.group, false);
    }

    setGroupSelection(group, checked) {
        if (group === 'salesTeam') {
            this.salesTeamOptions = this.salesTeamOptions.map((option) => ({ ...option, checked }));
            this.ownerOptions = this.ownerOptions.map((option) => ({ ...option, checked }));
        } else if (group === 'owner') {
            this.ownerOptions = this.ownerOptions.map((option) => ({ ...option, checked }));
        } else if (group === 'products') {
            this.productOptions = this.productOptions.map((option) => ({ ...option, checked }));
        }
    }

    async handleApplySidebarFilters() {
        await this.loadConversionData(false);
    }

    handleSliceClick(event) {
        this.selectPieOutcome(event.currentTarget.dataset.outcome);
    }

    handleSliceKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.selectPieOutcome(event.currentTarget.dataset.outcome);
        }
    }

    selectPieOutcome(outcome) {
        if (!outcome) {
            return;
        }
        this.selectedPieOutcome = outcome;
        this.isExpanded = true;
    }

    handleToggleTable() {
        this.isExpanded = !this.isExpanded;
    }

    async handleApply() {
        const inputs = [...this.template.querySelectorAll('lightning-input, lightning-combobox')];
        const allValid = inputs.reduce((valid, input) => {
            input.reportValidity();
            return valid && input.checkValidity();
        }, true);

        if (allValid) {
            await this.loadConversionData(this.dimensionFiltersNeedReset);
        }
    }

    async loadConversionData(resetDimensions = false) {
        this.isLoading = true;
        this.errorMessage = undefined;
        this.result = undefined;
        this.isExpanded = false;
        this.selectedPieOutcome = undefined;

        try {
            const selectedProductIds = resetDimensions ? null : this.selectedProductIds;
            const selectedOwnerIds = resetDimensions ? null : this.selectedOwnerIds;
            const data = await getCustomConversionData({
                startDate: this.startDate,
                endDate: this.endDate,
                sourceStage: this.sourceStage,
                selectedProductIds,
                selectedOwnerIds
            });
            const selectedSalesTeamSet = new Set(this.selectedSalesTeams);
            const selectedOwnerIdSet = new Set(selectedOwnerIds || []);
            const selectedProductIdSet = new Set(selectedProductIds || []);
            this.salesTeamOptions = this.prepareFilterOptions(
                data.availableSalesTeams,
                resetDimensions,
                selectedSalesTeamSet
            );
            this.ownerOptions = this.prepareFilterOptions(
                data.availableOwners,
                resetDimensions,
                selectedOwnerIdSet
            );
            this.productOptions = (data.availableProducts || []).map((product) => ({
                ...product,
                label: `${product.productName} (${product.opportunityCount})`,
                checked: resetDimensions || selectedProductIds === null ||
                    selectedProductIdSet.has(product.productId)
            }));
            this.hasNoProduct = Boolean(data.hasNoProduct);
            this.dimensionFiltersNeedReset = false;
            this.result = this.prepareResult(data);
        } catch (error) {
            this.result = undefined;
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
        await this.refreshYearComparison();
    }

    async refreshYearComparison() {
        await new Promise((resolve) => setTimeout(resolve, 0));
        const comparisonDashboard = this.template.querySelector('c-opportunity-year-comparison-dashboard');
        if (comparisonDashboard) {
            await comparisonDashboard.refresh();
        }
    }

    prepareFilterOptions(options, resetDimensions, selectedValues) {
        return (options || []).map((option) => ({
            ...option,
            label: `${option.label} (${option.opportunityCount})`,
            checked: resetDimensions || selectedValues === null || selectedValues.has(option.value)
        }));
    }

    prepareResult(data) {
        const conversionRate = Number(data.conversionRate || 0);
        const closedWinRate = Number(data.closedWinRate || 0);
        return {
            ...data,
            conversionRateLabel: `${conversionRate.toFixed(1)}%`,
            closedWinRateLabel: `${closedWinRate.toFixed(1)}%`,
            rangeLabel: `${this.formatDate(data.startDate)} – ${this.formatDate(data.endDate)}`,
            opportunities: (data.opportunities || []).map((row) => ({
                ...row,
                opportunityUrl: `/lightning/r/Opportunity/${row.opportunityId}/view`,
                sourceDateLabel: this.formatDateTime(row.enteredSourceStageAt),
                outcomeDateLabel: this.formatDateTime(row.outcomeAt)
            }))
        };
    }

    createDonutPath(startAngle, endAngle) {
        const outerRadius = 38;
        const innerRadius = 22;
        const outerStart = this.polarPoint(outerRadius, startAngle);
        const outerEnd = this.polarPoint(outerRadius, endAngle);
        const innerEnd = this.polarPoint(innerRadius, endAngle);
        const innerStart = this.polarPoint(innerRadius, startAngle);
        const largeArc = endAngle - startAngle > 180 ? 1 : 0;

        return [
            `M ${outerStart.x} ${outerStart.y}`,
            `A ${outerRadius} ${outerRadius} 0 ${largeArc} 1 ${outerEnd.x} ${outerEnd.y}`,
            `L ${innerEnd.x} ${innerEnd.y}`,
            `A ${innerRadius} ${innerRadius} 0 ${largeArc} 0 ${innerStart.x} ${innerStart.y}`,
            'Z'
        ].join(' ');
    }

    polarPoint(radius, angle) {
        const radians = ((angle - 90) * Math.PI) / 180;
        return {
            x: (50 + radius * Math.cos(radians)).toFixed(3),
            y: (50 + radius * Math.sin(radians)).toFixed(3)
        };
    }

    toDateInputValue(value) {
        const year = value.getFullYear();
        const month = String(value.getMonth() + 1).padStart(2, '0');
        const day = String(value.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    formatDate(value) {
        if (!value) return '';
        const [year, month, day] = value.split('-').map(Number);
        return new Intl.DateTimeFormat('en-US', {
            month: 'short', day: 'numeric', year: 'numeric'
        }).format(new Date(year, month - 1, day));
    }

    formatDateTime(value) {
        if (!value) return '';
        return new Intl.DateTimeFormat('en-US', {
            month: 'short', day: 'numeric', year: 'numeric'
        }).format(new Date(value));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'The conversion report could not be loaded.';
    }
}
