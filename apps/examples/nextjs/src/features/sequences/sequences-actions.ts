"use server";

import type { SequenceStep } from "better-supabase/blocks/sequences";

import { ok } from "better-supabase";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { refreshCaller } from "@/lib/refresh-caller";
import { bs } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());
const Text = v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200));

/** Saves a draft sequence with an email, a wait and a follow-up task. */
export const createSampleSequence = bs.action(
  {
    input: v.object({
      name: Text,
      subject: Text,
      text: v.pipe(v.string(), v.maxLength(4000)),
      task: Text,
    }),
    requireTenant: true,
    authorize: (session) => can(session, "sequences.manage"),
  },
  async ({ name, subject, text, task }, { supabase, tenant, auth }) => {
    const saved = await blocks(supabase, tenant).sequences.save({
      key: `sample-${crypto.randomUUID().slice(0, 8)}`,
      name,
      steps: [
        { id: "intro", kind: "email", subject, text },
        { id: "wait", kind: "wait", minutes: 2 * 24 * 60 },
        { id: "follow-up", kind: "task", title: task, dueInMinutes: 24 * 60 },
      ],
    });

    if (!saved.ok) {
      return saved;
    }

    refreshCaller(auth);

    return ok({ id: saved.data.id });
  },
);

/** Activates a sequence so it takes enrollments, or pauses every run. */
export const setSequenceStatus = bs.action(
  {
    input: v.object({
      sequenceId: Id,
      status: v.picklist(["active", "paused"]),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "sequences.manage"),
  },
  async ({ sequenceId, status }, { supabase, tenant, auth }) => {
    const saved = await blocks(supabase, tenant).sequences.save({
      id: sequenceId,
      status,
    });

    if (!saved.ok) {
      return saved;
    }

    refreshCaller(auth);

    return ok({ status: saved.data.status });
  },
);

const StepInput = v.variant("kind", [
  v.object({ kind: v.literal("email"), subject: Text }),
  v.object({
    kind: v.literal("wait"),
    minutes: v.pipe(
      v.string(),
      v.toNumber(),
      v.integer(),
      v.minValue(1),
      v.maxValue(525_600),
    ),
  }),
  v.object({ kind: v.literal("task"), title: Text }),
]);

function stepOf(input: v.InferOutput<typeof StepInput>): SequenceStep {
  const id = `${input.kind}-${crypto.randomUUID().slice(0, 8)}`;

  switch (input.kind) {
    case "email": {
      return { id, kind: "email", subject: input.subject };
    }

    case "wait": {
      return { id, kind: "wait", minutes: input.minutes };
    }

    case "task": {
      return { id, kind: "task", title: input.title };
    }

    default: {
      const unknown: never = input;

      return unknown;
    }
  }
}

/** Appends a step; the sequence's version goes up. */
export const addSequenceStep = bs.action(
  {
    input: v.intersect([v.object({ sequenceId: Id }), StepInput]),
    requireTenant: true,
    authorize: (session) => can(session, "sequences.manage"),
  },
  async (input, { supabase, tenant, auth }) => {
    const { sequences } = blocks(supabase, tenant);
    const current = await sequences.get(input.sequenceId);

    if (!current.ok) {
      return current;
    }

    const saved = await sequences.save({
      id: input.sequenceId,
      steps: [...current.data.steps, stepOf(input)],
    });

    if (!saved.ok) {
      return saved;
    }

    refreshCaller(auth);

    return ok({ steps: saved.data.steps.length });
  },
);
