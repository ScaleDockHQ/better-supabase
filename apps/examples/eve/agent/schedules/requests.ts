import type { SessionAuthContext } from "eve/context";

import { toStandardJsonSchema } from "@valibot/to-json-schema";
import { defineDynamicSchedules } from "eve/experimental/schedules";
import * as v from "valibot";

import eve from "../channels/eve";
import { memberSchedules, postgres } from "../lib/server";

const Member = v.object({
  tenantId: v.pipe(
    v.string("Scheduling needs a member of an organization."),
    v.minLength(1),
  ),
});

const tenantOf = (attributes: SessionAuthContext["attributes"]): string =>
  v.parse(Member, attributes).tenantId;

// Members schedule their own prompts ("every weekday at 9, summarize my open
// tasks"). Each schedule is stored in the queue block's drain scheduler and
// fired by agent/schedules/dispatch.ts, as the member who created it.
export default defineDynamicSchedules({
  description: "Prompts a member schedules for themselves, once or on a cron.",
  inputSchema: toStandardJsonSchema(
    v.object({ task: v.pipe(v.string(), v.minLength(1), v.maxLength(2000)) }),
  ),
  provider: memberSchedules,
  // Each member manages the schedules of the organization they act in.
  scope: ({ session }) => {
    const auth = session.auth.current;

    return auth?.principalType === "user"
      ? [tenantOf(auth.attributes), auth.principalId]
      : null;
  },
  preparePayload: (input, { session }) => ({
    task: input.task,
    tenantId: tenantOf(session.auth.current?.attributes ?? {}),
  }),
  // The member must still belong to the organization when the schedule fires.
  async auth({ principal, payload }) {
    const rows = await postgres.admin.queryRaw(
      "select 1 from public.memberships where organization_id = $1 and user_id = $2",
      [payload.tenantId, principal.principalId],
    );

    const { type, ...identity } = principal;

    return rows.length === 0
      ? null
      : {
          ...identity,
          principalType: type,
          attributes: { tenantId: payload.tenantId },
        };
  },
  async run({ payload, occurrence, to }) {
    await to(eve, {}).send(payload.task, {
      title: occurrence.displayName ?? "Scheduled prompt",
    });
  },
});
