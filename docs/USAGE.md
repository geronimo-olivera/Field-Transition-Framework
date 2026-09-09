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

Only `before update` matters — an `insert` has no "from" value to compare, so a rule with a blank `From_Value__c` would otherwise fire on every insert that happens to land on `To_Value__c`, which isn't a transition at all.

## Creating a rule

1. New `Field_Transition_Rule__mdt` record.
2. `Object_API_Name__c` — the object, e.g. `Opportunity`.
3. `Field_API_Name__c` — the field being watched, e.g. `StageName`.
4. `To_Value__c` — the value that triggers this rule, e.g. `Closed Won`.
5. `From_Value__c` — optional. Leave it blank if the rule should apply no matter what the field's previous value was; set it if the rule is specific to one transition, e.g. `Negotiation/Review`.
6. `Is_Active__c` — `true`, or the rule is silently ignored.
7. `Order__c` — only matters if more than one active rule targets the same object/field; doesn't affect whether a rule blocks, just the order rules are evaluated in.

A rule with no active conditions attached never blocks anything — it's allowed unconditionally the moment it matches.

## Creating conditions

Each condition belongs to one rule (`Field_Transition_Rule__c`) and has a `Condition_Type__c` that determines which of the other fields apply.

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

`Field.Amount = null` and `Field != null` are the only way to test for blank — see [Null handling](#null-handling) below for what every other operator does with a blank field.

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

Multi-select picklists store their selected values internally separated by `;`. `=`/`!=` test for a single exact value being selected (among possibly others); `INCLUDES`/`EXCLUDES` test for combinations, matching real SOQL semantics:

```
Interests__c = 'Golf'
Interests__c != 'Golf'
Interests__c INCLUDES ('Golf')
Interests__c INCLUDES ('Golf;Tennis')
Interests__c INCLUDES ('Golf', 'Tennis')
Interests__c EXCLUDES ('Skiing')
```

- `INCLUDES ('Golf;Tennis')` — one quoted group with a `;` inside — means **both** Golf AND Tennis must be selected.
- `INCLUDES ('Golf', 'Tennis')` — two separate quoted groups — means Golf **or** Tennis (or both) is enough; any one group fully matching is a pass.
- You can combine both inside the same list: `INCLUDES ('Golf;Tennis', 'Skiing')` passes if either (Golf and Tennis are both selected) or (Skiing is selected).
- `EXCLUDES` is the negation of the same grouping logic — `EXCLUDES ('Skiing')` passes if Skiing is not among the selected values.
- On a completely blank multi-select field, every `EXCLUDES` comparison passes (there's nothing selected to exclude) and every `INCLUDES`/`=` comparison fails.
- `IN`/`NOT IN` also work on multi-select fields and behave like `INCLUDES`/`EXCLUDES` with only single-value (no `;`) groups — match if any listed value is selected.

### Number, Currency, Percent

All three compare as decimals — there's no meaningful difference in how the framework evaluates them:

```
Amount > 10000
Amount >= 5000
Probability >= 75
NumberOfEmployees < 1000
Amount = 12345.67
```

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

Supported literals: `TODAY`, `YESTERDAY`, `TOMORROW`, `THIS_WEEK`, `LAST_WEEK`, `NEXT_WEEK`, `THIS_MONTH`, `LAST_MONTH`, `NEXT_MONTH`, `THIS_QUARTER`, `LAST_QUARTER`, `NEXT_QUARTER`, `THIS_YEAR`, `LAST_YEAR`, `NEXT_YEAR`, and the `:n`-suffixed family — `LAST_N_DAYS:n`, `NEXT_N_DAYS:n`, `N_DAYS_AGO:n`, `LAST_N_WEEKS:n`, `NEXT_N_WEEKS:n`, `N_WEEKS_AGO:n`, `LAST_N_MONTHS:n`, `NEXT_N_MONTHS:n`, `N_MONTHS_AGO:n`, `LAST_N_QUARTERS:n`, `NEXT_N_QUARTERS:n`, `N_QUARTERS_AGO:n`, `LAST_N_YEARS:n`, `NEXT_N_YEARS:n`, `N_YEARS_AGO:n`. Weeks start on Sunday; quarters are calendar quarters. **Fiscal-year literals aren't supported** — they depend on org-specific fiscal year settings this framework has no visibility into.

Single-day literals (`TODAY`, `N_DAYS_AGO:n`, etc.) support all six operators. Range literals (`THIS_WEEK`, `LAST_MONTH`, `THIS_QUARTER`, etc.) only support `=` (falls within the range) and `!=` (falls outside it) — `>`/`<` against a range doesn't have an unambiguous meaning, so it throws rather than guessing.

### Date/Time

Same literals as Date work here too (they widen to midnight–end-of-day on the field's date component). For an absolute value, you additionally get to choose how the time is anchored:

```
CreatedDate > 2026-01-01T09:00:00
CreatedDate > 2026-01-01 09:00:00
CreatedDate > 2026-01-01T09:00:00Z
```

**Without a trailing `Z`, the value is interpreted in the timezone of whoever saves the record** — the same way `Datetime.valueOf()` behaves in Apex. That's convenient for a single-timezone team, but means the exact same criteria string can produce different results for two users in different timezones, or for a scheduled/batch job running under a different user than the one who configured the rule. **Add a trailing `Z`** (e.g. `2026-01-01T09:00:00Z`) to pin an exact, unambiguous UTC instant — recommended for anything where the moment matters more than "business hours where I am."

### Null handling

`Amount = null` and `Amount != null` are the explicit way to test for blank. Every other operator (`>`, `<`, `LIKE`, `IN`, `NOT IN`, etc.) treats a blank field as **not satisfying the comparison**, full stop — `Amount > 100` on a blank Amount is `false`, not an error and not vacuously true. This is deliberately consistent across every operator, including `NOT IN`, even though a strict SQL reading might expect `NOT IN` to treat a blank field as automatically matching. If you want "blank is fine, but if it's set it must satisfy X," write two conditions: one `Field = null`... no — since conditions are ANDed, not ORed, that specific "blank OR matches X" shape isn't expressible as two `Parent Field Criteria` conditions on the same rule. Model it as two separate rules instead (one for each acceptable case), or reconsider whether the field should be required in the first place.

The only exception is multi-select picklists, where a blank field is treated as an empty set: every `EXCLUDES` passes, every `INCLUDES`/`=` fails — see [Multi-select Picklist](#multi-select-picklist) above.

## Adding the checklist LWC to a record page

`fieldTransitionChecklist` targets `lightning__RecordPage` and isn't restricted to any particular object — it works on any object that has active `Field_Transition_Rule__mdt` records configured for it, and shows nothing (a graceful empty state) for one that doesn't.

1. Open the record page in Lightning App Builder.
2. Drag **Transition Checklist** onto the page — anywhere a component fits, including inside a Tabs component.
3. Save and activate.

It groups its output by governed field, shows every reachable next value from the record's current state, and marks each condition as met or not yet met. It's read-only — it never blocks a save, it only reports.

## What you should NOT do

- Don't call `FieldTransitionValidator` from anywhere except a `before update` context (or something that mimics one, like a batch that supplies its own before/after pair). It compares old vs. new field values; without a genuine "before" state it can't tell what's actually transitioning.
- Don't combine multiple comparisons in one `Parent_Filter_Criteria__c` with `AND`/`OR` — it's not supported, and the parser will reject it. Use another condition record instead; every active condition on a rule is already ANDed.
- Don't rely on a field reference in `Field_API_Name__c`, `Child_Object_API_Name__c`, or a criteria string surviving a later field rename or deletion without you noticing — a rule or condition that references something that no longer exists is skipped/treated as unsatisfied and logged via `System.debug(LoggingLevel.ERROR, ...)`, rather than throwing and taking down every other save on that object. Check debug logs after any schema change touching a field these records reference.
- Don't expect `!=`/`NOT IN`/`>` to treat a blank field as a pass — see [Null handling](#null-handling) above.
- Don't assume an absolute datetime literal means the same instant for every user — add `Z` if you need it to.
