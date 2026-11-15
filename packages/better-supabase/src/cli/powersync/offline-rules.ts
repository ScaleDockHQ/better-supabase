import type { EntityOffline } from "../../blocks/index.ts";

/**
 * The rows each offline block syncs to a device (ADR 0926). `powersync streams`
 * writes its stream queries from this table, and a test keeps it equal to what
 * the manifests declare on their entity (a manifest can't import it: its entry
 * would carry the table).
 */
const notificationsOffline: EntityOffline = {
  scope: "user",
  join: [
    {
      kind: "referenced",
      stream: "events",
      table: { columns: ["type", "idempotency_key", "summary"] },
      column: "id",
      parentColumn: "event_id",
    },
    {
      kind: "owned",
      stream: "preferences",
      table: { columns: ["user_id", "channel", "enabled"] },
      optional: true,
    },
  ],
};

const attachmentsOffline: EntityOffline = {
  scope: "tenant",
  join: [
    { kind: "readers" },
    { kind: "subject", typeColumn: "subject_type", idColumn: "subject_id" },
  ],
};

const membershipsOffline: EntityOffline = {
  scope: "user",
  join: [
    {
      kind: "member-set",
      stream: "roles",
      table: { roleSet: true },
      optional: true,
    },
    {
      kind: "member-organizations",
      stream: "organizations",
      table: {
        block: "organizations",
        columns: ["id", "name"],
        without: ["user_id"],
      },
      select: ["id", "name", "slug", "disabled_at", "deleted_at"],
      optional: true,
    },
  ],
};

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
