/**
 * File Name   :	FieldTransitionFrameworkTest.cls
 * Description :	Tests every part of the framework against rules and conditions built in memory and passed in
 *                  through FieldTransitionMetadataService's test overrides, so it passes in any org whatever its
 *                  configuration. activeConfigurationInThisOrgIsValid is the exception: it checks the org's real
 *                  rules, so a typo in a rule fails the deploy.
 **/
@IsTest
private class FieldTransitionFrameworkTest {

    private static Integer sequence = 0;

    // ---------- helpers

    private static Id fakeId(Schema.SObjectType objectType) {
        sequence++;
        return Id.valueOf(objectType.getDescribe().getKeyPrefix() + String.valueOf(sequence).leftPad(12, '0'));
    }

    private static Field_Transition_Rule__mdt rule(String objectName, String fieldName, String fromValue, String toValue) {
        return new Field_Transition_Rule__mdt(
            Id = fakeId(Field_Transition_Rule__mdt.SObjectType),
            DeveloperName = 'Rule_' + sequence,
            MasterLabel = 'Rule ' + sequence,
            Object_API_Name__c = objectName,
            Field_API_Name__c = fieldName,
            From_Value__c = fromValue,
            To_Value__c = toValue,
            Is_Active__c = true,
            Order__c = sequence,
            Apply_On_Insert__c = false
        );
    }

    private static Transition_Condition__mdt condition(Field_Transition_Rule__mdt parentRule, String conditionType, String message) {
        return new Transition_Condition__mdt(
            Id = fakeId(Transition_Condition__mdt.SObjectType),
            DeveloperName = 'Condition_' + sequence,
            MasterLabel = 'Condition ' + sequence,
            Field_Transition_Rule__c = parentRule == null ? null : parentRule.Id,
            Condition_Type__c = conditionType,
            Message__c = message,
            Is_Active__c = true
        );
    }

    private static Transition_Condition__mdt parentCriteria(Field_Transition_Rule__mdt parentRule, String criteria, String message) {
        Transition_Condition__mdt c = condition(parentRule, FieldTransitionConditionEvaluator.CONDITION_TYPE_PARENT_FIELD_CRITERIA, message);
        c.Parent_Filter_Criteria__c = criteria;
        return c;
    }

    private static Transition_Condition__mdt childCondition(Field_Transition_Rule__mdt parentRule, String conditionType, String childObject, String relationshipField, String filter, String required, String message) {
        Transition_Condition__mdt c = condition(parentRule, conditionType, message);
        c.Child_Object_API_Name__c = childObject;
        c.Child_Relationship_Field__c = relationshipField;
        c.Child_Filter_Criteria__c = filter;
        c.Child_Required_Criteria__c = required;
        return c;
    }

    private static void useConfiguration(List<Field_Transition_Rule__mdt> rules, List<Transition_Condition__mdt> conditions) {
        FieldTransitionMetadataService.rulesOverride = rules;
        FieldTransitionMetadataService.conditionsOverride = conditions;
    }

    private static Boolean matches(SObject record, String criteria) {
        return FieldTransitionConditionEvaluator.evaluate(parentCriteria(null, criteria, null), record);
    }

    private static String errorOf(SObject record, String criteria) {
        try {
            matches(record, criteria);
            return null;
        } catch (FieldTransitionConditionEvaluator.FieldTransitionValidatorException ex) {
            return ex.getMessage();
        }
    }

