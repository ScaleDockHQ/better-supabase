import { defineAgent } from "eve";

import { scriptedModel } from "./model.ts";

const retention = process.env["EVE_WORLD_RETENTION"];
const idleMs = Number(process.env["EVE_WORLD_IDLE_MS"] ?? 0);

export default defineAgent({
  model: scriptedModel,
  // eve has no Gateway catalog entry for a scripted model.
  modelContextWindowTokens: 200_000,
  experimental: {
    workflow: {
      // The server reads the delivery mode and the connection from the environment.
      // EVE_WORLD_LOCAL=1 runs eve's own file World, the reference the scenarios compare against.
      ...(process.env["EVE_WORLD_LOCAL"] === "1"
        ? {}
        : { world: "better-supabase/workflow-sdk/world" }),
      ...(retention === "0" ? { retention: 0 } : {}),
      ...(retention === "default" ? { retention: "default" as const } : {}),
    },
  },
  ...(idleMs > 0 ? { limits: { sessionTimeoutMs: idleMs } } : {}),
});
