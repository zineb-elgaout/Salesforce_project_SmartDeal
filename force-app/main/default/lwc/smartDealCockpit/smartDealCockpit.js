import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getCockpit from '@salesforce/apex/SmartDealCockpitController.getCockpit';

const REQUEST_ACTIONS = [
    { label: 'Ouvrir la demande', name: 'open_request' },
    { label: 'Ouvrir l’opportunité', name: 'open_opportunity' }
];

const REQUEST_COLUMNS = [
    { label: 'Client', fieldName: 'customerName', type: 'text', wrapText: true },
    { label: 'Produit', fieldName: 'productName', type: 'text', wrapText: true },
    {
        label: 'Qté',
        fieldName: 'quantity',
        type: 'number',
        cellAttributes: { alignment: 'right' }
    },
    { label: 'Ville', fieldName: 'city', type: 'text' },
    { label: 'Date', fieldName: 'requestedDate', type: 'text' },
    { label: 'Validation', fieldName: 'validationStatus', type: 'text' },
    { label: 'Faisabilité', fieldName: 'feasibilityStatus', type: 'text' },
    {
        type: 'action',
        typeAttributes: { rowActions: REQUEST_ACTIONS }
    }
];

const EMPTY_COUNTS = {
    requestsToValidate: 0,
    opportunitiesAtRisk: 0,
    scenariosToDecide: 0,
    scenariosSelected: 0,
    serviceOpen: 0,
    serviceOverdue: 0
};

export default class SmartDealCockpit extends NavigationMixin(LightningElement) {
    requestColumns = REQUEST_COLUMNS;
    cockpitData;
    wiredResult;
    error;
    isRefreshing = false;

    @wire(getCockpit)
    wiredCockpit(result) {
        this.wiredResult = result;
        if (result.data) {
            this.cockpitData = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = this.reduceError(result.error);
        }
    }

    get cockpit() {
        return this.cockpitData;
    }

    get counts() {
        return this.cockpitData ? this.cockpitData.counts : EMPTY_COUNTS;
    }

    get workQueue() {
        return this.cockpitData && this.cockpitData.workQueue ? this.cockpitData.workQueue : [];
    }

    get recentDecisions() {
        return this.cockpitData && this.cockpitData.recentDecisions
            ? this.cockpitData.recentDecisions
            : [];
    }

    get hasWorkQueue() {
        return this.workQueue.length > 0;
    }

    get hasDecisions() {
        return this.recentDecisions.length > 0;
    }

    get isLoading() {
        return !this.cockpitData && !this.error;
    }

    get hasError() {
        return Boolean(this.error);
    }

    get selectedRateLabel() {
        const generated = this.counts.scenariosSelected + this.counts.scenariosToDecide;
        if (!generated) {
            return '0 %';
        }
        return `${Math.round((this.counts.scenariosSelected * 100) / generated)} %`;
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

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        if (action.name === 'open_request' && row.requestId) {
            this.navigateToRecord(row.requestId, 'Customer_Request__c');
        } else if (action.name === 'open_opportunity' && row.opportunityId) {
            this.navigateToRecord(row.opportunityId, 'Opportunity');
        }
    }

    handleDecisionOpen(event) {
        const opportunityId = event.currentTarget.dataset.id;
        if (opportunityId) {
            this.navigateToRecord(opportunityId, 'Opportunity');
        }
    }

    handleOpenRequests() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Customer_Request__c',
                actionName: 'list'
            }
        });
    }

    handleOpenOpportunities() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Opportunity',
                actionName: 'list'
            }
        });
    }

    handleOpenScenarios() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Rescue_Scenario__c',
                actionName: 'list'
            }
        });
    }

    navigateToRecord(recordId, objectApiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName,
                actionName: 'view'
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
