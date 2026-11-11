"use server";

import { dbError, err, ok } from "better-supabase";
import { refresh } from "next/cache";
import * as v from "valibot";

import { aiChat } from "@/features/assistant/assistant-server";
import {
  durable,
  durableContext,
} from "@/features/assistant/durable/durable-server";
import { memory } from "@/features/knowledge/knowledge-server";
import { bsbCore } from "@/lib/supabase/server-core";

import { agentsBlock } from "./agents-server";
import { TOOL_POLICIES } from "./agents-tools";

const Slug = v.pipe(v.string(), v.trim(), v.regex(/^[a-z0-9-]{2,40}$/));
const Name = v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(80));
const Id = v.pipe(v.string(), v.uuid());

const AgentFields = {
  name: Name,
  description: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(300))),
  instructions: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(8000)),
  model: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(120))),
  tools: v.array(v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(80))),
  starters: v.array(
    v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
  ),
};

/** Creates an agent for the organization, private until it is published. */
export const createAgent = bsbCore.action(
  {
    input: v.object({ slug: Slug, ...AgentFields }),
    requireTenant: true,
    permission: "agents.write",
  },
  async (input, { tenant, supabase }) => {
    const created = await agentsBlock(supabase).create({
      organizationId: tenant,
      agent: {
        slug: input.slug,
        name: input.name,
        description: input.description ?? "",
        instructions: input.instructions,
        ...(input.model === undefined || input.model === ""
          ? {}
          : { model: input.model }),
        tools: input.tools,
        starters: input.starters,
      },
    });

    if (!created.ok) {
      return created;
    }

    refresh();

    return ok(created.data.id);
  },
);

/** Saves the configuration of an agent. */
export const updateAgent = bsbCore.action(
  {
    input: v.object({ id: Id, ...AgentFields }),
    requireTenant: true,
    permission: "agents.write",
  },
  async ({ id, ...input }, { tenant, supabase }) => {
    const updated = await agentsBlock(supabase).update({
      organizationId: tenant,
      agentId: id,
      fields: {
        name: input.name,
        description: input.description ?? "",
        instructions: input.instructions,
        model:
          input.model === undefined || input.model === "" ? null : input.model,
        tools: input.tools,
        starters: input.starters,
      },
    });

    if (!updated.ok) {
      return updated;
    }

    refresh();

    return ok(updated.data.id);
  },
);

/** Shows an agent to its owner, the organization or everyone. */
export const publishAgent = bsbCore.action(
  {
    input: v.object({
      id: Id,
      visibility: v.picklist(["private", "organization", "public"]),
    }),
    requireTenant: true,
    permission: "agents.publish",
  },
  async ({ id, visibility }, { supabase }) => {
    const published = await agentsBlock(supabase).publish({
      agentId: id,
      visibility,
    });

    if (!published.ok) {
      return published;
    }

    refresh();

    return ok(published.data.visibility);
  },
);

/** Installs an agent for the caller, or removes the installation. */
export const installAgent = bsbCore.action(
  {
    input: v.object({ id: Id, installed: v.boolean() }),
    requireTenant: true,
    permission: "agents.read",
  },
  async ({ id, installed }, { tenant, supabase }) => {
    const result = await agentsBlock(supabase).install({
      organizationId: tenant,
      agentId: id,
      installed,
    });

    if (!result.ok) {
      return result;
    }

    refresh();

    return ok(result.data);
  },
);

/** Deletes an agent. */
export const removeAgent = bsbCore.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    permission: "agents.write",
  },
  async ({ id }, { supabase }) => {
    const removed = await agentsBlock(supabase).remove(id);

    if (!removed.ok) {
      return removed;
    }

    refresh();

    return ok(removed.data);
  },
);

/** Asks a running answer to stop. */
export const cancelRun = bsbCore.action(
  {
    input: v.object({ chatId: Id }),
    requireTenant: true,
    permission: "ai_chat.create",
  },
  async ({ chatId }, { supabase }) => {
    const result = await aiChat(supabase).runs.stop(chatId);

    if (!result.ok) {
      return result;
    }

    refresh();

    return ok(result.data !== undefined);
  },
);

