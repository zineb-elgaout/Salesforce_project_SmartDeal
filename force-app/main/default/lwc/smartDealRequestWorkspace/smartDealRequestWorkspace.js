import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getWorkspace from '@salesforce/apex/SmartDealRequestWorkspaceController.getWorkspace';
import validateRequest from '@salesforce/apex/SmartDealRequestWorkspaceController.validateRequest';

const WAREHOUSE_COLUMNS = [
    { label: 'Entrepôt', fieldName: 'warehouseName', type: 'text', wrapText: true },
    { label: 'Ville', fieldName: 'city', type: 'text' },
    {
        label: 'Disponible',
        fieldName: 'usableQuantity',
        type: 'number',
        cellAttributes: { alignment: 'right' }
    },
    {
        label: 'Prix unitaire',
        fieldName: 'unitPrice',
        type: 'currency',
        typeAttributes: { currencyCode: 'MAD' },
        cellAttributes: { alignment: 'right' }
    },
    {
        label: 'Délai',
        fieldName: 'leadTimeDays',
        type: 'number',
        cellAttributes: { alignment: 'right' }
    },
    { label: 'Livraison', fieldName: 'estimatedDeliveryDate', type: 'text' },
    {
        label: 'Total',
        fieldName: 'estimatedTotal',
        type: 'currency',
        typeAttributes: { currencyCode: 'MAD' },
        cellAttributes: { alignment: 'right' }
    },
    { label: 'Statut', fieldName: 'statusLabel', type: 'text' },
    { label: 'Blocages', fieldName: 'blockingReasons', type: 'text', wrapText: true }
];

export default class SmartDealRequestWorkspace extends NavigationMixin(LightningElement) {
    @api recordId;

    warehouseColumns = WAREHOUSE_COLUMNS;
    workspaceData;
    wiredResult;
    error;
    isWorking = false;

    @wire(getWorkspace, { requestId: '$recordId' })
    wiredWorkspace(result) {
        this.wiredResult = result;
        if (result.data) {
            this.workspaceData = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = this.reduceError(result.error);
        }
    }

    get workspace() {
        return this.workspaceData;
    }

    get request() {
        return this.workspaceData ? this.workspaceData.request : undefined;
    }

    get checklist() {
        return this.workspaceData && this.workspaceData.checklist
            ? this.workspaceData.checklist
            : [];
    }

    get inventory() {
        return this.workspaceData ? this.workspaceData.inventory : undefined;
    }

    get warehouses() {
        if (!this.inventory || !this.inventory.warehouses) {
            return [];
        }
        return this.inventory.warehouses.map((row) => ({
            ...row,
            statusLabel: row.eligible ? 'Éligible' : 'Bloqué'
        }));
    }

    get hasWarehouses() {
        return this.warehouses.length > 0;
    }

    get canValidate() {
        return this.workspaceData ? this.workspaceData.canValidate : false;
    }

    get isValidated() {
        return this.workspaceData ? this.workspaceData.isValidated : false;
    }

    get hasMissingInformation() {
        return Boolean(this.request && this.request.missingInformation);
    }

    get isAtRisk() {
        return this.request && this.request.feasibilityStatus === 'At Risk';
    }

    get isFeasible() {
        return this.request && this.request.feasibilityStatus === 'Feasible';
    }

    get inventoryLabel() {
        if (!this.inventory) {
            return 'Non vérifié';
        }
        const labels = {
            FEASIBLE: 'Faisable',
            AT_RISK: 'À risque',
            NO_STOCK: 'Aucun stock',
            NO_DATA: 'Données manquantes',
            INVALID_REQUEST: 'Demande invalide',
            LIMIT_EXCEEDED: 'Limite dépassée'
        };
        return labels[this.inventory.status] || this.inventory.status;
    }

    get inventoryClass() {
        if (!this.inventory) {
            return 'badge badge-neutral';
        }
        if (this.inventory.status === 'FEASIBLE') {
            return 'badge badge-success';
        }
        if (this.inventory.status === 'AT_RISK') {
            return 'badge badge-warning';
        }
        return 'badge badge-error';
    }

    get feasibilityClass() {
        if (this.isFeasible) {
            return 'badge badge-success';
        }
        if (this.isAtRisk) {
            return 'badge badge-warning';
        }
        return 'badge badge-neutral';
    }

    get isLoading() {
        return !this.workspaceData && !this.error;
    }

    get hasError() {
        return Boolean(this.error);
    }

    async handleRefresh() {
        if (!this.wiredResult) {
            return;
        }
        this.isWorking = true;
        try {
            await refreshApex(this.wiredResult);
        } finally {
            this.isWorking = false;
        }
    }

    async handleValidate() {
        if (!this.recordId) {
            return;
        }
        this.isWorking = true;
        try {
            const result = await validateRequest({ requestId: this.recordId });
            this.workspaceData = result;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Demande validée',
                    message:
                        'Le statut est passé à Validated. Flow 1 et Flow 2 prennent le relais.',
                    variant: 'success'
                })
            );
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Validation impossible',
                    message: this.reduceError(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isWorking = false;
        }
    }

    handleEdit() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: 'Customer_Request__c',
                actionName: 'edit'
            }
        });
    }

    handleOpenOpportunity() {
        if (!this.request || !this.request.opportunityId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.request.opportunityId,
                objectApiName: 'Opportunity',
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
