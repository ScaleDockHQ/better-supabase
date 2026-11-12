"use server";

import { ok } from "better-supabase";
import { refresh } from "next/cache";
import * as v from "valibot";

import { bsbCore } from "@/lib/supabase/server-core";

import { promptsBlock } from "./prompts-server";

const Name = v.pipe(v.string(), v.regex(/^[a-z0-9][a-z0-9._-]{2,79}$/));
const Label = v.pipe(v.string(), v.regex(/^[a-z][a-z0-9_-]{1,30}$/));

/**
 * Saves the template as the next version of the prompt. A label moves to it in
 * the same call, so `production` goes live at once.
 */
export const savePromptVersion = bsbCore.action(
  {
    input: v.object({
      name: Name,
      template: v.pipe(
        v.string(),
        v.trim(),
        v.minLength(1),
        v.maxLength(20_000),
      ),
      label: v.optional(Label),
    }),
    requireTenant: true,
    permission: "ai_chat.manage",
  },
  async ({ name, template, label }, { tenant }) => {
    const saved = await promptsBlock().create({
      name,
      template,
      organizationId: tenant,
      ...(label === undefined ? {} : { label }),
    });

    if (!saved.ok) {
      return saved;
    }

    refresh();

    return ok(saved.data.version);
  },
);

/** Points a label at an existing version: a promotion or a rollback. */
export const setPromptLabel = bsbCore.action(
  {
    input: v.object({
      name: Name,
      label: Label,
      version: v.pipe(v.number(), v.integer(), v.minValue(1)),
    }),
    requireTenant: true,
    permission: "ai_chat.manage",
  },
  async ({ name, label, version }, { tenant }) => {
    const moved = await promptsBlock().setLabel({
      name,
      label,
      version,
      organizationId: tenant,
    });

    if (!moved.ok) {
      return moved;
    }

    refresh();

    return ok(moved.data.version);
  },
);
