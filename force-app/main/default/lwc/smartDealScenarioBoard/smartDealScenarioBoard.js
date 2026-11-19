import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getBoard from '@salesforce/apex/SmartDealScenarioController.getBoard';
import selectScenario from '@salesforce/apex/SmartDealScenarioController.selectScenario';
import rejectScenario from '@salesforce/apex/SmartDealScenarioController.rejectScenario';

export default class SmartDealScenarioBoard extends NavigationMixin(LightningElement) {
    @api recordId;

    boardData;
    wiredResult;
    error;
    isWorking = false;
    pendingAction;
    pendingScenarioId;
    pendingScenarioName;
    decisionComment = '';
    rejectionReason = '';

    @wire(getBoard, { opportunityId: '$recordId' })
    wiredBoard(result) {
        this.wiredResult = result;
        if (result.data) {
            this.boardData = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = this.reduceError(result.error);
        }
    }

    get board() {
        return this.boardData;
    }

    get opportunity() {
        return this.boardData ? this.boardData.opportunity : undefined;
    }

    get scenarios() {
        if (!this.boardData || !this.boardData.scenarios) {
            return [];
        }
        return this.boardData.scenarios.map((scenario) => ({
            ...scenario,
            cardClass: scenario.selected
                ? 'scenario-card scenario-card-selected'
                : 'scenario-card'
        }));
    }

    get hasScenarios() {
        return this.scenarios.length > 0;
    }

    get warning() {
        return this.boardData ? this.boardData.warning : undefined;
    }

    get hasWarning() {
        return Boolean(this.warning);
    }

    get relatedRequestId() {
        return this.boardData ? this.boardData.relatedRequestId : undefined;
    }

    get noRelatedRequest() {
        return !this.relatedRequestId;
    }

    get selectedCount() {
        return this.boardData ? this.boardData.selectedCount : 0;
    }

    get isLoading() {
        return !this.boardData && !this.error;
    }

    get hasError() {
        return Boolean(this.error);
    }

    get showSelectPanel() {
        return this.pendingAction === 'select';
    }

    get showRejectPanel() {
        return this.pendingAction === 'reject';
    }

    get selectDisabled() {
        return this.isWorking || !this.decisionComment || !this.decisionComment.trim();
    }

    get rejectDisabled() {
        return this.isWorking || !this.rejectionReason || !this.rejectionReason.trim();
    }

    get feasibilityClass() {
        if (!this.opportunity) {
            return 'badge badge-neutral';
        }
        if (this.opportunity.feasibilityStatus === 'Feasible') {
            return 'badge badge-success';
        }
        if (this.opportunity.feasibilityStatus === 'At Risk') {
            return 'badge badge-warning';
        }
        if (this.opportunity.feasibilityStatus === 'Rescued') {
            return 'badge badge-success';
        }
        return 'badge badge-neutral';
    }

    handleSelectClick(event) {
        this.pendingAction = 'select';
        this.pendingScenarioId = event.currentTarget.dataset.id;
        this.pendingScenarioName = event.currentTarget.dataset.name;
        this.decisionComment = '';
        this.rejectionReason = '';
    }

    handleRejectClick(event) {
        this.pendingAction = 'reject';
        this.pendingScenarioId = event.currentTarget.dataset.id;
        this.pendingScenarioName = event.currentTarget.dataset.name;
        this.decisionComment = '';
        this.rejectionReason = '';
    }

    handleCommentChange(event) {
        this.decisionComment = event.target.value;
    }

    handleReasonChange(event) {
        this.rejectionReason = event.target.value;
    }

    handleCancel() {
        this.pendingAction = undefined;
        this.pendingScenarioId = undefined;
        this.pendingScenarioName = undefined;
        this.decisionComment = '';
        this.rejectionReason = '';
    }

    async handleConfirmSelect() {
        if (this.selectDisabled) {
            return;
        }
        const scenarioName = this.pendingScenarioName;
        this.isWorking = true;
        try {
            const result = await selectScenario({
                scenarioId: this.pendingScenarioId,
                comment: this.decisionComment
            });
            this.boardData = result;
            this.handleCancel();
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Scénario sélectionné',
                    message: `${scenarioName || 'Le scénario'} a été retenu. La décision est horodatée.`,
                    variant: 'success'
                })
            );
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Sélection impossible',
                    message: this.reduceError(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isWorking = false;
        }
    }

    async handleConfirmReject() {
        if (this.rejectDisabled) {
            return;
        }
        this.isWorking = true;
        try {
            const result = await rejectScenario({
                scenarioId: this.pendingScenarioId,
                reason: this.rejectionReason
            });
            this.boardData = result;
            this.handleCancel();
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Scénario rejeté',
                    message: 'Le motif de rejet a été enregistré.',
                    variant: 'success'
                })
            );
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Rejet impossible',
                    message: this.reduceError(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isWorking = false;
        }
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

    handleOpenRequest() {
        if (!this.relatedRequestId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.relatedRequestId,
                objectApiName: 'Customer_Request__c',
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
