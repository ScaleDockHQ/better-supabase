/**
 * The blocks 0.15 renamed to plain defaults (ADR 0093), from the 0.14 name to
 * the 0.15 one. `upgrade` moves an installed block to its new name, the config
 * names the new one for an old key, and `codemod 0.15` rewrites both.
 */
export const BLOCK_RENAMES: Readonly<Record<string, string>> = {
  "work-items": "tasks",
  parties: "contacts",
  engagements: "activities",
  targets: "goals",
  "number-sequences": "numbering",
  actor: "created-by",
  "ensure-rls": "rls-guard",
  grants: "data-api-grants",
  "shared-signals": "security-events",
  "service-principals": "service-accounts",
  "support-sessions": "impersonation",
  bulk: "bulk-actions",
  controls: "compliance",
  passes: "admission-passes",
  "ai-tasks": "ai-schedules",
  "ai-providers": "ai-keys",
  "workflow-builder": "workflow-editor",
  jobs: "queue",
  flags: "feature-flags",
  access: "permissions",
  rules: "automations",
  identities: "linked-identities",
  sessions: "session-revocation",
  tenant: "memberships",
  activity: "timeline",
  "workflow-sdk-world": "workflow-sdk",
};

/** The 0.15 name of a block 0.15 renamed, or `undefined`. */
export function renamedBlock(name: string): string | undefined {
  return Object.hasOwn(BLOCK_RENAMES, name) ? BLOCK_RENAMES[name] : undefined;
}

/** The 0.14 name of a block 0.15 renamed, or `undefined`. */
export function formerBlockName(name: string): string | undefined {
  return Object.entries(BLOCK_RENAMES).find(([, to]) => to === name)?.[0];
}

/** `name` under its 0.15 name. */
export const currentBlockName = (name: string): string =>
  renamedBlock(name) ?? name;
