import { createElement } from 'lwc';
import FieldTransitionChecklist from 'c/fieldTransitionChecklist';
import getPendingRequirements from '@salesforce/apex/FieldTransitionRequirementController.getPendingRequirements';
import { getRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';

jest.mock(
    '@salesforce/apex/FieldTransitionRequirementController.getPendingRequirements',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex',
    () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
    { virtual: true }
);

const GROUPS = [
    {
        fieldApiName: 'StageName',
        fieldLabel: 'Stage',
        currentValue: 'Prospecting',
        transitions: [
            {
                fromValue: 'Any',
                toValue: 'Closed Lost',
                allSatisfied: false,
                conditions: [
                    { label: 'A reason', conditionType: 'Parent Field Criteria', satisfied: false },
                    { label: 'An amount', conditionType: 'Parent Field Criteria', satisfied: true }
                ]
            },
            {
                fromValue: 'Any',
                toValue: 'Closed Lost',
                allSatisfied: true,
                conditions: [{ label: 'A reason', conditionType: 'Parent Field Criteria', satisfied: true }]
            }
        ]
    }
];

function createComponent() {
    const element = createElement('c-field-transition-checklist', { is: FieldTransitionChecklist });
    element.recordId = '006000000000001AAA';
    element.objectApiName = 'Opportunity';
    document.body.appendChild(element);
    return element;
}

function flush() {
    return Promise.resolve().then(() => Promise.resolve());
}

describe('c-field-transition-checklist', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows each transition and condition with its status', async () => {
        const element = createComponent();
        getPendingRequirements.emit(GROUPS);
        await flush();

        const heading = element.shadowRoot.querySelector('h3');
        expect(heading.textContent).toContain('Stage');
        const boxes = element.shadowRoot.querySelectorAll('.slds-box');
        expect(boxes.length).toBe(2);
        const items = element.shadowRoot.querySelectorAll('li');
        expect(items.length).toBe(3);
        const icons = Array.from(items).map((li) => li.querySelector('lightning-icon').iconName);
        expect(icons).toEqual(['utility:close', 'utility:success', 'utility:success']);
        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
    });

    it('gives two rules to the same value their own keys', async () => {
        const element = createComponent();
        getPendingRequirements.emit(GROUPS);
        await flush();
        // Two "Any -> Closed Lost" rules render as two boxes: duplicate keys would drop or merge them.
        expect(element.shadowRoot.querySelectorAll('.slds-box').length).toBe(2);
    });

    it('shows the empty state when no rule applies', async () => {
        const element = createComponent();
        getPendingRequirements.emit([]);
        await flush();
        expect(element.shadowRoot.querySelector('p.slds-text-color_weak')).not.toBeNull();
    });

    it('shows the server error message', async () => {
        const element = createComponent();
        getPendingRequirements.error({ message: 'No access to the Apex class' });
        await flush();
        const error = element.shadowRoot.querySelector('.slds-text-color_error');
        expect(error.textContent).toContain('No access to the Apex class');
    });

    it('falls back to a generic message for an unexpected error', async () => {
        const element = createComponent();
        getPendingRequirements.error({ details: 'no message' });
        await flush();
        const error = element.shadowRoot.querySelector('.slds-text-color_error');
        expect(error.textContent).toContain('unexpected error');
    });

    it('refreshes when the Refresh button is clicked', async () => {
        const element = createComponent();
        getPendingRequirements.emit(GROUPS);
        await flush();
        element.shadowRoot.querySelector('lightning-button').click();
        await flush();
        expect(refreshApex).toHaveBeenCalledTimes(1);
    });

    it('refreshes when the record is saved, but not on the first load', async () => {
        createComponent();
        getPendingRequirements.emit(GROUPS);
        getRecord.emit({ lastModifiedDate: '2026-11-09T10:00:00.000Z' });
        await flush();
        expect(refreshApex).not.toHaveBeenCalled();

        getRecord.emit({ lastModifiedDate: '2026-11-09T10:05:00.000Z' });
        await flush();
        expect(refreshApex).toHaveBeenCalledTimes(1);
    });
});
