"use server";

import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Starts a planned meeting. */
export const startMeeting = bsb.blockAction(
  ({ db }) => db.meetings,
  "start",
  {
    input: v.object({ meetingId: Id }),
    requireTenant: true,
    permission: "meetings.write",
    args: ({ meetingId }) => [meetingId],
  },
  (started) => ({ title: started.title }),
);

/** Holds a running meeting; the database checks that the caller runs it. */
export const holdMeeting = bsb.blockAction(
  ({ db }) => db.meetings,
  "hold",
  {
    input: v.object({ meetingId: Id }),
    requireTenant: true,
    permission: "meetings.write",
  },
  (held) => ({ title: held.title }),
);

/** Settles a decision from the votes of the attendees. */
export const settleDecision = bsb.blockAction(
  ({ db }) => db.meetings,
  "decide",
  {
    input: v.object({ decisionId: Id }),
    requireTenant: true,
    permission: "meetings.write",
  },
  (decided) => ({ status: decided.status }),
);
