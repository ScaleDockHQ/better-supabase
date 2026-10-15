import * as v from "valibot";

/**
 * Each notification type and the Standard Schema `send` checks its `data`
 * against. Replace the example with your own types; zod and arktype schemas
 * work too.
 */
export const notificationTypes = {
  "member.joined": v.object({ name: v.pipe(v.string(), v.minLength(1)) }),
};
