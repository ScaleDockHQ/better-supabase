"use server";

import { ok } from "better-supabase";
import { rpcTransport } from "better-supabase/blocks";
import { createStateMachine } from "better-supabase/blocks/state-machine";
import * as v from "valibot";

import { builderFor } from "@/features/workflows/builder/builder-server";
import { refreshCaller } from "@/lib/refresh-caller";
import { blockConfig } from "@/lib/supabase/blocks.config";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

import {
  CHANGE_SUBJECT,
  CHANGE_WORKFLOW,
  DEFAULT_CHANGE_GRAPH,
} from "./change-request-lifecycle";

const Id = v.pipe(v.string(), v.uuid());

const Stage = v.pipe(v.string(), v.regex(/^[a-z0-9_-]{1,60}$/u));

/** The schema `gen` exposes the state machine's calls in. */
const MACHINE_API = blockConfig["state-machine"].api;

/**
 * Publishes the default change lifecycle as the organization's
 * `change-requests` workflow and makes it the default lifecycle for change
 * requests. The workflow builder edits it from then on.
 */
export const setUpChangeWorkflow = bsb.action(
  { requireTenant: true, permission: "workflow_editor.manage" },
  async (_input, { tenant, supabase, auth }) => {
    const builder = builderFor(supabase);

    const definition = await builder.definitions.upsert({
      tenant,
      slug: CHANGE_WORKFLOW,
      name: "Change requests",
      subjectTypes: [CHANGE_SUBJECT],
    });

    if (!definition.ok) {
      return definition;
    }

    const draft = await builder.versions.upsert({
      definition: definition.data.id,
      graph: DEFAULT_CHANGE_GRAPH,
    });

    if (!draft.ok) {
      return draft;
    }

    const published = await builder.versions.publish({
      version: draft.data.id,
    });

    if (!published.ok) {
      return published;
    }

    const purpose = await builder.definitions.setPurpose({
      id: definition.data.id,
      purpose: "lifecycle",
      isDefault: true,
    });

    if (!purpose.ok) {
      return purpose;
    }

    await refreshCaller(auth, [tags.changeRequests()]);

    return ok(published.data.version);
  },
);

/** Submits a change request; the workflow's trigger sets its first stage. */
export const createChangeRequest = bsb.action(
  {
    input: v.object({
      title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
    }),
    requireTenant: true,
  },
  async ({ title }, { tenant, db, auth }) => {
    const created = await db.changeRequests.create(
      { title, organizationId: tenant },
      { select: ["id"] },
    );

    if (!created.ok) {
      return created;
    }

    await refreshCaller(auth, [tags.changeRequests()]);

    return ok(created.data.id);
  },
);

/**
 * Moves a change request to another stage as the caller. The table's trigger
 * refuses a move the published workflow has no path for, and the status history
 * keeps who moved it.
 */
export const moveChangeRequest = bsb.action(
  { input: v.object({ id: Id, to: Stage }), requireTenant: true },
  async ({ id, to }, { supabase, auth }) => {
    const machine = createStateMachine({
      transport: rpcTransport(supabase, { schema: MACHINE_API }),
      schema: MACHINE_API,
    });

    const moved = await machine.transition({
      subject: { type: CHANGE_SUBJECT, id },
      to,
    });

    if (!moved.ok) {
      return moved;
    }

    await refreshCaller(auth, [tags.changeRequests()]);

    return ok(moved.data);
  },
);
