import type { EntityOffline } from "./entity-surface.ts";

/**
 * The rows each offline block syncs to a device (ADR 0926). The manifests
 * declare these on their entity and `powersync streams` writes its stream
 * queries from them, so both read one table.
 */
export const OFFLINE_RULES: Readonly<
  Record<
    | "activities"
    | "attachments"
    | "medications"
    | "memberships"
    | "notifications"
    | "observations"
    | "profiles"
    | "teams",
    EntityOffline
  >
> = {
  notifications: { scope: "user" },
  attachments: { scope: "tenant" },
  memberships: { scope: "user" },
  teams: { scope: "tenant" },
  profiles: { scope: "self" },
  observations: { scope: "readers", systemRows: "definitions" },
  medications: { scope: "readers", systemRows: "definitions" },
  activities: {
    scope: "readers",
    // Progress notes that are open to the whole team.
    where: [
      { column: "type", equals: "note" },
      { column: "audience", equals: "team", optional: true },
      { column: "restricted_roles", isNull: true, optional: true },
    ],
  },
};
