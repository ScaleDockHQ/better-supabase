import type { EntityOffline } from "../../blocks/index.ts";

/**
 * The rows each offline block syncs to a device (ADR 0926). `powersync streams`
 * writes its stream queries from this table, and a test keeps it equal to what
 * the manifests declare on their entity (a manifest can't import it: its entry
 * would carry the table).
 */
const notificationsOffline: EntityOffline = { scope: "user" };

const attachmentsOffline: EntityOffline = { scope: "tenant" };

const membershipsOffline: EntityOffline = { scope: "user" };

const teamsOffline: EntityOffline = { scope: "tenant" };

const profilesOffline: EntityOffline = { scope: "self" };

const observationsOffline: EntityOffline = {
  scope: "readers",
  systemRows: "definitions",
};

const medicationsOffline: EntityOffline = {
  scope: "readers",
  systemRows: "definitions",
};

/** Progress notes that are open to the whole team. */
const activitiesOffline: EntityOffline = {
  scope: "readers",
  where: [
    { column: "type", equals: "note" },
    { column: "audience", equals: "team", optional: true },
    { column: "restricted_roles", isNull: true, optional: true },
  ],
};

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
  activities: activitiesOffline,
  attachments: attachmentsOffline,
  medications: medicationsOffline,
  memberships: membershipsOffline,
  notifications: notificationsOffline,
  observations: observationsOffline,
  profiles: profilesOffline,
  teams: teamsOffline,
};
