import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { getRecord } from 'lightning/uiRecordApi';
import getPendingRequirements from '@salesforce/apex/FieldTransitionRequirementController.getPendingRequirements';
import checklistTitle from '@salesforce/label/c.Field_Transition_Checklist_Title';
import emptyStateMessage from '@salesforce/label/c.Field_Transition_Checklist_Empty_State';

export default class FieldTransitionChecklist extends LightningElement {
    @api recordId;
    @api objectApiName;

    label = {
        checklistTitle,
        emptyStateMessage
    };

    groups = [];
    error;
    isLoading = true;
    wiredResult;
    lastModified;

    get recordFields() {
        return this.objectApiName ? [this.objectApiName + '.LastModifiedDate'] : [];
    }

    // Reload the checklist whenever the record itself is saved, so it never shows a stale state after an edit.
    @wire(getRecord, { recordId: '$recordId', optionalFields: '$recordFields' })
    wiredRecord({ data }) {
        if (!data) {
            return;
        }
        const modified = data.lastModifiedDate || (data.fields && data.fields.LastModifiedDate && data.fields.LastModifiedDate.value);
        if (this.lastModified && modified !== this.lastModified && this.wiredResult) {
            this.handleRefresh();
        }
        this.lastModified = modified;
    }

    @wire(getPendingRequirements, { recordId: '$recordId' })
    wiredRequirements(result) {
        this.wiredResult = result;
        if (result.data) {
            this.groups = result.data.map((group) => this.decorateGroup(group));
            this.error = undefined;
            this.isLoading = false;
        } else if (result.error) {
            this.error = this.extractErrorMessage(result.error);
            this.groups = [];
            this.isLoading = false;
        }
    }

    get hasGroups() {
        return this.groups.length > 0;
    }

    get showEmptyState() {
        return !this.isLoading && !this.error && !this.hasGroups;
    }

    handleRefresh() {
        this.isLoading = true;
        return refreshApex(this.wiredResult).finally(() => {
            this.isLoading = false;
        });
    }

    decorateGroup(group) {
        return {
            ...group,
            key: group.fieldApiName,
            transitions: group.transitions.map((transition) => this.decorateTransition(transition))
        };
    }

    decorateTransition(transition) {
        return {
            ...transition,
            key: transition.fromValue + '->' + transition.toValue,
            statusIcon: transition.allSatisfied ? 'utility:success' : 'utility:warning',
            statusVariant: transition.allSatisfied ? 'success' : 'warning',
            conditions: transition.conditions.map((condition, index) => ({
                ...condition,
                key: transition.fromValue + '->' + transition.toValue + '-' + index,
                statusIcon: condition.satisfied ? 'utility:success' : 'utility:close',
                statusVariant: condition.satisfied ? 'success' : 'error'
            }))
        };
    }

    extractErrorMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return 'An unexpected error occurred while loading the checklist.';
    }
}
