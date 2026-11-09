# Field Transition Framework

A metadata-driven Apex framework for Salesforce that blocks a field from changing to a configured value until a set of configurable conditions are met — checks against the record itself, against related child records, or both. Ships with a Lightning web component that shows a record's outstanding requirements before you even try to save.

## Purpose

Stage-gating logic (an Opportunity can't move to a given stage until X, Y, Z are true) tends to end up hardcoded in validation rules or Apex, spread across the org, hard to see in one place and hard to change without a deploy. The goal of this framework is:

- **Configuration over code** — which field, which transition, and which conditions block it live in `Field_Transition_Rule__mdt` and `Transition_Condition__mdt` records. Adding, disabling, or changing a requirement doesn't require touching Apex.
- **Works on any object and any field** — nothing in the framework is specific to Opportunity/StageName or any other object. `Object_API_Name__c` and `Field_API_Name__c` are plain text.
- **Four ways to express a requirement** — a related child record must (or must not) exist, a field on the record itself must match a comparison, or a combination of both. See [`docs/USAGE.md`](docs/USAGE.md) for the full reference.
- **Bulk-safe** — validating a batch of records costs one query per distinct condition that batch actually needs, not one per record. A 500-record update doesn't come close to the governor limit.
- **A companion checklist, not just a blocker** — `fieldTransitionChecklist` is a Lightning web component you can drop on any record page. It shows every reachable next value for a governed field and which of its conditions are already met, before the user tries to save.

See [`docs/USAGE.md`](docs/USAGE.md) for how to configure a rule, every supported operator and field type with worked examples, and what to avoid.

## Contents

- [`force-app/main/default/classes/FieldTransitionValidator.cls`](force-app/main/default/classes/FieldTransitionValidator.cls) — call this from a trigger's `before update` to block a transition. Bulk-safe.
- [`force-app/main/default/classes/FieldTransitionConditionEvaluator.cls`](force-app/main/default/classes/FieldTransitionConditionEvaluator.cls) — evaluates a single condition against a record. Shared by the validator and the checklist service; has no idea which one is calling it.
- [`force-app/main/default/classes/FieldTransitionMetadataService.cls`](force-app/main/default/classes/FieldTransitionMetadataService.cls) — read-only access to the two custom metadata types.
- [`force-app/main/default/classes/FieldTransitionRequirementService.cls`](force-app/main/default/classes/FieldTransitionRequirementService.cls) — builds the read-only checklist (never blocks anything) for the LWC.
- [`force-app/main/default/classes/FieldTransitionRequirementController.cls`](force-app/main/default/classes/FieldTransitionRequirementController.cls) — thin `@AuraEnabled` entry point the LWC calls.
- [`force-app/main/default/classes/FieldTransitionFrameworkTest.cls`](force-app/main/default/classes/FieldTransitionFrameworkTest.cls) — test coverage. Doesn't cover everything — see [Tests](#tests) below.
- [`force-app/main/default/lwc/fieldTransitionChecklist/`](force-app/main/default/lwc/fieldTransitionChecklist) — drop this on a record page to show pending requirements.
- [`force-app/main/default/objects/Field_Transition_Rule__mdt/`](force-app/main/default/objects/Field_Transition_Rule__mdt) and [`Transition_Condition__mdt/`](force-app/main/default/objects/Transition_Condition__mdt) — the two custom metadata types. This repo ships the types, fields, and layouts only — no records. Your rules and conditions are your org's own configuration; see [`docs/USAGE.md`](docs/USAGE.md) for how to create them.

## Custom metadata: `Field_Transition_Rule__mdt`

One record per governed transition (one field, one target value, optionally scoped to a specific starting value).

| Field | Type | Description |
|---|---|---|
| `Object_API_Name__c` | Text (required) | API name of the SObject this rule applies to, e.g. `Opportunity`. |
| `Field_API_Name__c` | Text (required) | API name of the field on that object this rule watches, e.g. `StageName`. |
| `To_Value__c` | Text (required) | The value the field must be changing **to** for this rule to apply. |
| `From_Value__c` | Text | The value the field must be changing **from**. Leave blank to match a transition from any value. |
| `Is_Active__c` | Checkbox | Must be `true` for the rule to be enforced at all. |
| `Order__c` | Number | Evaluation order relative to other active rules on the same object/field. |

## Custom metadata: `Transition_Condition__mdt`

One or more per rule. **Every** active condition on a rule must be satisfied for the transition to be allowed.

| Field | Type | Description |
|---|---|---|
| `Field_Transition_Rule__c` | Metadata Relationship (required) | The rule this condition belongs to. |
| `Condition_Type__c` | Picklist (required) | `Child Record Exists`, `All Matching Children Satisfy`, `Parent Field Criteria`, or `Parent Criteria If Child Exists`. See [`docs/USAGE.md`](docs/USAGE.md) for what each one does and when to use it. |
| `Child_Object_API_Name__c` | Text | API name of the child object to check. Used by every type except `Parent Field Criteria`. |
| `Child_Relationship_Field__c` | Text | API name of the lookup/master-detail field on the child that points back to the parent. Used by every type except `Parent Field Criteria`. |
| `Child_Filter_Criteria__c` | Long Text Area | A WHERE-clause fragment against the child object. Meaning depends on `Condition_Type__c` — see [`docs/USAGE.md`](docs/USAGE.md). |
| `Child_Required_Criteria__c` | Long Text Area | A WHERE-clause fragment every selected child must also match. Used only by `All Matching Children Satisfy`. |
| `Parent_Filter_Criteria__c` | Long Text Area | A single `Field Operator Value` comparison against the record being saved. Used by `Parent Field Criteria` and `Parent Criteria If Child Exists`. Full operator/type reference in [`docs/USAGE.md`](docs/USAGE.md). |
| `Message__c` | Text | What to show for this condition in the checklist LWC, instead of the record's name. |
| `Is_Active__c` | Checkbox | Must be `true` for the condition to be enforced at all. |

## Tests

`FieldTransitionFrameworkTest` calls `FieldTransitionValidator`, `FieldTransitionConditionEvaluator`, `FieldTransitionRequirementService`, and `FieldTransitionRequirementController` directly — it doesn't go through a trigger, because wiring this framework to an object's trigger is your own org's setup, not something this repo ships (see [Wiring it up](docs/USAGE.md#wiring-it-into-your-org) in the usage doc). It covers, among other things:

- Every scalar comparison type `Parent Field Criteria` supports (string, picklist, number, percent, currency, boolean, date, datetime — including the UTC/`Z` behavior) and the null-handling convention.
- All four condition types, backed by real child records.
- Bulk behavior: the query cost of validating many records stays flat instead of growing per record, and one misconfigured condition doesn't take down the others in the same batch.
- The read-only checklist service and its controller, including objects with no configured rules.

It does **not** cover everything, and it isn't meant to. Multi-select picklist and record-type comparisons, for example, exercise the exact same code paths already covered by the other operator tests, so they aren't duplicated here — but they also depend on fields/record types this repo has no way of guaranteeing exist in your org, so there's no dedicated test for them either. If your org configures rules using field types or scenarios this test class doesn't touch, that's on you to cover with your own tests, the same way it would be for any framework you install rather than write yourself.

## Deploy to an org

You need [VS Code with the Salesforce Extension Pack](https://developer.salesforce.com/tools/vscode/) and an authenticated org.

1. Clone this repo and open it in VS Code.
2. Authenticate to your target org (`SFDX: Authorize an Org`, or `sf org login web` from the CLI).
3. Right-click [`manifest/package.xml`](manifest/package.xml) and choose **SFDX: Deploy Source in Manifest to Org**.

That deploys the Apex classes, both custom metadata types with their fields and layouts, the custom labels, and the checklist LWC — everything except your own rules/conditions and the trigger that calls `FieldTransitionValidator`, both of which are yours to create. See [`docs/USAGE.md`](docs/USAGE.md) for both.

## Documentation

- [`docs/USAGE.md`](docs/USAGE.md) — wiring it into a trigger, creating rules and conditions, every operator and field type with worked examples (string, picklist, multi-select picklist, number/currency/percent, boolean, date, datetime), adding the checklist LWC to a page, and what to avoid.

## License

Released under the [MIT License](LICENSE).
