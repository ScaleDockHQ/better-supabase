"use server";

import { ok } from "better-supabase";
import { PII_KINDS } from "better-supabase/blocks/ai-guardrails";
import { refresh } from "next/cache";
import * as v from "valibot";

import { bsbCore } from "@/lib/supabase/server-core";

import { guardrailsBlock } from "./guardrails-server";

const Agent = v.pipe(v.string(), v.regex(/^(\*|[a-z0-9][a-z0-9-]{1,39})$/));

/** Saves the policy of one agent and stage for the organization. */
export const savePolicy = bsbCore.action(
  {
    input: v.object({
      agent: Agent,
      stage: v.picklist(["input", "output"]),
      enabled: v.boolean(),
      injection: v.optional(v.picklist(["block", "flag"])),
      pii: v.optional(
        v.object({
          action: v.picklist(["block", "redact", "flag"]),
          kinds: v.array(v.picklist(PII_KINDS)),
        }),
      ),
      denyTopics: v.array(
        v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(60)),
      ),
      maxToolDepth: v.optional(
        v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(20)),
      ),
    }),
    requireTenant: true,
    permission: "ai_chat.manage",
  },
  async (input, { tenant }) => {
    const saved = await guardrailsBlock().policies.upsert({
      agent: input.agent,
      stage: input.stage,
      organizationId: tenant,
      enabled: input.enabled,
      config: {
        ...(input.injection === undefined
          ? {}
          : { injection: { action: input.injection } }),
        ...(input.pii === undefined
          ? {}
          : {
              pii: {
                action: input.pii.action,
                ...(input.pii.kinds.length === 0
                  ? {}
                  : { kinds: input.pii.kinds }),
              },
            }),
        ...(input.denyTopics.length === 0
          ? {}
          : { denyTopics: input.denyTopics }),
        ...(input.maxToolDepth === undefined
          ? {}
          : { maxToolDepth: input.maxToolDepth }),
      },
    });

    if (!saved.ok) {
      return saved;
    }

    refresh();

    return ok(saved.data.id);
  },
);

/**
 * Runs text through the policy that applies and shows the verdict, for the
 * tester.
 */
export const testPolicy = bsbCore.action(
  {
    input: v.object({
      agent: Agent,
      stage: v.picklist(["input", "output"]),
      text: v.pipe(v.string(), v.minLength(1), v.maxLength(2000)),
    }),
    requireTenant: true,
    permission: "ai_chat.manage",
  },
  async ({ agent, stage, text }, { tenant }) => {
    const verdict = await guardrailsBlock().check({
      agent,
      stage,
      text,
      organizationId: tenant,
    });

    if (!verdict.ok) {
      return verdict;
    }

    refresh();

    return ok({
      decision: verdict.data.decision,
      text: verdict.data.text,
      reasons: verdict.data.reasons.map((reason) => reason.detail),
    });
  },
);
