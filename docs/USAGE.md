# Usage

## What this is for

A `Field_Transition_Rule__mdt` record says "field X on object Y can't change to value Z (optionally: from value W) unless every one of its conditions is met." Each rule has one or more `Transition_Condition__mdt` children, and **all** of them must pass. There's no OR between conditions on the same rule — if you need an either/or requirement, that's two separate rules with the same `To_Value__c` (and, if relevant, different `From_Value__c`), each with its own subset of conditions.

`FieldTransitionValidator` is what actually blocks a save — call it from a trigger. `FieldTransitionRequirementService` (behind the `fieldTransitionChecklist` LWC) reads the exact same configuration and evaluates it the exact same way, but only reports pass/fail — it never blocks anything, so you can drop it on a record page to show a user what's still missing before they try to save.

## Wiring it into your org

This repo ships the framework, not a trigger — whether you already have a trigger framework, want one trigger per object, or something else entirely is your call. Whatever you already have, call `FieldTransitionValidator.validateTransitions` from a `before update` context on the object(s) you're governing:

```apex
trigger OpportunityTrigger on Opportunity (before update) {
    FieldTransitionValidator.validateTransitions(Trigger.new, Trigger.oldMap);
}
```

There's also a single-record overload if you're calling it from somewhere that isn't natively bulk:

```apex
FieldTransitionValidator.validateTransitions(newOpportunity, oldOpportunity);
```

By default only `before update` matters — an `insert` has no "from" value to compare. But creating a record directly at the final value would skip every requirement, so a rule can opt in with **`Apply_On_Insert__c`**: then a record created with `To_Value__c` is checked too. That only applies to rules with a blank `From_Value__c`, and the trigger must also run in `before insert`:

```apex
trigger OpportunityTrigger on Opportunity (before insert, before update) {
    FieldTransitionValidator.validateTransitions(Trigger.new, Trigger.oldMap);
}
```

On insert, `Trigger.oldMap` is null and only `Apply_On_Insert__c` rules are checked. Child-record conditions can't be met on insert, since the record has no children yet: a `Child Record Exists` condition blocks it, and `All Matching Children Satisfy` passes.

When a save is blocked, the user sees the field's label, the value and what's missing, for example *Cannot change Stage to "Closed Won". Still missing: A Decision Maker contact role; An amount above zero.* Each requirement is its condition's `Message__c`, or its label when `Message__c` is blank. The text is the `Field_Transition_Blocked_Error` custom label, so it can be translated.

## Creating a rule

This repo ships the two custom metadata *types* — no rule or condition records, since those are your org's own configuration. Create them either way CMDT records normally get created:

