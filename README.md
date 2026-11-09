# Field Transition Framework

A metadata-driven Apex framework for Salesforce that blocks a field from changing to a configured value until a set of configurable conditions are met — checks against the record itself, against related child records, or both. Ships with a Lightning web component that shows a record's outstanding requirements before you even try to save.

[![Deploy to Salesforce](https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png)](https://githubsfdeploy.herokuapp.com?owner=geronimo-olivera&repo=Field-Transition-Framework&ref=master)

## Purpose

Stage-gating logic (an Opportunity can't move to a given stage until X, Y, Z are true) tends to end up hardcoded in validation rules or Apex, spread across the org, hard to see in one place and hard to change without a deploy. The goal of this framework is:

- **Configuration over code** — which field, which transition, and which conditions block it live in `Field_Transition_Rule__mdt` and `Transition_Condition__mdt` records. Adding, disabling, or changing a requirement doesn't require touching Apex.
- **Works on any object and any field** — nothing in the framework is specific to Opportunity/StageName or any other object. `Object_API_Name__c` and `Field_API_Name__c` are plain text.
- **Four ways to express a requirement** — a related child record must (or must not) exist, a field on the record itself must match a comparison, or a combination of both. See [`docs/USAGE.md`](docs/USAGE.md) for the full reference.
- **Bulk-safe** — validating a batch of records costs one query per distinct condition that batch actually needs, not one per record. A 1,000-record update used 10 queries in total.
- **SOQL semantics** — `Parent_Filter_Criteria__c` behaves like a SOQL `WHERE` clause, including blank fields, multi-select picklists, 15-character Ids and date literals, verified against real SOQL on 86 criteria.
- **Clear errors** — a blocked save names the field and lists exactly which requirements are missing.
- **Same answer for every user** — conditions are evaluated without sharing, so the checklist and the save always agree, whoever is looking.
- **A companion checklist, not just a blocker** — `fieldTransitionChecklist` is a Lightning web component you can drop on any record page. It shows every reachable next value for a governed field and which of its conditions are already met, before the user tries to save.

See [`docs/USAGE.md`](docs/USAGE.md) for how to configure a rule, every supported operator and field type with worked examples, and what to avoid.

## Contents

- [`force-app/main/default/classes/FieldTransitionValidator.cls`](force-app/main/default/classes/FieldTransitionValidator.cls) — call this from a trigger's `before update` (and `before insert`, for `Apply_On_Insert__c` rules) to block a transition. Bulk-safe.
- [`force-app/main/default/classes/FieldTransitionConditionEvaluator.cls`](force-app/main/default/classes/FieldTransitionConditionEvaluator.cls) — evaluates a single condition against a record. Shared by the validator and the checklist service; has no idea which one is calling it.
- [`force-app/main/default/classes/FieldTransitionMetadataService.cls`](force-app/main/default/classes/FieldTransitionMetadataService.cls) — read-only access to the two custom metadata types, and `validateConfiguration()` to find mistakes in them.
- [`force-app/main/default/classes/FieldTransitionRequirementService.cls`](force-app/main/default/classes/FieldTransitionRequirementService.cls) — builds the read-only checklist (never blocks anything) for the LWC.
- [`force-app/main/default/classes/FieldTransitionRequirementController.cls`](force-app/main/default/classes/FieldTransitionRequirementController.cls) — thin `@AuraEnabled` entry point the LWC calls.
- [`force-app/main/default/classes/FieldTransitionFrameworkTest.cls`](force-app/main/default/classes/FieldTransitionFrameworkTest.cls) — test coverage. Doesn't cover everything — see [Tests](#tests) below.
- [`force-app/main/default/lwc/fieldTransitionChecklist/`](force-app/main/default/lwc/fieldTransitionChecklist) — drop this on a record page to show pending requirements. Has Jest tests in `__tests__`.
- [`force-app/main/default/permissionsets/Field_Transition_Checklist.permissionset-meta.xml`](force-app/main/default/permissionsets/Field_Transition_Checklist.permissionset-meta.xml) — assign it to users who should see the checklist.
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
| `Apply_On_Insert__c` | Checkbox | Also check this rule when a record is created directly with `To_Value__c`. Needs a blank `From_Value__c` and a trigger that runs in `before insert`. |

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

**Apex:** `FieldTransitionFrameworkTest` has 18 tests and doesn't depend on your org's configuration: each test builds its rules and conditions in memory and passes them in through `FieldTransitionMetadataService`'s test overrides. They cover every operator and field type with SOQL's semantics, every date literal, all four condition types with real child records, 200 records in one validation, the insert rule, the error message, the checklist, a standard user, and every mistake `validateConfiguration()` reports. Coverage is 100% on the validator, the checklist service, the controller and the metadata service, and 94% on the evaluator (the multi-select branch needs a multi-select field, which standard objects don't have; its matching is tested directly). One test, `activeConfigurationInThisOrgIsValid`, checks **your** real rules on every deploy.

**LWC:** 7 Jest tests, 100% of the component's lines. Run them with `npm install` and `npm test`.

### Tested end to end

In a scratch org with three custom objects (projects, tasks and private reviews) and 11 rules with 24 conditions across Opportunity, Case, Lead, Account and those objects:

| Check | Result |
|---|---|
| 25 save scenarios across five objects, every condition type | All as expected, each block listing what's missing |
| Evaluator vs. real SOQL, 86 criteria on 26 records | Identical results |
| 1,000 records in one save | Correct for every record, 10 queries |
| Record created directly at a gated value (`Apply_On_Insert__c`) | Blocked when a requirement is missing |
| Standard user without access to a qualifying child record | The checklist (in Lightning) and the save both count it as met |

To run the Apex tests in a scratch org:

```bash
sf org create scratch --definition-file config/project-scratch-def.json --alias ftf --duration-days 1 --target-dev-hub <your-dev-hub>
sf project deploy start --manifest manifest/package.xml --target-org ftf
sf apex run test --target-org ftf --test-level RunLocalTests --code-coverage --wait 20
```

## Deploy to an org

### One click

[![Deploy to Salesforce](https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png)](https://githubsfdeploy.herokuapp.com?owner=geronimo-olivera&repo=Field-Transition-Framework&ref=master)

Click the button, choose production or sandbox, and log in to the org. The deploy runs through [GitHub Salesforce Deploy](https://github.com/afawcett/githubsfdeploy), a free open-source tool by Andrew Fawcett. Try it in a sandbox first: a production deploy also runs your org's Apex tests.

### From VS Code

You need [VS Code with the Salesforce Extension Pack](https://developer.salesforce.com/tools/vscode/) and an authenticated org.

1. Clone this repo and open it in VS Code.
2. Authenticate to your target org (`SFDX: Authorize an Org`, or `sf org login web` from the CLI).
3. Right-click [`manifest/package.xml`](manifest/package.xml) and choose **SFDX: Deploy Source in Manifest to Org**.

That deploys the Apex classes, both custom metadata types with their fields and layouts, the custom labels, the checklist LWC and its permission set — everything except your own rules/conditions and the trigger that calls `FieldTransitionValidator`, both of which are yours to create. See [`docs/USAGE.md`](docs/USAGE.md) for both.

## Documentation

- [`docs/USAGE.md`](docs/USAGE.md) — wiring it into a trigger, creating rules and conditions, every operator and field type with worked examples (string, picklist, multi-select picklist, number/currency/percent, boolean, date, datetime), adding the checklist LWC to a page, and what to avoid.

## License

Released under the [MIT License](LICENSE).