    private static User createStandardUser() {
        List<Profile> profiles = [
            SELECT Id, Name FROM Profile
            WHERE UserLicense.Name = 'Salesforce' AND PermissionsModifyAllData = false
            AND PermissionsViewAllData = false AND PermissionsCustomizeApplication = false
            ORDER BY Name
        ];
        Profile chosen = profiles[0];
        for (Profile candidate : profiles) {
            if (candidate.Name == 'Standard User' || candidate.Name == 'Usuario estándar') { chosen = candidate; break; }
        }
        String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User user = new User(
            ProfileId = chosen.Id, FirstName = 'Standard', LastName = 'Tester', Alias = 'stdtst',
            Email = 'standard.tester@example.com', Username = 'standard.tester.' + unique + '@example.com',
            TimeZoneSidKey = 'America/Montevideo', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        insert user;
        return user;
    }

    // ---------- Parent Field Criteria

    @IsTest
    static void textPicklistNumberBooleanAndLookupComparisons() {
        Id ownerId = UserInfo.getUserId();
        Opportunity opp = new Opportunity(Name = 'Acme Corp', Type = 'New Customer', Probability = 75, Amount = 12345.67, IsPrivate = true, CloseDate = Date.today(), OwnerId = ownerId);

        Assert.isTrue(matches(opp, 'Name = \'Acme Corp\''), 'text =');
        Assert.isTrue(matches(opp, 'Name = \'acme corp\''), 'text = ignores case, as SOQL does');
        Assert.isTrue(matches(opp, 'Name != \'Other\''), 'text !=');
        Assert.isTrue(matches(opp, 'Name LIKE \'Acme%\''), 'LIKE with %');
        Assert.isTrue(matches(opp, 'Name LIKE \'acme _orp\''), 'LIKE with _ ignores case');
        Assert.isFalse(matches(opp, 'Name LIKE \'Acme\''), 'LIKE without a wildcard needs the whole value');
        Assert.isTrue(matches(opp, 'Type IN (\'New Customer\', \'Existing Customer - Upgrade\')'), 'picklist IN');
        Assert.isTrue(matches(opp, 'Type NOT IN (\'Existing Customer - Upgrade\')'), 'picklist NOT IN');
        Assert.isTrue(matches(opp, 'Probability >= 75'), 'percent >=');
        Assert.isTrue(matches(opp, 'Amount > 10000'), 'currency >');
        Assert.isTrue(matches(opp, 'Amount = 12345.67'), 'currency exact decimal');
        Assert.isTrue(matches(opp, 'Amount IN (1, 12345.67)'), 'number IN');
        Assert.isTrue(matches(opp, 'Amount NOT IN (1, 2)'), 'number NOT IN');
        Assert.isTrue(matches(opp, 'Amount < 20000') && matches(opp, 'Amount <= 12345.67') && matches(opp, 'Amount != 1'), 'number <, <=, !=');
        Assert.isTrue(matches(opp, 'IsPrivate = true') && matches(opp, 'IsPrivate != false'), 'boolean = and !=');
        Assert.isTrue(matches(opp, 'OwnerId = \'' + ownerId + '\''), 'lookup with an 18-character Id');
        Assert.isTrue(matches(opp, 'OwnerId = \'' + String.valueOf(ownerId).left(15) + '\''), 'lookup with a 15-character Id, as SOQL accepts');
        Assert.isTrue(matches(opp, 'OwnerId IN (\'' + String.valueOf(ownerId).left(15) + '\')'), 'lookup IN with a 15-character Id');
        Assert.isFalse(matches(opp, 'OwnerId = \'not-an-id\''), 'a value that is not an Id never matches');

        Event ev = new Event(StartDateTime = Datetime.newInstanceGmt(2026, 1, 1, 9, 0, 0), DurationInMinutes = 30);
        Assert.isTrue(matches(ev, 'DurationInMinutes >= 15') && matches(ev, 'DurationInMinutes < 60'), 'integer fields compare as numbers');
        Assert.isTrue(matches(ev, 'DurationInMinutes IN (30, 60)'), 'integer IN');
    }

    @IsTest
    static void operatorsWithoutSpacesAreParsed() {
        Opportunity opp = new Opportunity(Amount = 100, Probability = 50);

        Assert.isTrue(matches(opp, 'Amount>=100'), '>= without spaces');
        Assert.isTrue(matches(opp, 'Amount<=100'), '<= without spaces');
        Assert.isTrue(matches(opp, 'Amount!=5'), '!= without spaces');
        Assert.isFalse(matches(opp, 'Probability>50'), '> without spaces');
        Assert.isTrue(matches(opp, 'Probability=50'), '= without spaces');
    }

    @IsTest
    static void blankFieldsFollowSoql() {
        Opportunity blank = new Opportunity(Amount = null, LeadSource = null, Name = null);

        Assert.isTrue(matches(blank, 'Amount = null'), '= null on a blank field');
        Assert.isFalse(matches(blank, 'Amount != null'), '!= null on a blank field');
        Assert.isTrue(matches(blank, 'Amount != 100'), 'a blank field is not equal to a value');
        Assert.isTrue(matches(blank, 'LeadSource NOT IN (\'Web\')'), 'a blank field is not in a list');
        Assert.isFalse(matches(blank, 'Amount > 100') || matches(blank, 'Amount < 100'), 'ordering never matches a blank field');
        Assert.isFalse(matches(blank, 'LeadSource IN (\'Web\')'), 'IN never matches a blank field');
        Assert.isFalse(matches(blank, 'Name LIKE \'%\''), 'LIKE never matches a blank field');
        Assert.isFalse(matches(blank, 'Name = \'x\''), '= never matches a blank field');
    }

    @IsTest
    static void multiSelectPicklistsFollowSoql() {
        Schema.SObjectField multiField = findMultiSelectField(Account.SObjectType);
        if (multiField == null) { return; }
        String fieldName = multiField.getDescribe().getName();
        List<Schema.PicklistEntry> entries = multiField.getDescribe().getPicklistValues();
        String a = entries[0].getValue();
        String b = entries[1].getValue();
        Account account = new Account(Name = 'Multi');
        account.put(multiField, a + ';' + b);

        Assert.isTrue(matches(account, fieldName + ' = \'' + b + ';' + a + '\''), '= is the same set of selections, in any order');
        Assert.isFalse(matches(account, fieldName + ' = \'' + a + '\''), '= does not match a subset');
        Assert.isTrue(matches(account, fieldName + ' != \'' + a + '\''), '!= is a different set');
        Assert.isTrue(matches(account, fieldName + ' IN (\'' + a + '\', \'' + a + ';' + b + '\')'), 'IN matches one exact set in the list');
        Assert.isFalse(matches(account, fieldName + ' IN (\'' + a + '\')'), 'IN does not match a subset');
        Assert.isTrue(matches(account, fieldName + ' INCLUDES (\'' + a + '\')'), 'INCLUDES one value');
        Assert.isTrue(matches(account, fieldName + ' INCLUDES (\'' + a + ';' + b + '\')'), 'INCLUDES both values (AND inside a group)');
        Assert.isFalse(matches(account, fieldName + ' EXCLUDES (\'' + b + '\')'), 'EXCLUDES a selected value');

        Account empty = new Account(Name = 'Empty');
        Assert.isTrue(matches(empty, fieldName + ' EXCLUDES (\'' + a + '\')'), 'an empty multi-select excludes everything');
        Assert.isFalse(matches(empty, fieldName + ' INCLUDES (\'' + a + '\')'), 'an empty multi-select includes nothing');
        Assert.isTrue(matches(empty, fieldName + ' = null'), 'an empty multi-select is null');
        Assert.isNotNull(errorOf(account, fieldName + ' > \'' + a + '\''), 'ordering is not supported on a multi-select');
        Assert.isNotNull(errorOf(account, fieldName + ' = ' + a), 'multi-select values must be quoted');
        Assert.isNotNull(errorOf(account, fieldName + ' INCLUDES (' + a + ')'), 'INCLUDES values must be quoted');
    }

    @IsTest
    static void multiSelectMatchingWorksWithoutAField() {
        // Standard objects have no multi-select picklist, so the matching itself is also tested directly.
        Assert.isTrue(FieldTransitionConditionEvaluator.multiPicklistEquals('A;B', 'b; a'), 'same set, any order and case');
        Assert.isFalse(FieldTransitionConditionEvaluator.multiPicklistEquals('A;B', 'A'), 'a subset is not equal');
        Assert.isTrue(FieldTransitionConditionEvaluator.multiPicklistEquals(null, ''), 'two empty values are equal');
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluateIncludesClause('A;B;C', '(\'A;C\', \'D\')', 'x'), 'one group fully included');
        Assert.isFalse(FieldTransitionConditionEvaluator.evaluateIncludesClause('A;B', '(\'A;D\')', 'x'), 'a group only partly included');
        Assert.isFalse(FieldTransitionConditionEvaluator.evaluateIncludesClause(null, '(\'A\')', 'x'), 'an empty value includes nothing');
    }