/**
 * Decides several approvals at once. Each chat's turn continues in its workflow
 * once none of its approvals is pending, so the decisions are sent once per
 * chat.
 */
export const decideApprovals = bsbCore.action(
  {
    input: v.object({
      decisions: v.pipe(
        v.array(
          v.object({
            chatId: Id,
            approvalId: v.pipe(v.string(), v.minLength(1), v.maxLength(200)),
          }),
        ),
        v.minLength(1),
        v.maxLength(50),
      ),
      approved: v.boolean(),
    }),
    requireTenant: true,
    permission: "ai_chat.create",
  },
  async ({ decisions, approved }, { tenant, auth, supabase }) => {
    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to decide approvals"));
    }

    const byChat = Map.groupBy(decisions, (decision) => decision.chatId);

    const responses = await Promise.all(
      [...byChat].map(([chatId, entries]) =>
        durable().decide(
          chatId,
          entries.map((entry) => ({ approvalId: entry.approvalId, approved })),
          durableContext(supabase, auth.user.id, tenant),
        ),
      ),
    );

    const failed = responses.filter((response) => !response.ok).length;

    if (failed > 0) {
      return err(
        dbError("unexpected", `${failed} of ${responses.length} chats failed`),
      );
    }

    refresh();

    return ok(decisions.length);
  },
);

/** Saves the rule of each changed tool; `null` removes a rule. */
export const saveToolPolicies = bsbCore.action(
  {
    input: v.object({
      policies: v.pipe(
        v.array(
          v.object({
            tool: v.pipe(v.string(), v.minLength(1), v.maxLength(80)),
            policy: v.nullable(v.picklist(TOOL_POLICIES)),
          }),
        ),
        v.minLength(1),
        v.maxLength(100),
      ),
    }),
    requireTenant: true,
    permission: "ai_chat.manage",
  },
  async ({ policies }, { tenant, supabase }) => {
    const chat = aiChat(supabase);

    const results = await Promise.all(
      policies.map((entry) =>
        chat.approvals.setPolicy({
          organizationId: tenant,
          tool: entry.tool,
          policy: entry.policy,
        }),
      ),
    );

    const failed = results.find((result) => !result.ok);

    if (failed !== undefined) {
      return failed;
    }

    refresh();

    return ok(policies.length);
  },
);

/** Writes a core memory file the assistant reads on every answer. */
export const writeMemoryFile = bsbCore.action(
  {
    input: v.object({
      path: v.pipe(
        v.string(),
        v.trim(),
        v.regex(/^\/memories\/[A-Za-z0-9._/-]{1,100}$/),
      ),
      content: v.pipe(v.string(), v.maxLength(8000)),
    }),
    requireTenant: true,
    permission: "memory.manage",
  },
  async ({ path, content }, { tenant, supabase }) => {
    const saved = await memory(supabase).core.write({
      organizationId: tenant,
      path,
      content,
    });

    if (!saved.ok) {
      return saved;
    }

    refresh();

    return ok(saved.data.version);
  },
);

/** Deletes a core memory file. */
export const removeMemoryFile = bsbCore.action(
  {
    input: v.object({
      path: v.pipe(v.string(), v.minLength(1), v.maxLength(200)),
    }),
    requireTenant: true,
    permission: "memory.manage",
  },
  async ({ path }, { tenant, supabase }) => {
    const removed = await memory(supabase).core.remove({
      organizationId: tenant,
      path,
    });

    if (!removed.ok) {
      return removed;
    }

    refresh();

    return ok(removed.data);
  },
);

/** Forgets one remembered fact; it stays restorable until the purge. */
export const forgetMemoryFact = bsbCore.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    permission: "memory.manage",
  },
  async ({ id }, { supabase }) => {
    const forgotten = await memory(supabase).archival.forget({ memoryId: id });

    if (!forgotten.ok) {
      return forgotten;
    }

    refresh();

    return ok(forgotten.data);
  },
);
