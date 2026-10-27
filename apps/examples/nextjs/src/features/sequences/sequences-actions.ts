"use server";

import type { SequenceStep } from "better-supabase/blocks/sequences";

import { ok } from "better-supabase";
import * as v from "valibot";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());
const Text = v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200));

/** Saves a draft sequence with an email, a wait and a follow-up task. */
export const createSampleSequence = bsb.action(
  {
    input: v.object({
      name: Text,
      subject: Text,
      text: v.pipe(v.string(), v.maxLength(4000)),
      task: Text,
    }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "sequences.manage"),
  },
  async ({ name, subject, text, task }, { db, auth }) => {
    const saved = await db.sequences.upsert({
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

    await refreshCaller(auth);

    return ok({ id: saved.data.id });
  },
);

/** Activates a sequence so it takes enrollments, or pauses every run. */
export const setSequenceStatus = bsb.action(
  {
    input: v.object({
      sequenceId: Id,
      status: v.picklist(["active", "paused"]),
    }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "sequences.manage"),
  },
  async ({ sequenceId, status }, { db, auth }) => {
    const saved = await db.sequences.upsert({ id: sequenceId, status });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth);

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
export const addSequenceStep = bsb.action(
  {
    input: v.intersect([v.object({ sequenceId: Id }), StepInput]),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "sequences.manage"),
  },
  async (input, { db, auth }) => {
    const { sequences } = db;
    const current = await sequences.get(input.sequenceId);

    if (!current.ok) {
      return current;
    }

    const saved = await sequences.upsert({
      id: input.sequenceId,
      steps: [...current.data.steps, stepOf(input)],
    });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth);

    return ok({ steps: saved.data.steps.length });
  },
);
