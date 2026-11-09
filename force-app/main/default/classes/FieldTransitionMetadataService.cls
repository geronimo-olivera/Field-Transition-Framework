/**
 * File Name   :	FieldTransitionMetadataService.cls
 * Description :	Read-only data access for Field_Transition_Rule__mdt and Transition_Condition__mdt, plus
 *                  validateConfiguration(), which checks every active rule and condition for mistakes that
 *                  would otherwise only show up as a blocked save.
 *
 *                  Reads with SOQL rather than getAll(), because getAll() truncates the long text criteria
 *                  fields to 255 characters. In a trigger that query works for every user. Called from the checklist,
 *                  it needs read access to both metadata types, which the Field_Transition_Checklist permission set
 *                  grants. Tests supply their own records through the @TestVisible overrides, so they never depend on
 *                  an org's configuration.
 **/
public inherited sharing class FieldTransitionMetadataService {

    /** Lets a test supply rules instead of reading Field_Transition_Rule__mdt. */
    @TestVisible
    private static List<Field_Transition_Rule__mdt> rulesOverride;

    /** Lets a test supply conditions instead of reading Transition_Condition__mdt. */
    @TestVisible
    private static List<Transition_Condition__mdt> conditionsOverride;

    private static final Set<String> CHILD_CONDITION_TYPES = new Set<String>{
        FieldTransitionConditionEvaluator.CONDITION_TYPE_CHILD_RECORD_EXISTS,
        FieldTransitionConditionEvaluator.CONDITION_TYPE_ALL_MATCHING_CHILDREN_SATISFY,
        FieldTransitionConditionEvaluator.CONDITION_TYPE_PARENT_CRITERIA_IF_CHILD_EXISTS
    };

    /**
     * Fetches the active transition rules configured for one object.
     * @param objectApiName API name of the object to look up rules for.
     * @return active Field_Transition_Rule__mdt records for that object, ordered by Order__c.
     */
    public static List<Field_Transition_Rule__mdt> getActiveRulesForObject(String objectApiName) {
        List<Field_Transition_Rule__mdt> matching = new List<Field_Transition_Rule__mdt>();
        for (Field_Transition_Rule__mdt rule : getActiveRules()) {
            if (rule.Object_API_Name__c != null && rule.Object_API_Name__c.equalsIgnoreCase(objectApiName)) { matching.add(rule); }
        }
        return matching;
    }

    /**
     * Fetches the active conditions for a set of rules, grouped by rule.
     * @param ruleIds Ids of Field_Transition_Rule__mdt records to fetch conditions for.
     * @return active Transition_Condition__mdt records, grouped by their Field_Transition_Rule__c, in label order.
     */
    public static Map<Id, List<Transition_Condition__mdt>> getActiveConditionsByRuleId(Set<Id> ruleIds) {
        Map<Id, List<Transition_Condition__mdt>> conditionsByRuleId = new Map<Id, List<Transition_Condition__mdt>>();
        for (Transition_Condition__mdt condition : getActiveConditions(ruleIds)) {
            if (!conditionsByRuleId.containsKey(condition.Field_Transition_Rule__c)) {
                conditionsByRuleId.put(condition.Field_Transition_Rule__c, new List<Transition_Condition__mdt>());
            }
            conditionsByRuleId.get(condition.Field_Transition_Rule__c).add(condition);
        }
        return conditionsByRuleId;
    }

    /**
     * Checks every active rule and condition and reports what would make it block or allow saves wrongly: an
     * object or field that doesn't exist, a From/To value that isn't one of a picklist's values, a child object
     * or relationship field that doesn't exist or doesn't point to the rule's object, child criteria that don't
     * compile as SOQL, and parent criteria with bad syntax or a value that doesn't fit the field. Call it from a
     * test in your org so a typo fails the deploy instead of blocking users in production.
     * @return one readable problem per mistake. Empty when everything is valid.
     */
    public static List<String> validateConfiguration() {
        List<String> problems = new List<String>();
        List<Field_Transition_Rule__mdt> rules = getActiveRules();
        Set<Id> ruleIds = new Set<Id>();
        for (Field_Transition_Rule__mdt rule : rules) { ruleIds.add(rule.Id); }
        Map<Id, List<Transition_Condition__mdt>> conditionsByRuleId = getActiveConditionsByRuleId(ruleIds);
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

        for (Field_Transition_Rule__mdt rule : rules) {
            String ruleLabel = 'Rule ' + rule.DeveloperName;
            Schema.SObjectType objectType = String.isBlank(rule.Object_API_Name__c) ? null : globalDescribe.get(rule.Object_API_Name__c.toLowerCase());
            if (objectType == null) {
                problems.add(ruleLabel + ': object "' + rule.Object_API_Name__c + '" does not exist.');
                continue;
            }
            Schema.SObjectField field = String.isBlank(rule.Field_API_Name__c) ? null : objectType.getDescribe().fields.getMap().get(rule.Field_API_Name__c);
            if (field == null) {
                problems.add(ruleLabel + ': field "' + rule.Field_API_Name__c + '" does not exist on ' + rule.Object_API_Name__c + '.');
            } else {
                problems.addAll(findPicklistValueProblems(ruleLabel, field, rule));
            }
            List<Transition_Condition__mdt> conditions = conditionsByRuleId.get(rule.Id);
            if (conditions == null) { continue; }
            for (Transition_Condition__mdt condition : conditions) {
                problems.addAll(findConditionProblems(ruleLabel + ', condition ' + condition.DeveloperName, objectType, condition, globalDescribe));
            }
        }
        return problems;
    }

    /**
     * @param ruleLabel How the rule is named in messages.
     * @param field The governed field.
     * @param rule The rule.
     * @return a problem for each From/To value that isn't an active value of a picklist field.
     */
    private static List<String> findPicklistValueProblems(String ruleLabel, Schema.SObjectField field, Field_Transition_Rule__mdt rule) {
        List<String> problems = new List<String>();
        Schema.DescribeFieldResult describe = field.getDescribe();
        if (describe.getType() != Schema.DisplayType.PICKLIST) { return problems; }
        Set<String> values = new Set<String>();
        for (Schema.PicklistEntry entry : describe.getPicklistValues()) {
            if (entry.isActive()) { values.add(entry.getValue().toLowerCase()); }
        }
        if (String.isNotBlank(rule.To_Value__c) && !values.contains(rule.To_Value__c.toLowerCase())) {
            problems.add(ruleLabel + ': To_Value__c "' + rule.To_Value__c + '" is not an active value of ' + describe.getName() + '.');
        }
        if (String.isNotBlank(rule.From_Value__c) && !values.contains(rule.From_Value__c.toLowerCase())) {
            problems.add(ruleLabel + ': From_Value__c "' + rule.From_Value__c + '" is not an active value of ' + describe.getName() + '.');
        }
        return problems;
    }

    /**
     * @param label How the condition is named in messages.
     * @param parentType The rule's object.
     * @param condition The condition to check.
     * @param globalDescribe The org's objects.
     * @return the condition's problems.
     */
    private static List<String> findConditionProblems(String label, Schema.SObjectType parentType, Transition_Condition__mdt condition, Map<String, Schema.SObjectType> globalDescribe) {
        List<String> problems = new List<String>();
        String conditionType = condition.Condition_Type__c;
        Boolean isChildType = CHILD_CONDITION_TYPES.contains(conditionType);
        if (!isChildType && conditionType != FieldTransitionConditionEvaluator.CONDITION_TYPE_PARENT_FIELD_CRITERIA) {
            problems.add(label + ': unknown Condition_Type__c "' + conditionType + '".');
            return problems;
        }
        if (conditionType != FieldTransitionConditionEvaluator.CONDITION_TYPE_CHILD_RECORD_EXISTS
            && conditionType != FieldTransitionConditionEvaluator.CONDITION_TYPE_ALL_MATCHING_CHILDREN_SATISFY) {
            String parentProblem = String.isBlank(condition.Parent_Filter_Criteria__c)
                ? label + ': Parent_Filter_Criteria__c is required for this condition type.'
                : FieldTransitionConditionEvaluator.findParentCriteriaProblem(parentType, condition.Parent_Filter_Criteria__c);
            if (parentProblem != null) { problems.add(parentProblem.startsWith(label) ? parentProblem : label + ': ' + parentProblem); }
        }
        if (!isChildType) { return problems; }

        Schema.SObjectType childType = String.isBlank(condition.Child_Object_API_Name__c) ? null : globalDescribe.get(condition.Child_Object_API_Name__c.toLowerCase());
        if (childType == null) {
            problems.add(label + ': child object "' + condition.Child_Object_API_Name__c + '" does not exist.');
            return problems;
        }
        Schema.SObjectField relationship = String.isBlank(condition.Child_Relationship_Field__c) ? null : childType.getDescribe().fields.getMap().get(condition.Child_Relationship_Field__c);
        if (relationship == null) {
            problems.add(label + ': field "' + condition.Child_Relationship_Field__c + '" does not exist on ' + condition.Child_Object_API_Name__c + '.');
            return problems;
        }
        if (!relationship.getDescribe().getReferenceTo().contains(parentType)) {
            problems.add(label + ': ' + condition.Child_Object_API_Name__c + '.' + condition.Child_Relationship_Field__c + ' does not point to ' + parentType + '.');
            return problems;
        }
        if (conditionType == FieldTransitionConditionEvaluator.CONDITION_TYPE_ALL_MATCHING_CHILDREN_SATISFY && String.isBlank(condition.Child_Required_Criteria__c)) {
            problems.add(label + ': Child_Required_Criteria__c is required for All Matching Children Satisfy.');
        }
        String query = 'SELECT COUNT() FROM ' + condition.Child_Object_API_Name__c + ' WHERE ' + condition.Child_Relationship_Field__c + ' = null';
        if (String.isNotBlank(condition.Child_Filter_Criteria__c)) { query += ' AND (' + condition.Child_Filter_Criteria__c + ')'; }
        if (String.isNotBlank(condition.Child_Required_Criteria__c)) { query += ' AND (' + condition.Child_Required_Criteria__c + ')'; }
        try {
            Database.countQuery(query + ' LIMIT 1');
        } catch (Exception ex) {
            problems.add(label + ': the child criteria are not valid SOQL: ' + ex.getMessage());
        }
        return problems;
    }

    /**
     * @return every active rule, ordered by Order__c (nulls last).
     */
    private static List<Field_Transition_Rule__mdt> getActiveRules() {
        if (rulesOverride != null) {
            List<Field_Transition_Rule__mdt> active = new List<Field_Transition_Rule__mdt>();
            for (Field_Transition_Rule__mdt rule : rulesOverride) {
                if (rule.Is_Active__c) { active.add(rule); }
            }
            return active;
        }
        return [
            SELECT Id, DeveloperName, MasterLabel, Field_API_Name__c, From_Value__c, Is_Active__c, Object_API_Name__c,
                Order__c, To_Value__c, Apply_On_Insert__c
            FROM Field_Transition_Rule__mdt
            WHERE Is_Active__c = true
            ORDER BY Order__c ASC NULLS LAST, DeveloperName ASC
        ];
    }

    /**
     * @param ruleIds The rules whose conditions to return.
     * @return the active conditions of those rules, in label order.
     */
    private static List<Transition_Condition__mdt> getActiveConditions(Set<Id> ruleIds) {
        if (conditionsOverride != null) {
            List<Transition_Condition__mdt> active = new List<Transition_Condition__mdt>();
            for (Transition_Condition__mdt condition : conditionsOverride) {
                if (condition.Is_Active__c && ruleIds.contains(condition.Field_Transition_Rule__c)) { active.add(condition); }
            }
            return active;
        }
        return [
            SELECT Id, DeveloperName, MasterLabel, Message__c, Child_Filter_Criteria__c, Child_Object_API_Name__c,
                Child_Relationship_Field__c, Child_Required_Criteria__c, Condition_Type__c, Field_Transition_Rule__c,
                Parent_Filter_Criteria__c, Is_Active__c
            FROM Transition_Condition__mdt
            WHERE Is_Active__c = true AND Field_Transition_Rule__c IN :ruleIds
            ORDER BY MasterLabel ASC
        ];
    }
}
