"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Starts a planned meeting. */
export const startMeeting = bsb.action(
  {
    input: v.object({ meetingId: Id }),
    requireTenant: true,
    permission: "meetings.write",
  },
  async ({ meetingId }, { db }) => {
    const started = await db.meetings.start(meetingId);

    return started.ok ? ok({ title: started.data.title }) : started;
  },
);

/** Holds a running meeting; the database checks that the caller runs it. */
export const holdMeeting = bsb.action(
  {
    input: v.object({ meetingId: Id }),
    requireTenant: true,
    permission: "meetings.write",
  },
  async ({ meetingId }, { db }) => {
    const held = await db.meetings.hold(meetingId);

    return held.ok ? ok({ title: held.data.title }) : held;
  },
);

/** Settles a decision from the votes of the attendees. */
export const settleDecision = bsb.action(
  {
    input: v.object({ decisionId: Id }),
    requireTenant: true,
    permission: "meetings.write",
  },
  async ({ decisionId }, { db }) => {
    const decided = await db.meetings.decide(decisionId);

    return decided.ok ? ok({ status: decided.data.status }) : decided;
  },
);