    private static Schema.SObjectField findMultiSelectField(Schema.SObjectType objectType) {
        for (Schema.SObjectField field : objectType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (describe.getType() == Schema.DisplayType.MULTIPICKLIST && describe.isUpdateable() && describe.getPicklistValues().size() >= 2) {
                return field;
            }
        }
        return null;
    }

    @IsTest
    static void likeSupportsEscapedWildcards() {
        Opportunity literal = new Opportunity(Name = 'PRJ_1 (100%)');
        Opportunity other = new Opportunity(Name = 'PRJX1 (100x)');

        Assert.isTrue(matches(literal, 'Name LIKE \'PRJ\\_1%\''), 'an escaped underscore matches only an underscore');
        Assert.isFalse(matches(other, 'Name LIKE \'PRJ\\_1%\''), 'and not any other character');
        Assert.isTrue(matches(literal, 'Name LIKE \'%100\\%)\''), 'an escaped percent matches only a percent sign');
        Assert.isTrue(matches(literal, 'Name LIKE \'PRJ_1 (%\''), 'regex characters in the pattern are taken literally');
    }

    @IsTest
    static void datesAndDateLiterals() {
        Date today = Date.today();
        Date weekStart = today.toStartOfWeek();
        Opportunity opp = new Opportunity(CloseDate = today);

        Assert.isTrue(matches(opp, 'CloseDate = TODAY') && matches(opp, 'CloseDate = ' + String.valueOf(today)), 'TODAY and an absolute date');
        Assert.isTrue(matches(opp, 'CloseDate > YESTERDAY') && matches(opp, 'CloseDate < TOMORROW'), 'single-day literals with > and <');
        Assert.isTrue(matches(opp, 'CloseDate = THIS_WEEK'), 'today is in THIS_WEEK');
        Assert.isTrue(matches(new Opportunity(CloseDate = weekStart), 'CloseDate = THIS_WEEK'), 'the week starts on the user locale first day');
        Assert.isTrue(matches(new Opportunity(CloseDate = weekStart.addDays(-1)), 'CloseDate = LAST_WEEK'), 'the day before the week start is last week');
        Assert.isFalse(matches(opp, 'CloseDate = NEXT_N_DAYS:3'), 'NEXT_N_DAYS starts tomorrow');
        Assert.isTrue(matches(new Opportunity(CloseDate = today.addDays(3)), 'CloseDate = NEXT_N_DAYS:3'), 'and covers n days');
        Assert.isTrue(matches(new Opportunity(CloseDate = today.addDays(-3)), 'CloseDate = LAST_N_DAYS:3'), 'LAST_N_DAYS covers the past n days');
        Assert.isFalse(matches(opp, 'CloseDate = LAST_N_MONTHS:1'), 'LAST_N_MONTHS leaves out the current month');
        Assert.isTrue(matches(new Opportunity(CloseDate = today.toStartOfMonth().addMonths(-1)), 'CloseDate = LAST_N_MONTHS:1'), 'and starts on the first day of the earliest month');
        Assert.isFalse(matches(opp, 'CloseDate = NEXT_N_MONTHS:1'), 'NEXT_N_MONTHS leaves out the current month');
        Assert.isFalse(matches(opp, 'CloseDate = LAST_N_WEEKS:1') || matches(opp, 'CloseDate = NEXT_N_WEEKS:1'), 'the N_WEEKS literals leave out the current week');
        Assert.isFalse(matches(opp, 'CloseDate = LAST_N_QUARTERS:1') || matches(opp, 'CloseDate = NEXT_N_QUARTERS:1'), 'the N_QUARTERS literals leave out the current quarter');
        Assert.isFalse(matches(opp, 'CloseDate = LAST_N_YEARS:1') || matches(opp, 'CloseDate = NEXT_N_YEARS:1'), 'the N_YEARS literals leave out the current year');
        Assert.isTrue(matches(new Opportunity(CloseDate = Date.newInstance(today.year() - 1, 6, 1)), 'CloseDate = LAST_N_YEARS:1'), 'last year is in LAST_N_YEARS:1');
        Assert.isTrue(matches(opp, 'CloseDate > LAST_N_DAYS:7') == false && matches(opp, 'CloseDate >= LAST_N_DAYS:7'), 'a range literal with > means after the range');
        Assert.isTrue(matches(opp, 'CloseDate < NEXT_N_DAYS:7') && matches(opp, 'CloseDate <= THIS_MONTH'), 'a range literal with < means before the range');
        Assert.isTrue(matches(opp, 'CloseDate != LAST_MONTH'), 'a range literal with !=');

        for (String literal : new List<String>{ 'THIS_MONTH', 'LAST_MONTH', 'NEXT_MONTH', 'THIS_QUARTER', 'LAST_QUARTER', 'NEXT_QUARTER', 'THIS_YEAR', 'LAST_YEAR', 'NEXT_YEAR', 'NEXT_WEEK', 'N_DAYS_AGO:1', 'N_WEEKS_AGO:1', 'N_MONTHS_AGO:1', 'N_QUARTERS_AGO:1', 'N_YEARS_AGO:1' }) {
            Assert.isNull(errorOf(opp, 'CloseDate = ' + literal), literal + ' is supported');
        }
        Assert.isTrue(matches(opp, 'CloseDate = THIS_MONTH') && matches(opp, 'CloseDate = THIS_QUARTER') && matches(opp, 'CloseDate = THIS_YEAR'), 'today is in the current month, quarter and year');

        Event ev = new Event(StartDateTime = Datetime.newInstanceGmt(2026, 1, 1, 9, 0, 0), DurationInMinutes = 30);
        Assert.isTrue(matches(ev, 'StartDateTime = 2026-01-01T09:00:00Z'), 'a datetime with Z is an exact UTC instant');
        Assert.isFalse(matches(ev, 'StartDateTime = 2026-01-01 09:00:00'), 'without Z it is the user local time, a different instant');
        Assert.isTrue(matches(ev, 'StartDateTime > 2025-12-31T00:00:00Z') && matches(ev, 'StartDateTime < 2026-01-02'), 'datetime ordering, including a date-only value');
        Assert.isTrue(matches(new Event(StartDateTime = Datetime.now(), DurationInMinutes = 1), 'StartDateTime = TODAY'), 'a datetime compared with a date literal uses its local date');
    }

