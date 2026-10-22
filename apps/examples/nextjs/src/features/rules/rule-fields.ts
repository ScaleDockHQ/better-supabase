import type { FilterQuery } from "better-supabase/list";

import { defineRuleFields } from "better-supabase/blocks/automations";

/** The record type the example's rules test. */
export const RULE_SUBJECT = "customer";

/** The event the rules run on: a customer was created or changed. */
export const RULE_TRIGGER = "customer.saved";

/**
 * The customer values a rule may test. `sync-rule-fields.ts` writes them at
 * start-up, so the database checks and evaluates rules against the same catalog
 * as the editor.
 */
export const customerRuleFields = defineRuleFields(RULE_SUBJECT, {
  status: {
    type: "select",
    options: ["lead", "active", "archived"],
    operators: ["is", "is_not"],
    nullable: false,
  },
  name: {
    type: "text",
    operators: ["contains", "not_contains", "starts_with", "is", "is_not"],
    nullable: false,
  },
  kvk: {
    type: "text",
    label: "KvK number",
    operators: ["is", "empty", "not_empty"],
  },
  createdAt: {
    type: "date",
    column: "created_at",
    operators: ["is_before", "is_after"],
    nullable: false,
  },
});

/** The condition every customer rule starts with; the editor locks it. */
export const LOCKED_CONDITION = "lead-status";

/** A new rule's tree: the locked "Status is Lead" condition. */
export const initialConditions: FilterQuery = {
  id: "root",
  type: "group",
  combinator: "and",
  rules: [
    {
      id: LOCKED_CONDITION,
      type: "rule",
      path: ["status"],
      operator: "is",
      value: "lead",
    },
  ],
};
