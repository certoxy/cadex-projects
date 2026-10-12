import { LightningElement } from 'lwc';
import getDashboardData from '@salesforce/apex/OppYearCompareDashboardController.getDashboardData';

const CLOSED_WON_COLUMNS = [
    {
        label: 'Opportunity',
        fieldName: 'opportunityUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'opportunityName' }, target: '_blank' }
    },
    { label: 'Year', fieldName: 'cohortYear', type: 'number', initialWidth: 90 },
    { label: 'Owner', fieldName: 'ownerName' },
    { label: 'Sales Team', fieldName: 'salesTeam' },
    { label: 'Products', fieldName: 'productNames', wrapText: true },
    { label: '12mo Deal Value (Amount)', fieldName: 'amount', type: 'currency' },
    { label: 'Created', fieldName: 'createdDate', type: 'date' },
    { label: 'Closed', fieldName: 'closedDate', type: 'date' },
    { label: 'Days', fieldName: 'daysToClose', type: 'number', initialWidth: 80 }
];

export default class OpportunityYearComparisonDashboard extends LightningElement {
    compareThroughDate = new Date().toISOString().slice(0, 10);
    dashboard;
    year2025;
    year2026;
    stageRows = [];
    productRows = [];
    closedWonRows = [];
    salesTeams = [];
    owners = [];
    products = [];
    isLoading = true;
    errorMessage;
    detailsExpanded = false;
    filtersCollapsed = false;
    closedWonColumns = CLOSED_WON_COLUMNS;

    connectedCallback() {
        this.loadDashboard(true);
    }

    async loadDashboard(resetFilters) {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const result = await getDashboardData({
                compareThroughDate: this.compareThroughDate,
                selectedOwnerIds: resetFilters ? null : this.selectedOwnerIds,
                selectedProductIds: resetFilters ? null : this.selectedProductIds
            });
            this.prepareDashboard(result, resetFilters);
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load dashboard data.';
        } finally {
            this.isLoading = false;
        }
    }

    prepareDashboard(result, resetFilters) {
        this.dashboard = result;
        this.year2025 = this.decorateYear(result.years[0]);
        this.year2026 = this.decorateYear(result.years[1]);
        this.stageRows = result.stages.map((row) => ({
            ...row,
            rate2025Label: `${row.rate2025}%`,
            rate2026Label: `${row.rate2026}%`,
            bar2025Style: `width:${Math.min(row.rate2025, 100)}%`,
            bar2026Style: `width:${Math.min(row.rate2026, 100)}%`
        }));
        const maxCloseDays = Math.max(
            1,
            ...result.products.flatMap((row) => [
                row.closedCount2025 ? row.averageCloseDays2025 : 0,
                row.closedCount2026 ? row.averageCloseDays2026 : 0
            ])
        );
        this.productRows = result.products.map((row) => ({
            ...row,
            averageDealValue2025Label: this.formatCurrency(row.averageDealValue2025),
            averageDealValue2026Label: this.formatCurrency(row.averageDealValue2026),
            averageCloseDays2025Label: this.formatProductDays(row.averageCloseDays2025, row.closedCount2025),
            averageCloseDays2026Label: this.formatProductDays(row.averageCloseDays2026, row.closedCount2026),
            closeDays2025Style: `width:${row.closedCount2025 ? (row.averageCloseDays2025 / maxCloseDays) * 100 : 0}%`,
            closeDays2026Style: `width:${row.closedCount2026 ? (row.averageCloseDays2026 / maxCloseDays) * 100 : 0}%`
        }));
        this.closedWonRows = result.closedWonOpportunities.map((row) => ({
            ...row,
            opportunityUrl: `/${row.opportunityId}`
        }));
        this.salesTeams = this.mergeOptions(result.availableSalesTeams, this.salesTeams, resetFilters);
        this.owners = this.mergeOptions(result.availableOwners, this.owners, resetFilters);
        this.products = this.mergeOptions(result.availableProducts, this.products, resetFilters);
    }

    decorateYear(year) {
        return {
            ...year,
            winRateLabel: `${year.winRate}%`,
            averageFinalDealValueLabel: this.formatCurrency(year.averageFinalDealValue),
            averageDaysToCloseLabel: this.formatDays(year.averageDaysToClose)
        };
    }

    mergeOptions(options, previous, reset) {
        const priorState = new Map(previous.map((item) => [item.value, item.checked]));
        return options.map((item) => ({
            ...item,
            displayLabel: `${item.label} (${item.opportunityCount})`,
            checked: reset || !priorState.has(item.value) ? true : priorState.get(item.value)
        }));
    }

    get selectedOwnerIds() {
        return this.owners.filter((item) => item.checked).map((item) => item.value);
    }

    get selectedProductIds() {
        return this.products.filter((item) => item.checked).map((item) => item.value);
    }

    get filterToggleIcon() {
        return this.filtersCollapsed ? 'utility:chevronright' : 'utility:chevronleft';
    }

    get filterToggleTitle() {
        return this.filtersCollapsed ? 'Show filters' : 'Hide filters';
    }

    get layoutClass() {
        return this.filtersCollapsed ? 'dashboard-layout filters-hidden' : 'dashboard-layout';
    }

    get detailsIcon() {
        return this.detailsExpanded ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get detailsLabel() {
        return `${this.detailsExpanded ? 'Hide' : 'Show'} ${this.closedWonRows.length} Opportunities`;
    }

    get hasProducts() {
        return this.productRows.length > 0;
    }

    get noProductOpportunityCount() {
        return this.dashboard?.noProductOpportunityCount || 0;
    }

    handleDateChange(event) {
        this.compareThroughDate = event.target.value;
    }

    handleApplyDate() {
        this.loadDashboard(true);
    }

    handleApplyFilters() {
        this.loadDashboard(false);
    }

    handleTeamChange(event) {
        const value = event.target.dataset.value;
        const checked = event.target.checked;
        this.salesTeams = this.salesTeams.map((item) => item.value === value ? { ...item, checked } : item);
        this.owners = this.owners.map((item) => item.parentValue === value ? { ...item, checked } : item);
    }

    handleOwnerChange(event) {
        const value = event.target.dataset.value;
        const checked = event.target.checked;
        this.owners = this.owners.map((item) => item.value === value ? { ...item, checked } : item);
    }

    handleProductChange(event) {
        const value = event.target.dataset.value;
        const checked = event.target.checked;
        this.products = this.products.map((item) => item.value === value ? { ...item, checked } : item);
    }

    handleSelectAll(event) {
        const group = event.currentTarget.dataset.group;
        this[group] = this[group].map((item) => ({ ...item, checked: true }));
    }

    handleClearAll(event) {
        const group = event.currentTarget.dataset.group;
        this[group] = this[group].map((item) => ({ ...item, checked: false }));
    }

    toggleFilters() {
        this.filtersCollapsed = !this.filtersCollapsed;
    }

    toggleDetails() {
        this.detailsExpanded = !this.detailsExpanded;
    }

    formatCurrency(value) {
        return new Intl.NumberFormat('en-US', {
            style: 'currency', currency: 'USD', maximumFractionDigits: 0
        }).format(value || 0);
    }

    formatDays(value) {
        return `${Number(value || 0).toFixed(1)} days`;
    }

    formatProductDays(value, count) {
        return count ? `${Number(value || 0).toFixed(1)} days` : '—';
    }
}