- **Setup UI** — Setup → Custom Metadata Types → **Field Transition Rule** / **Transition Condition** → Manage Records → New.
- **Source** — add a `.md-meta.xml` file under `force-app/main/default/customMetadata/` and deploy it. For example, `Field_Transition_Rule.Prospecting_to_Qualification.md-meta.xml`:

  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <CustomMetadata xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://soap.sforce.com/2006/04/metadata">
      <label>Prospecting to Qualification</label>
      <protected>false</protected>
      <values><field>Object_API_Name__c</field><value xsi:type="xsd:string">Opportunity</value></values>
      <values><field>Field_API_Name__c</field><value xsi:type="xsd:string">StageName</value></values>
      <values><field>From_Value__c</field><value xsi:type="xsd:string">Prospecting</value></values>
      <values><field>To_Value__c</field><value xsi:type="xsd:string">Qualification</value></values>
      <values><field>Is_Active__c</field><value xsi:type="xsd:boolean">true</value></values>
      <values><field>Order__c</field><value xsi:type="xsd:double">10</value></values>
  </CustomMetadata>
  ```

Either way, the fields are:

1. `Object_API_Name__c` — the object, e.g. `Opportunity`.
2. `Field_API_Name__c` — the field being watched, e.g. `StageName`.
3. `To_Value__c` — the value that triggers this rule, e.g. `Closed Won`.
4. `From_Value__c` — optional. Leave it blank if the rule should apply no matter what the field's previous value was; set it if the rule is specific to one transition, e.g. `Negotiation/Review`.
5. `Is_Active__c` — `true`, or the rule is silently ignored.
6. `Order__c` — the order rules are evaluated in when more than one is active for the same object/field. It does **not** make rules mutually exclusive: if two active rules both match the same transition (e.g. one scoped to `From_Value__c = Prospecting` and another left blank so it matches from anywhere), both apply, and their conditions are effectively ANDed together — every matching rule has to pass independently, it isn't "first match wins."

A rule with no active conditions attached never blocks anything — it's allowed unconditionally the moment it matches.

## Creating conditions

Each condition belongs to one rule (`Field_Transition_Rule__c`) and has a `Condition_Type__c` that determines which of the other fields apply. Set `Message__c` on every condition you want shown in the checklist LWC with a human-readable explanation (e.g. "At least one Decision Maker contact role is required") — if you leave it blank, the checklist falls back to showing the condition record's own label instead.

### Child Record Exists

Passes if at least one child record matches `Child_Filter_Criteria__c`.

```
Child_Object_API_Name__c:    OpportunityContactRole
Child_Relationship_Field__c: OpportunityId
Child_Filter_Criteria__c:    Role = 'Decision Maker'
```

"At least one Contact Role with Role = Decision Maker must exist." Leave `Child_Filter_Criteria__c` blank to require any child record of that type at all, regardless of its fields.

### All Matching Children Satisfy

Selects children with `Child_Filter_Criteria__c` (blank selects every child of that type), and passes only if **all** of them also match `Child_Required_Criteria__c`. Vacuously true if none are selected.

```
Child_Object_API_Name__c:    OpportunityContactRole
Child_Relationship_Field__c: OpportunityId
Child_Filter_Criteria__c:    Role = 'Decision Maker'
Child_Required_Criteria__c:  IsPrimary = true
```

"Of all the Decision Maker contact roles, every one of them must be marked Primary." If there are two Decision Makers and only one is Primary, this fails — that's the difference from `Child Record Exists`, which would already be satisfied by the first one existing at all.

### Parent Field Criteria

Evaluates a single comparison against the record being saved — see [Parent Filter Criteria syntax](#parent-filter-criteria-syntax) below for the full operator and field-type reference.

```
Parent_Filter_Criteria__c: Amount != null
```

### Parent Criteria If Child Exists

An IF-THEN: if a child matching `Child_Filter_Criteria__c` exists, the parent must also match `Parent_Filter_Criteria__c`. Vacuously true if no such child exists at all — the requirement simply doesn't apply.

```
Child_Object_API_Name__c:    OpportunityContactRole
Child_Relationship_Field__c: OpportunityId
Child_Filter_Criteria__c:    Role = 'Decision Maker'
Parent_Filter_Criteria__c:   NextStep != null
```

"If this Opportunity has a Decision Maker contact role, NextStep must be populated. If it has no Decision Maker at all, this condition doesn't apply." That last part is the important one to get right when configuring this type — it's not "block the transition unless NextStep is set," it's conditional on the child existing at all.

## Parent Filter Criteria syntax

One comparison per condition record, always `FieldApiName OPERATOR Value` — no `AND`/`OR`. If you need multiple comparisons, add another condition record; every active condition on a rule is ANDed together anyway.

| Operator | Meaning |
|---|---|
| `=`, `!=` | Equals / not equals. Works for every field type below. |
| `>`, `>=`, `<`, `<=` | Ordering. Numbers and dates/datetimes only. |
| `LIKE` | SOQL-style pattern match, `%` for any run of characters, `_` for exactly one, case-insensitive. |
| `IN`, `NOT IN` | Match against a parenthesized list, e.g. `('A', 'B')`. |
| `INCLUDES`, `EXCLUDES` | Multi-select picklists only. |

`Amount = null` and `Amount != null` test for blank explicitly — see [Null handling](#null-handling) below for what every other operator does with a blank field.

### String

```
Name = 'Acme Corp'
Name != 'Acme Corp'
Name LIKE 'Acme%'
Name LIKE '%Corp'
Name LIKE 'Ac_e Corp'
```

### Picklist

Same as string, plus list membership:

```
Type = 'New Customer'
Type IN ('New Customer', 'Existing Customer - Upgrade')
LeadSource NOT IN ('Purchased List', 'Other')
```

### Multi-select Picklist

Multi-select picklists store their selected values separated by `;`. The operators follow SOQL exactly:

```
Interests__c = 'Golf'
Interests__c = 'Golf;Tennis'
Interests__c != 'Golf'
Interests__c IN ('Golf', 'Golf;Tennis')
Interests__c INCLUDES ('Golf')
Interests__c INCLUDES ('Golf;Tennis')
Interests__c INCLUDES ('Golf', 'Tennis')
Interests__c EXCLUDES ('Skiing')
```

- `=` means **exactly** that set of selections, in any order: `= 'Golf'` matches a record with only Golf selected, not one with Golf and Tennis. `!=` is the opposite.
- `IN` matches if the field is exactly one of the listed sets. `NOT IN` is the opposite.
- `INCLUDES ('Golf;Tennis')` — one quoted group with a `;` inside — means **both** Golf AND Tennis must be selected, among possibly others.
- `INCLUDES ('Golf', 'Tennis')` — two separate quoted groups — means Golf **or** Tennis (or both) is enough.
- You can combine both: `INCLUDES ('Golf;Tennis', 'Skiing')` passes if Golf and Tennis are both selected, or Skiing is.
- `EXCLUDES` is the negation of the same grouping logic.
- A blank multi-select satisfies `= null`, `!=`, `NOT IN` and `EXCLUDES`, and nothing else.

### Number, Currency, Percent

All three compare as decimals — there's no meaningful difference in how the framework evaluates them:

```
Amount > 10000
Amount >= 5000
Probability >= 75
NumberOfEmployees < 1000
Amount = 12345.67
```

In a multi-currency org, `Amount` comparisons are against the record's raw stored amount, in whatever currency that record is in — there's no conversion to a corporate/reference currency. A rule like `Amount > 10000` means something different for a USD Opportunity than a JPY one; scope separate rules per currency if that matters for you.

### Boolean

```
IsPrivate = true
IsPrimary != false
```

Only `=` and `!=` are supported for booleans.

### Date

Either an absolute `YYYY-MM-DD` value or a SOQL date literal:

```
CloseDate = 2026-01-01
CloseDate > 2026-01-01
CloseDate = TODAY
CloseDate = THIS_WEEK
CloseDate >= LAST_N_DAYS:30
```

Supported literals: `TODAY`, `YESTERDAY`, `TOMORROW`, `THIS_WEEK`, `LAST_WEEK`, `NEXT_WEEK`, `THIS_MONTH`, `LAST_MONTH`, `NEXT_MONTH`, `THIS_QUARTER`, `LAST_QUARTER`, `NEXT_QUARTER`, `THIS_YEAR`, `LAST_YEAR`, `NEXT_YEAR`, and the `:n`-suffixed family — `LAST_N_DAYS:n`, `NEXT_N_DAYS:n`, `N_DAYS_AGO:n`, `LAST_N_WEEKS:n`, `NEXT_N_WEEKS:n`, `N_WEEKS_AGO:n`, `LAST_N_MONTHS:n`, `NEXT_N_MONTHS:n`, `N_MONTHS_AGO:n`, `LAST_N_QUARTERS:n`, `NEXT_N_QUARTERS:n`, `N_QUARTERS_AGO:n`, `LAST_N_YEARS:n`, `NEXT_N_YEARS:n`, `N_YEARS_AGO:n`. Weeks start on the running user's locale's first day of the week, as in SOQL (Sunday for en_US, Monday for many other locales); quarters are calendar quarters. The boundaries match SOQL: `LAST_N_DAYS:n` includes today, `NEXT_N_DAYS:n` starts tomorrow, and the `N_WEEKS`, `N_MONTHS`, `N_QUARTERS` and `N_YEARS` literals cover whole periods before or after the current one, leaving the current week, month, quarter or year out. **Fiscal-year literals aren't supported** — they depend on org-specific fiscal year settings this framework has no visibility into.

Every literal supports all six operators, with SOQL's meaning: `=` is within the range, `!=` outside it, `>` after its last day, `>=` from its first day, `<` before its first day, and `<=` up to its last day. A single-day literal such as `TODAY` is a range of one day.

### Date/Time

Same literals as Date work here too (they widen to midnight–end-of-day on the field's date component). For an absolute value, you additionally get to choose how the time is anchored:

```
CreatedDate > 2026-01-01T09:00:00
CreatedDate > 2026-01-01 09:00:00
CreatedDate > 2026-01-01T09:00:00Z
```

**Without a trailing `Z`, the value is interpreted in the timezone of whoever saves the record** — the same way `Datetime.valueOf()` behaves in Apex. That's convenient for a single-timezone team, but means the exact same criteria string can produce different results for two users in different timezones, or for a scheduled/batch job running under a different user than the one who configured the rule. **Add a trailing `Z`** (e.g. `2026-01-01T09:00:00Z`) to pin an exact, unambiguous UTC instant — recommended for anything where the moment matters more than "business hours where I am."

### Null handling

Blank fields behave as in SOQL:

- `Amount = null` and `Amount != null` test for blank explicitly.
- `!=`, `NOT IN` and `EXCLUDES` **pass** on a blank field: a blank Amount is not equal to 100, and a blank Type is not in ('A', 'B').
- Every other operator (`=` with a value, `>`, `<`, `IN`, `LIKE`, `INCLUDES`) **fails** on a blank field.

### Other details that follow SOQL

- Text comparisons with `=`, `!=`, `IN` and `LIKE` ignore case.
- Id and lookup fields accept the 15- or the 18-character Id: `OwnerId = '005xx000001Sv6A'` matches.
- In `LIKE`, a backslash makes the next character literal: `Code__c LIKE 'PRJ\_%'` matches a real underscore.
- Spaces around the operator are optional: `Amount>=100` works.

These rules were verified by comparing the evaluator with real SOQL queries on the same records, for 86 criteria covering every field type, operator and date literal.

## Adding the checklist LWC to a record page

`fieldTransitionChecklist` targets `lightning__RecordPage` and isn't restricted to any particular object — it works on any object that has active `Field_Transition_Rule__mdt` records configured for it, and shows nothing (a graceful empty state) for one that doesn't.

1. Open the record page in Lightning App Builder.
2. Drag **Transition Checklist** onto the page — anywhere a component fits, including inside a Tabs component.
3. Save and activate.

It groups its output by governed field, shows every reachable next value from the record's current state, and marks each condition as met or not yet met. It's read-only — it never blocks a save, it only reports.

Users need the **Field Transition Checklist** permission set to use it. It grants access to the Apex controller and read access to the two rule metadata types; without it, the component shows an access error. Blocking saves needs no permission at all.

The checklist reloads by itself when the record is saved, and has a Refresh button for changes to related records.

The checklist and the save always agree. Conditions are evaluated without sharing, so a requirement met by a child record the user can't see counts as met in both places. Only pass/fail and the configured messages are shown, never the child records themselves.

The checklist shows the same thing to every user who can see the record and the page it's on — it doesn't hide a condition or its `Message__c` based on the viewer's field-level security. That's a deliberate default (everyone sees the same requirements), not an oversight; if your org needs the checklist itself restricted by FLS, that's a change to make in `FieldTransitionRequirementService` before deploying it.

## Checking your configuration

`FieldTransitionMetadataService.validateConfiguration()` checks every active rule and condition and returns one readable problem per mistake: an object or field that doesn't exist, a `From_Value__c` or `To_Value__c` that isn't an active picklist value, an unknown condition type, a missing or invalid `Parent_Filter_Criteria__c`, a child object or relationship field that doesn't exist or doesn't point to the rule's object, and child criteria that aren't valid SOQL. The test `activeConfigurationInThisOrgIsValid` runs it on every deploy, so a typo fails the deploy instead of blocking users.

## API version

The classes use API 66.0 on purpose. In a scratch org on API 67.0, a query run for a standard user stopped returning records that user can't see, even in a `without sharing` class and with `WITH SYSTEM_MODE`; on API 62.0 to 66.0 it returned them. That would make a rule's answer depend on who saves the record. Keep the classes on 66.0 until that behavior is documented.

## What you should NOT do

- Don't call `FieldTransitionValidator` from anywhere except `before update`, or `before insert` for `Apply_On_Insert__c` rules (or something that mimics them, like a batch that supplies its own before/after pair). It compares old vs. new field values.
- Don't combine multiple comparisons in one `Parent_Filter_Criteria__c` with `AND`/`OR` — it's not supported, and the parser will reject it. Use another condition record instead; every active condition on a rule is already ANDed.
- Don't rely on a field reference in `Field_API_Name__c`, `Child_Object_API_Name__c`, or a criteria string surviving a later field rename or deletion without you noticing — a rule or condition that references something that no longer exists is skipped/treated as unsatisfied and logged via `System.debug(LoggingLevel.ERROR, ...)`, rather than throwing and taking down every other save on that object. Check debug logs after any schema change touching a field these records reference.
- Don't expect `>`, `<`, `IN` or `LIKE` to treat a blank field as a pass, or `!=` and `NOT IN` to treat it as a failure — see [Null handling](#null-handling) above.
- Don't assume an absolute datetime literal means the same instant for every user — add `Z` if you need it to.
- Don't assume unlimited headroom for rules and conditions — Custom Metadata Type storage is capped org-wide (10 MB across every custom metadata type in the org, not just this framework's), and each Long Text Area field on a condition counts as a flat 255 bytes toward that regardless of how much text it actually holds. That's room for many thousands of conditions in practice, but it's not infinite, and it's shared with whatever other CMDT your org uses.