    @IsTest
    static void invalidCriteriaAreReportedClearly() {
        Opportunity opp = new Opportunity(Name = 'X', Amount = 1, IsPrivate = true, Type = 'New Customer', CloseDate = Date.today());

        Assert.isTrue(errorOf(opp, 'not a valid criteria string').contains('Invalid'), 'bad syntax');
        Assert.isTrue(errorOf(opp, 'No_Such_Field__c = 1').contains('No_Such_Field__c'), 'unknown field');
        Assert.isNotNull(errorOf(opp, 'Amount > null'), '> with null');
        Assert.isNotNull(errorOf(opp, 'Name > \'A\''), 'ordering on text');
        Assert.isNotNull(errorOf(opp, 'IsPrivate > true'), 'ordering on a boolean');
        Assert.isNotNull(errorOf(opp, 'Name LIKE Acme'), 'unquoted LIKE pattern');
        Assert.isNotNull(errorOf(opp, 'Type IN \'New Customer\''), 'IN without parentheses');
        Assert.isNotNull(errorOf(opp, 'Type INCLUDES (\'New Customer\')'), 'INCLUDES on a single-select picklist');
        Assert.isNotNull(errorOf(opp, 'Amount = abc'), 'a value that is not a number');
        Assert.isNotNull(errorOf(opp, 'CloseDate = not-a-date'), 'a value that is not a date');
        Assert.isNull(errorOf(opp, ''), 'blank criteria always pass');
        Assert.isTrue(matches(opp, ''), 'blank criteria always pass');
        Assert.areEqual('Amount', FieldTransitionConditionEvaluator.extractParentCriteriaFieldName('Amount>=5'), 'field name extraction');
        Assert.isNull(FieldTransitionConditionEvaluator.extractParentCriteriaFieldName(''), 'no field in blank criteria');
    }

    // ---------- child conditions

