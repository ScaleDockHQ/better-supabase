"use server";

import { dbError, err, ok } from "better-supabase";
import { approvalToken } from "better-supabase/blocks/workflow-editor";
import { refresh } from "next/cache";
import * as v from "valibot";
import { resumeHook } from "workflow/api";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { bsb } from "@/lib/supabase/server";

import { builderFor } from "./builder-server";

const Id = v.pipe(v.string(), v.minLength(1), v.maxLength(100));

const Graph = v.object({
  nodes: v.pipe(
    v.array(
      v.object({
        id: Id,
        kind: v.picklist(["trigger", "step", "sleep", "approval", "condition"]),
        label: v.exactOptional(v.pipe(v.string(), v.maxLength(100))),
        step: v.exactOptional(Id),
        config: v.exactOptional(v.record(v.string(), v.unknown())),
        position: v.exactOptional(v.object({ x: v.number(), y: v.number() })),
      }),
    ),
    v.maxLength(100),
  ),
  edges: v.pipe(
    v.array(
      v.object({
        id: Id,
        source: Id,
        target: Id,
        branch: v.exactOptional(v.picklist(["true", "false"])),
      }),
    ),
    v.maxLength(200),
  ),
});

const slugOf = (name: string): string =>
  name
    .toLowerCase()
    .normalize("NFKD")
    .replaceAll(/[^a-z0-9]+/gu, "-")
    .replaceAll(/^-|-$/gu, "")
    .slice(0, 60) || "workflow";

export const createDefinition = bsb.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(100)),
    }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "workflow.edit"),
  },
  async ({ name }, { tenant, supabase }) => {
    const builder = builderFor(supabase);

    const saved = await builder.definitions.upsert({
      tenant,
      slug: slugOf(name),
      name,
    });

    if (!saved.ok) {
      return saved;
    }

    const draft = await builder.versions.upsert(saved.data.id, {
      nodes: [
        {
          id: "trigger",
          kind: "trigger",
          label: "Start",
          position: { x: 0, y: 0 },
        },
      ],
      edges: [],
    });

    if (!draft.ok) {
      return draft;
    }

    refresh();

    return ok(saved.data.id);
  },
);

export const saveDraft = bsb.action(
  {
    input: v.object({ definition: Id, graph: Graph }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "workflow.edit"),
  },
  async ({ definition, graph }, { supabase }) => {
    const saved = await builderFor(supabase).versions.upsert(definition, graph);

    if (!saved.ok) {
      return saved;
    }

    return ok(saved.data.id);
  },
);

/** Saves the canvas as the draft, then publishes it. */
export const publishGraph = bsb.action(
  {
    input: v.object({ definition: Id, graph: Graph }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "workflow.publish"),
  },
  async ({ definition, graph }, { supabase }) => {
    const builder = builderFor(supabase);
    const draft = await builder.versions.upsert(definition, graph);

    if (!draft.ok) {
      return draft;
    }

    const published = await builder.versions.publish(draft.data.id);

    if (!published.ok) {
      return published;
    }

    refresh();

    return ok(published.data.version);
  },
);

export const runDefinition = bsb.action(
  {
    input: v.object({
      definition: Id,
      text: v.optional(v.pipe(v.string(), v.maxLength(20_000))),
    }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "workflow.run"),
  },
  async ({ definition, text }, { auth, supabase }) => {
    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to run a workflow"));
    }

    return builderFor(supabase).run({
      definition,
      input: { text: text ?? "" },
      actor: auth.user.id,
    });
  },
);

const TriggerKind = v.picklist(["manual", "webhook", "schedule"]);

export const saveTrigger = bsb.action(
  {
    input: v.object({
      definition: Id,
      kind: TriggerKind,
      cron: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(100))),
    }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "workflow.admin"),
  },
  async ({ definition, kind, cron }, { tenant, supabase }) => {
    const builder = builderFor(supabase);

    const config = kind === "schedule" ? { cron: cron ?? "0 9 * * *" } : {};

    const saved = await builder.triggers.upsert({ definition, kind, config });

    if (!saved.ok) {
      return saved;
    }

    if (kind === "schedule") {
      const synced = await builder.triggers.syncSchedule(saved.data, tenant);

      if (!synced.ok) {
        return synced;
      }
    }

    refresh();

    return ok(saved.data.id);
  },
);

export const removeTrigger = bsb.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "workflow.admin"),
  },
  async ({ id }, { supabase }) => {
    const removed = await builderFor(supabase).triggers.remove(id);

    if (!removed.ok) {
      return removed;
    }

    refresh();

    return ok(removed.data);
  },
);

/** A new webhook token; the caller shows it once. */
export const rotateWebhookToken = bsb.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "workflow.admin"),
  },
  async ({ id }, { supabase }) => builderFor(supabase).triggers.rotateToken(id),
);

/**
 * Stores a Slack bot token in Vault and the reference to it in the tenant's
 * credentials.
 */
export const createCredential = bsb.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(100)),
      secret: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(4000)),
    }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "workflow.admin"),
  },
  async ({ name, secret }, { tenant, supabase }) => {
    const created = await builderFor(supabase).credentials.create({
      tenant,
      kind: "slack",
      name,
      ref: {
        provider: "vault",
        secret: `workflow:${tenant}:${crypto.randomUUID()}`,
      },
      secret,
    });

    if (!created.ok) {
      return created;
    }

    refresh();

    return ok(created.data.id);
  },
);

export const revokeCredential = bsb.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "workflow.admin"),
  },
  async ({ id }, { supabase }) => {
    const revoked = await builderFor(supabase).credentials.revoke(id);

    if (!revoked.ok) {
      return revoked;
    }

    refresh();

    return ok(revoked.data);
  },
);

/**
 * Resumes an approval node of a graph run. The run is read under RLS and must
 * belong to the active organization, so a caller can only decide the runs they
 * can see.
 */
export const decideNode = bsb.action(
  {
    input: v.object({ run: Id, node: Id, approved: v.boolean() }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "workflow.run"),
  },
  async ({ run, node, approved }, { tenant, auth, db }) => {
    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to decide"));
    }

    const found = await db.workflows.runs.get(run);

    if (!found.ok) {
      return found;
    }

    const key = found.data?.attributes["bsb.key"];

    if (found.data?.tenant !== tenant || !v.is(v.string(), key)) {
      return err(dbError("not_found", "No such run"));
    }

    await resumeHook(approvalToken(key, node), { approved, by: auth.user.id });

    return ok(true);
  },
);
