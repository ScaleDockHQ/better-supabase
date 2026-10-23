import type { FilterNode } from "better-supabase/list";

import "server-only";
import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import { bsb } from "@/lib/supabase/server";

import { RULE_SUBJECT } from "./rule-fields";

/** A rule as plain data, so it crosses the server boundary. */
export interface RuleRow {
  readonly id: string;
  readonly name: string;
  readonly enabled: boolean;
  readonly conditions: number;
  readonly version: number;
  readonly updatedAt: string;
}

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "no-organization" }
  | { readonly kind: "error" };

function countRules(node: FilterNode): number {
  return node.type === "rule"
    ? 1
    : node.rules.reduce((sum, child) => sum + countRules(child), 0);
}

/**
 * The organization's customer rules in evaluation order. Throws on a failed
 * read, so the private cache never keeps an error.
 */
async function loadRules(): Promise<readonly RuleRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const rules = await db.automations
    .list(tenant, { subjectType: RULE_SUBJECT })
    .orThrow();

  return rules.map((rule) => ({
    id: rule.id,
    name: rule.name,
    enabled: rule.enabled,
    conditions: countRules(rule.conditions),
    version: rule.version,
    updatedAt: rule.updatedAt.toString(),
  }));
}

export async function getRules(): Promise<Loaded<readonly RuleRow[]>> {
  try {
    const data = await loadRules();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}