    @IsTest
    static void childConditionTypesAreBulkAndIsolated() {
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 5; i++) {
            opps.add(new Opportunity(Name = 'Child Cond Opp ' + i, StageName = 'Prospecting', CloseDate = Date.today().addDays(30)));
        }
        insert opps;
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 5; i++) { contacts.add(new Contact(LastName = 'Child Cond Contact ' + i)); }
        insert contacts;
        insert new List<OpportunityContactRole>{
            new OpportunityContactRole(OpportunityId = opps[0].Id, ContactId = contacts[0].Id, Role = 'Decision Maker', IsPrimary = true),
            new OpportunityContactRole(OpportunityId = opps[1].Id, ContactId = contacts[1].Id, Role = 'Decision Maker', IsPrimary = false),
            new OpportunityContactRole(OpportunityId = opps[3].Id, ContactId = contacts[3].Id, Role = 'Business User', IsPrimary = true),
            new OpportunityContactRole(OpportunityId = opps[4].Id, ContactId = contacts[4].Id, Role = 'Decision Maker', IsPrimary = true),
            new OpportunityContactRole(OpportunityId = opps[4].Id, ContactId = contacts[0].Id, Role = 'Decision Maker', IsPrimary = false)
        };

        Transition_Condition__mdt exists = childCondition(null, FieldTransitionConditionEvaluator.CONDITION_TYPE_CHILD_RECORD_EXISTS, 'OpportunityContactRole', 'OpportunityId', 'Role = \'Decision Maker\'', null, null);
        Transition_Condition__mdt allSatisfy = childCondition(null, FieldTransitionConditionEvaluator.CONDITION_TYPE_ALL_MATCHING_CHILDREN_SATISFY, 'OpportunityContactRole', 'OpportunityId', 'Role = \'Decision Maker\'', 'IsPrimary = true', null);
        Transition_Condition__mdt ifExists = childCondition(null, FieldTransitionConditionEvaluator.CONDITION_TYPE_PARENT_CRITERIA_IF_CHILD_EXISTS, 'OpportunityContactRole', 'OpportunityId', 'Role = \'Decision Maker\'', null, null);
        ifExists.Parent_Filter_Criteria__c = 'Amount != null';
        Transition_Condition__mdt broken = childCondition(null, FieldTransitionConditionEvaluator.CONDITION_TYPE_CHILD_RECORD_EXISTS, 'NoSuchObject__x', 'X__c', null, null, null);
        Transition_Condition__mdt unknownType = condition(null, 'Some Future Type', null);

        Set<Id> parentIds = new Map<Id, Opportunity>(opps).keySet();
        opps[0].Amount = 5000;
        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        FieldTransitionConditionEvaluator.BulkContext context = FieldTransitionConditionEvaluator.prefetch(
            new List<Transition_Condition__mdt>{ exists, allSatisfy, ifExists, broken },
            new Map<Id, Set<Id>>{ exists.Id => parentIds, allSatisfy.Id => parentIds, ifExists.Id => parentIds, broken.Id => parentIds });
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        List<Boolean> expectedExists = new List<Boolean>{ true, true, false, false, true };
        List<Boolean> expectedAllSatisfy = new List<Boolean>{ true, false, true, true, false };
        for (Integer i = 0; i < 5; i++) {
            Assert.areEqual(expectedExists[i], FieldTransitionConditionEvaluator.evaluate(exists, opps[i], context), 'Child Record Exists, opp ' + i);
            Assert.areEqual(expectedAllSatisfy[i], FieldTransitionConditionEvaluator.evaluate(allSatisfy, opps[i], context), 'All Matching Children Satisfy, opp ' + i);
            Assert.isFalse(FieldTransitionConditionEvaluator.evaluate(broken, opps[i], context), 'a condition whose query fails is not met');
        }
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(ifExists, opps[0], context), 'has a Decision Maker and an Amount');
        Assert.isFalse(FieldTransitionConditionEvaluator.evaluate(ifExists, opps[1], context), 'has a Decision Maker but no Amount');
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(ifExists, opps[2], context), 'no Decision Maker: the condition does not apply');
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(unknownType, opps[0], context), 'an unknown condition type is ignored');
        Assert.isTrue(queriesUsed <= 4, 'one query per child condition for all five records, whatever their number: ' + queriesUsed);
    }

    // ---------- validator

    @IsTest
    static void validatorBlocksWithAClearMessageAndScalesInBulk() {
        Field_Transition_Rule__mdt toNeeds = rule('Opportunity', 'StageName', 'Prospecting', 'Needs Analysis');
        List<Transition_Condition__mdt> conditions = new List<Transition_Condition__mdt>{
            childCondition(toNeeds, FieldTransitionConditionEvaluator.CONDITION_TYPE_CHILD_RECORD_EXISTS, 'OpportunityContactRole', 'OpportunityId', 'Role = \'Decision Maker\'', null, 'A Decision Maker contact role'),
            parentCriteria(toNeeds, 'Amount > 0', 'An amount above zero'),
            parentCriteria(toNeeds, 'NextStep != null', null)
        };
        useConfiguration(new List<Field_Transition_Rule__mdt>{ toNeeds }, conditions);

        Integer total = 200;
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < total; i++) {
            opps.add(new Opportunity(Name = 'Bulk Opp ' + i, StageName = 'Prospecting', CloseDate = Date.today().addDays(30)));
        }
        insert opps;
        Contact contact = new Contact(LastName = 'Bulk Contact');
        insert contact;
        List<OpportunityContactRole> roles = new List<OpportunityContactRole>();
        for (Integer i = 0; i < total / 2; i++) {
            roles.add(new OpportunityContactRole(OpportunityId = opps[i].Id, ContactId = contact.Id, Role = 'Decision Maker'));
        }
        insert roles;

        Map<Id, SObject> oldMap = new Map<Id, SObject>();
        for (Opportunity o : opps) { oldMap.put(o.Id, o.clone(true, false, false, false)); }
        for (Integer i = 0; i < total; i++) {
            opps[i].StageName = 'Needs Analysis';
            if (i < total / 2) { opps[i].Amount = 5000; opps[i].NextStep = 'Demo'; }
        }

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        FieldTransitionValidator.validateTransitions(opps, oldMap);
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        for (Integer i = 0; i < total; i++) {
            Assert.areEqual(i >= total / 2, opps[i].hasErrors(), 'only the unqualified half is blocked, index ' + i);
        }
        String message = opps[total - 1].getErrors()[0].getMessage();
        String stageLabel = Opportunity.StageName.getDescribe().getLabel();
        Assert.isTrue(message.contains(stageLabel) && message.contains('Needs Analysis'), 'the message names the field by its label and the value: ' + message);
        Assert.isTrue(message.contains('A Decision Maker contact role') && message.contains('An amount above zero'), 'and lists what is missing: ' + message);
        Assert.isTrue(message.contains('Condition '), 'a condition without Message__c is named by its label: ' + message);
        Assert.isTrue(queriesUsed <= 3, total + ' records cost a fixed number of queries: ' + queriesUsed);
    }

    @IsTest
    static void validatorMatchesOnlyRealTransitions() {
        Field_Transition_Rule__mdt fromProspecting = rule('Opportunity', 'StageName', 'Prospecting', 'Needs Analysis');
        Field_Transition_Rule__mdt fromAnywhere = rule('Opportunity', 'StageName', null, 'Closed Lost');
        Field_Transition_Rule__mdt staleField = rule('Opportunity', 'No_Such_Field__c', null, 'X');
        Field_Transition_Rule__mdt inactive = rule('Opportunity', 'StageName', null, 'Qualification');
        inactive.Is_Active__c = false;
        Field_Transition_Rule__mdt noConditions = rule('Opportunity', 'StageName', null, 'Value Proposition');
        useConfiguration(
            new List<Field_Transition_Rule__mdt>{ fromProspecting, fromAnywhere, staleField, inactive, noConditions },
            new List<Transition_Condition__mdt>{
                parentCriteria(fromProspecting, 'Amount > 0', 'Amount'),
                parentCriteria(fromAnywhere, 'Description != null', 'A reason'),
                parentCriteria(staleField, 'Amount > 0', 'Never evaluated'),
                parentCriteria(inactive, 'Amount > 0', 'Inactive rule')
            });

        Assert.isFalse(save('Prospecting', 'Prospecting').hasErrors(), 'saving the same value is not a transition');
        Assert.isFalse(save('Qualification', 'Needs Analysis').hasErrors(), 'a From_Value__c rule ignores other starting values');
        Assert.isTrue(save('Prospecting', 'Needs Analysis').hasErrors(), 'the scoped transition is enforced');
        Assert.isTrue(save('Negotiation/Review', 'Closed Lost').hasErrors(), 'a blank From_Value__c applies from any value');
        Assert.isFalse(save('Prospecting', 'Qualification').hasErrors(), 'an inactive rule is ignored');
        Assert.isFalse(save('Prospecting', 'Value Proposition').hasErrors(), 'a rule without conditions never blocks');
        FieldTransitionValidator.validateTransitions(new List<SObject>(), null);
        FieldTransitionValidator.validateTransitions(new Account(Name = 'No rules'), null);
    }

    private static Opportunity save(String fromStage, String toStage) {
        Id oppId = fakeId(Opportunity.SObjectType);
        Opportunity oldRecord = new Opportunity(Id = oppId, StageName = fromStage);
        Opportunity newRecord = new Opportunity(Id = oppId, StageName = toStage);
        FieldTransitionValidator.validateTransitions(newRecord, oldRecord);
        return newRecord;
    }

    @IsTest
    static void rulesCanAlsoApplyOnInsert() {
        Field_Transition_Rule__mdt onInsert = rule('Opportunity', 'StageName', null, 'Closed Won');
        onInsert.Apply_On_Insert__c = true;
        Field_Transition_Rule__mdt updateOnly = rule('Opportunity', 'StageName', null, 'Closed Lost');
        Field_Transition_Rule__mdt scoped = rule('Opportunity', 'StageName', 'Prospecting', 'Needs Analysis');
        scoped.Apply_On_Insert__c = true;
        useConfiguration(
            new List<Field_Transition_Rule__mdt>{ onInsert, updateOnly, scoped },
            new List<Transition_Condition__mdt>{
                parentCriteria(onInsert, 'Amount > 0', 'Amount'),
                childCondition(onInsert, FieldTransitionConditionEvaluator.CONDITION_TYPE_ALL_MATCHING_CHILDREN_SATISFY, 'OpportunityContactRole', 'OpportunityId', null, 'IsPrimary = true', 'Primary contacts'),
                parentCriteria(updateOnly, 'Amount > 0', 'Amount'),
                parentCriteria(scoped, 'Amount > 0', 'Amount')
            });

        List<Opportunity> created = new List<Opportunity>{
            new Opportunity(Name = 'Created won, no amount', StageName = 'Closed Won'),
            new Opportunity(Name = 'Created won, amount', StageName = 'Closed Won', Amount = 10),
            new Opportunity(Name = 'Created lost', StageName = 'Closed Lost'),
            new Opportunity(Name = 'Created at a scoped stage', StageName = 'Needs Analysis')
        };
        FieldTransitionValidator.validateTransitions(created, null);

        Assert.isTrue(created[0].hasErrors(), 'Apply_On_Insert__c blocks creating a record directly at the value');
        Assert.isFalse(created[1].hasErrors(), 'when its conditions are met, the record is created; child conditions have nothing to check yet');
        Assert.isFalse(created[2].hasErrors(), 'a rule without Apply_On_Insert__c ignores inserts');
        Assert.isFalse(created[3].hasErrors(), 'a rule with a From_Value__c never applies on insert');
    }

    // ---------- checklist

    @IsTest
    static void checklistShowsReachableTransitionsAndAgreesWithTheSave() {
        Field_Transition_Rule__mdt toNeeds = rule('Opportunity', 'StageName', 'Prospecting', 'Needs Analysis');
        Field_Transition_Rule__mdt toLost = rule('Opportunity', 'StageName', null, 'Closed Lost');
        Field_Transition_Rule__mdt toLostAgain = rule('Opportunity', 'StageName', null, 'Closed Lost');
        Field_Transition_Rule__mdt fromElsewhere = rule('Opportunity', 'StageName', 'Qualification', 'Closed Won');
        Field_Transition_Rule__mdt toCurrent = rule('Opportunity', 'StageName', null, 'Prospecting');
        Field_Transition_Rule__mdt staleField = rule('Opportunity', 'No_Such_Field__c', null, 'X');
        useConfiguration(
            new List<Field_Transition_Rule__mdt>{ toNeeds, toLost, toLostAgain, fromElsewhere, toCurrent, staleField },
            new List<Transition_Condition__mdt>{
                parentCriteria(toNeeds, 'Amount > 0', 'An amount'),
                parentCriteria(toNeeds, 'Name != null', 'A name'),
                parentCriteria(toNeeds, 'No_Such_Field__c = 1', 'Broken'),
                parentCriteria(toLost, 'Description != null', 'A reason')
            });
        Opportunity opp = new Opportunity(Name = 'Checklist Opp', StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert opp;

        Test.startTest();
        List<FieldTransitionRequirementService.FieldRequirementGroup> groups = FieldTransitionRequirementController.getPendingRequirements(opp.Id);
        Test.stopTest();

        Assert.areEqual(1, groups.size(), 'one governed field');
        Assert.areEqual('StageName', groups[0].fieldApiName);
        Assert.areEqual(Opportunity.StageName.getDescribe().getLabel(), groups[0].fieldLabel, 'the field label is shown');
        Assert.areEqual('Prospecting', groups[0].currentValue);
        Assert.areEqual(3, groups[0].transitions.size(), 'reachable: to Needs Analysis and two Closed Lost rules; not Qualification-scoped or the current value');
        FieldTransitionRequirementService.TransitionRequirement needs = groups[0].transitions[0];
        Assert.areEqual('Needs Analysis', needs.toValue);
        Assert.isFalse(needs.allSatisfied, 'no amount yet');
        Map<String, Boolean> byLabel = new Map<String, Boolean>();
        for (FieldTransitionRequirementService.ConditionRequirement c : needs.conditions) { byLabel.put(c.label, c.satisfied); }
        Assert.isFalse(byLabel.get('An amount'), 'unmet condition');
        Assert.isTrue(byLabel.get('A name'), 'met condition');
        Assert.isFalse(byLabel.get('Broken'), 'a broken condition shows as unmet');
        Assert.areEqual('Any', groups[0].transitions[1].fromValue, 'a blank From_Value__c shows as Any');

        Opportunity saved = new Opportunity(Id = opp.Id, StageName = 'Needs Analysis');
        FieldTransitionValidator.validateTransitions(saved, new Opportunity(Id = opp.Id, StageName = 'Prospecting'));
        Assert.isTrue(saved.hasErrors(), 'the save agrees with the checklist');
        Assert.isTrue(FieldTransitionRequirementService.getPendingRequirements(null).isEmpty(), 'no record, no checklist');
        Assert.isTrue(FieldTransitionRequirementService.getPendingRequirements(fakeId(Account.SObjectType)).isEmpty(), 'an object without rules has an empty checklist');
    }

    @IsTest
    static void controllerReportsErrorsReadably() {
        useConfiguration(new List<Field_Transition_Rule__mdt>{ rule('Opportunity', 'StageName', null, 'Closed Won') }, new List<Transition_Condition__mdt>());
        try {
            FieldTransitionRequirementController.getPendingRequirements(fakeId(Opportunity.SObjectType));
            Assert.fail('a record that does not exist should fail');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex.getMessage(), 'the LWC gets a readable error');
        }
    }

    @IsTest
    static void standardUserGetsTheSameResults() {
        Field_Transition_Rule__mdt toNeeds = rule('Opportunity', 'StageName', 'Prospecting', 'Needs Analysis');
        useConfiguration(new List<Field_Transition_Rule__mdt>{ toNeeds }, new List<Transition_Condition__mdt>{
            parentCriteria(toNeeds, 'Amount > 0', 'An amount'),
            childCondition(toNeeds, FieldTransitionConditionEvaluator.CONDITION_TYPE_CHILD_RECORD_EXISTS, 'OpportunityContactRole', 'OpportunityId', null, null, 'A contact role')
        });
        User standardUser = createStandardUser();
        System.runAs(standardUser) {
            Opportunity opp = new Opportunity(Name = 'Standard User Opp', StageName = 'Prospecting', CloseDate = Date.today().addDays(30), Amount = 10);
            insert opp;
            List<FieldTransitionRequirementService.FieldRequirementGroup> groups = FieldTransitionRequirementController.getPendingRequirements(opp.Id);
            Assert.areEqual(2, groups[0].transitions[0].conditions.size(), 'a non-admin user sees the checklist');
            Opportunity saved = new Opportunity(Id = opp.Id, StageName = 'Needs Analysis', Amount = 10);
            FieldTransitionValidator.validateTransitions(saved, new Opportunity(Id = opp.Id, StageName = 'Prospecting'));
            Assert.isTrue(saved.getErrors()[0].getMessage().contains('A contact role'), 'and is blocked for the missing requirement only');
        }
    }

    // ---------- configuration check

    @IsTest
    static void validateConfigurationFindsEveryKindOfMistake() {
        Field_Transition_Rule__mdt badObject = rule('No_Such_Object__c', 'Status__c', null, 'X');
        Field_Transition_Rule__mdt badField = rule('Opportunity', 'No_Such_Field__c', null, 'X');
        Field_Transition_Rule__mdt badValues = rule('Opportunity', 'StageName', 'Not A Stage', 'Also Not A Stage');
        Field_Transition_Rule__mdt good = rule('Opportunity', 'StageName', 'Prospecting', 'Closed Won');
        useConfiguration(
            new List<Field_Transition_Rule__mdt>{ badObject, badField, badValues, good },
            new List<Transition_Condition__mdt>{
                condition(good, 'Some Future Type', null),
                condition(good, FieldTransitionConditionEvaluator.CONDITION_TYPE_PARENT_FIELD_CRITERIA, null),
                parentCriteria(good, 'No_Such_Field__c = 1', null),
                parentCriteria(good, 'Amount > abc', null),
                parentCriteria(good, 'Amount>=100', null),
                childCondition(good, FieldTransitionConditionEvaluator.CONDITION_TYPE_CHILD_RECORD_EXISTS, 'No_Such_Child__c', 'X__c', null, null, null),
                childCondition(good, FieldTransitionConditionEvaluator.CONDITION_TYPE_CHILD_RECORD_EXISTS, 'OpportunityContactRole', 'No_Such_Field__c', null, null, null),
                childCondition(good, FieldTransitionConditionEvaluator.CONDITION_TYPE_CHILD_RECORD_EXISTS, 'Contact', 'AccountId', null, null, null),
                childCondition(good, FieldTransitionConditionEvaluator.CONDITION_TYPE_ALL_MATCHING_CHILDREN_SATISFY, 'OpportunityContactRole', 'OpportunityId', null, null, null),
                childCondition(good, FieldTransitionConditionEvaluator.CONDITION_TYPE_CHILD_RECORD_EXISTS, 'OpportunityContactRole', 'OpportunityId', 'Role = ', null, null),
                childCondition(good, FieldTransitionConditionEvaluator.CONDITION_TYPE_CHILD_RECORD_EXISTS, 'OpportunityContactRole', 'OpportunityId', 'Role = \'Decision Maker\'', null, null)
            });

        List<String> problems = FieldTransitionMetadataService.validateConfiguration();
        String all = String.join(problems, '\n');

        Assert.areEqual(13, problems.size(), 'one problem per mistake, none for the valid parts:\n' + all);
        for (String expected : new List<String>{ 'No_Such_Object__c', 'does not exist on Opportunity', 'Also Not A Stage', 'Not A Stage', 'unknown Condition_Type__c', 'is required for this condition type', 'abc', 'No_Such_Child__c', 'does not point to Opportunity', 'Child_Required_Criteria__c is required', 'not valid SOQL' }) {
            Assert.isTrue(all.contains(expected), 'reports: ' + expected + '\n' + all);
        }
    }

    @IsTest
    static void activeConfigurationInThisOrgIsValid() {
        List<String> problems = FieldTransitionMetadataService.validateConfiguration();
        Assert.isTrue(problems.isEmpty(), 'Fix these transition rules: ' + String.join(problems, ' | '));
    }

    @IsTest
    static void metadataServiceFiltersAndGroups() {
        Field_Transition_Rule__mdt active = rule('Opportunity', 'StageName', null, 'Closed Won');
        Field_Transition_Rule__mdt otherObject = rule('Account', 'Rating', null, 'Hot');
        Transition_Condition__mdt kept = parentCriteria(active, 'Amount > 0', null);
        Transition_Condition__mdt inactiveCondition = parentCriteria(active, 'Amount > 1', null);
        inactiveCondition.Is_Active__c = false;
        useConfiguration(new List<Field_Transition_Rule__mdt>{ active, otherObject }, new List<Transition_Condition__mdt>{ kept, inactiveCondition });

        Assert.areEqual(1, FieldTransitionMetadataService.getActiveRulesForObject('opportunity').size(), 'rules are matched by object, ignoring case');
        Map<Id, List<Transition_Condition__mdt>> byRule = FieldTransitionMetadataService.getActiveConditionsByRuleId(new Set<Id>{ active.Id });
        Assert.areEqual(1, byRule.get(active.Id).size(), 'inactive conditions are left out');
    }
}
