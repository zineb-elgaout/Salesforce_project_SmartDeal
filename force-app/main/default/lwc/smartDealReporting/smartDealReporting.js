import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getDashboard from '@salesforce/apex/SmartDealReportingController.getDashboard';

export default class SmartDealReporting extends NavigationMixin(LightningElement) {
    dashboardData;
    wiredResult;
    error;
    isRefreshing = false;

    @wire(getDashboard)
    wiredDashboard(result) {
        this.wiredResult = result;
        if (result.data) {
            this.dashboardData = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = this.reduceError(result.error);
        }
    }

    get dashboard() {
        return this.dashboardData;
    }

    get isLoading() {
        return !this.dashboardData && !this.error;
    }

    get hasError() {
        return Boolean(this.error);
    }

    get hasData() {
        return Boolean(this.dashboardData);
    }

    get kpis() {
        if (!this.dashboardData) {
            return [];
        }
        const data = this.dashboardData;
        return [
            {
                key: 'validation',
                label: 'Demandes validées',
                value: data.requestsValidated,
                detail: `${data.requestsToValidate} à traiter sur ${data.requestsTotal}`,
                rate: data.validationRate,
                hasRate: true,
                cardClass: 'kpi-card kpi-blue'
            },
            {
                key: 'risk',
                label: 'Opportunités à risque',
                value: data.opportunitiesAtRisk,
                detail: `${data.opportunitiesFeasible} faisables · ${data.opportunitiesRescued} sauvées`,
                rate: null,
                hasRate: false,
                cardClass: 'kpi-card kpi-red'
            },
            {
                key: 'selection',
                label: 'Scénarios sélectionnés',
                value: data.scenariosSelected,
                detail: `${data.scenariosGenerated} scénarios générés`,
                rate: data.selectionRate,
                hasRate: true,
                cardClass: 'kpi-card kpi-green'
            },
            {
                key: 'score',
                label: 'Score moyen retenu',
                value: data.averageSelectedScore,
                detail: 'Sur les scénarios sélectionnés',
                rate: null,
                hasRate: false,
                cardClass: 'kpi-card kpi-teal'
            },
            {
                key: 'service',
                label: 'Service ouvert',
                value: data.serviceOpen,
                detail: `${data.serviceOverdue} en retard sur ${data.serviceTotal}`,
                rate: null,
                hasRate: false,
                cardClass: 'kpi-card kpi-amber'
            }
        ];
    }

    get funnel() {
        return this.dashboardData && this.dashboardData.funnel ? this.dashboardData.funnel : [];
    }

    get hasFunnel() {
        return this.funnel.length > 0;
    }

    get scenarioTypes() {
        return this.dashboardData && this.dashboardData.scenarioTypes
            ? this.dashboardData.scenarioTypes
            : [];
    }

    get hasScenarioTypes() {
        return this.scenarioTypes.length > 0;
    }

    get servicePriorities() {
        return this.dashboardData && this.dashboardData.servicePriorities
            ? this.dashboardData.servicePriorities
            : [];
    }

    get hasServicePriorities() {
        return this.servicePriorities.length > 0;
    }

    async handleRefresh() {
        if (!this.wiredResult) {
            return;
        }
        this.isRefreshing = true;
        try {
            await refreshApex(this.wiredResult);
        } finally {
            this.isRefreshing = false;
        }
    }

    handleOpenRequests() {
        this.navigateToList('Customer_Request__c');
    }

    handleOpenOpportunities() {
        this.navigateToList('Opportunity');
    }

    handleOpenScenarios() {
        this.navigateToList('Rescue_Scenario__c');
    }

    handleOpenService() {
        this.navigateToList('Service_Request__c');
    }

    navigateToList(objectApiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName,
                actionName: 'list'
            }
        });
    }

    reduceError(error) {
        if (Array.isArray(error && error.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return error && error.message ? error.message : 'Erreur inconnue.';
    }
}
