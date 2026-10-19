import type { RuleBuilderState } from "better-supabase/blocks/rules/react";
import type { FilterQuery } from "better-supabase/list";

import { generatedOptions } from "better-supabase/blocks";
import { useRuleBuilder } from "better-supabase/blocks/rules/react";
import { tenantOf, useAuth } from "better-supabase/react";

import { blockConfig } from "@/lib/supabase/blocks.generated";

export interface RuleEditorOptions {
  /** The rule to edit; `null` edits a new one. */
  readonly rule: string | null;
  /** The record type whose fields the rules test, such as `expense`. */
  readonly subjectType: string;
  /** A new rule's trigger, such as `expense.submitted`. */
  readonly trigger?: string;
  /** The tree a new rule starts with. */
  readonly initial?: FilterQuery;
  /** Node ids the editor may not change, such as a fixed first condition. */
  readonly locked?: readonly string[];
}

export interface RuleEditor extends RuleBuilderState {
  /** The active organization; `undefined` until the session has a tenant claim, so keep Save disabled. */
  readonly organizationId: string | undefined;
}

/**
 * The editor state of one rule in the active organization: its fields, its
 * condition tree, validation, dirty state and save. Works in React DOM and
 * React Native; render the rows with your own components.
 */
export function useRuleEditor(options: RuleEditorOptions): RuleEditor {
  const organizationId = tenantOf(useAuth());

  const builder = useRuleBuilder({
    ...options,
    organizationId: organizationId ?? "",
    schema: generatedOptions(blockConfig.rules).schema,
  });

  return { ...builder, organizationId };
}
