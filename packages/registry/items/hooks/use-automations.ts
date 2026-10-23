"use client";

import type {
  Automations,
  RuleBuilderActions,
  RuleBuilderSnapshot,
} from "better-supabase/blocks/automations";
import type { FilterLimits, FilterQuery } from "better-supabase/list";

import { rpcTransport } from "better-supabase/blocks";
import {
  createAutomations,
  createRuleBuilderController,
} from "better-supabase/blocks/automations";
import { useBlockEnv, useController, useLatest } from "better-supabase/react";
import { useMemo } from "react";

export interface UseRuleBuilderOptions {
  readonly organizationId: string;
  /** The rule to edit; `null` edits a new one. */
  readonly rule: string | null;
  /** The record type whose fields the rules test. */
  readonly subjectType: string;
  /** A new rule's trigger, such as `expense.submitted`. */
  readonly trigger?: string;
  /** The tree a new rule starts with. Read once, when the editor starts. */
  readonly initial?: FilterQuery;
  /** Node ids the editor may not change. Read once, when the editor starts. */
  readonly locked?: readonly string[];
  readonly limits?: FilterLimits;
  /** The schema the calls go to (default `better_supabase`). */
  readonly schema?: string;
}

export interface RuleBuilderState
  extends RuleBuilderSnapshot, RuleBuilderActions {
  /** The rules client for the signed-in user, for lists and toggles. */
  readonly rules: Automations;
}

/**
 * The editor state of one rule: its fields, its condition tree with the edits
 * to it, validation, dirty state and save.
 *
 * ```tsx
 * const builder = useRuleBuilder({
 *   organizationId,
 *   rule: null,
 *   subjectType: "expense",
 * });
 * builder.addRule(undefined, "amount");
 * ```
 */
export function useRuleBuilder(
  options: UseRuleBuilderOptions,
): RuleBuilderState {
  const { supabase, auth } = useBlockEnv();
  const latest = useLatest(options);

  const { organizationId, rule, subjectType, trigger, limits, schema } =
    options;

  const rules = useMemo(
    () =>
      createAutomations({
        transport: rpcTransport(supabase),
        ...(schema === undefined ? {} : { schema }),
      }),
    [supabase, schema],
  );

  const { view } = useController(() => {
    const { initial, locked } = latest.current;

    return createRuleBuilderController({
      client: rules,
      auth,
      organizationId,
      rule,
      subjectType,
      ...(trigger === undefined ? {} : { trigger }),
      ...(initial === undefined ? {} : { initial }),
      ...(locked === undefined ? {} : { locked }),
      ...(limits === undefined ? {} : { limits }),
    });
  }, [rules, auth, latest, organizationId, rule, subjectType, trigger, limits]);

  return useMemo(() => ({ ...view, rules }), [view, rules]);
}
