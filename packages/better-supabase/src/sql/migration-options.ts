import type { ModuleConfig, ModulesConfig } from "../config/modules.ts";

/** A module option that only fits a schema being adopted. */
interface MigrationOption {
  readonly module: string;
  readonly option: string;
  /** Whether the configured value departs from the managed default. */
  readonly departs: (value: unknown) => boolean;
  /** What the value does, completing "It ...". */
  readonly effect: string;
}

const MIGRATION_OPTIONS: readonly MigrationOption[] = [
  {
    module: "invitations",
    option: "tokenStorage",
    departs: (value) => value === "plain",
    effect:
      "stores invitation tokens in plain text instead of their SHA-256 hash",
  },
  {
    module: "webhooks-out",
    option: "secretStorage",
    departs: (value) => value === "column",
    effect: "keeps signing secrets in a table column instead of Vault",
  },
  {
    module: "webhooks-out",
    option: "eventIdType",
    departs: (value) => value !== "text",
    effect: "types event ids for an existing column; managed tables use text",
  },
  {
    module: "webhooks-out",
    option: "runIdType",
    departs: (value) => value !== "text",
    effect: "types run ids for an existing column; managed tables use text",
  },
  {
    module: "outbox",
    option: "blockSource",
    departs: (value) => value !== "better-supabase/{module}",
    effect: "replaces the CloudEvents source of module events",
  },
  {
    module: "outbox",
    option: "defaultSource",
    departs: (value) => value !== "",
    effect: "fills a source for events emitted without one",
  },
];

/** A migration-only option a config sets. */
export interface MigrationOptionUse {
  readonly module: string;
  readonly option: string;
  readonly value: unknown;
  readonly adopted: boolean;
  /** `sql.modules.<module>.options.<option> ... It <effect>.` */
  readonly message: string;
}

/**
 * The migration-only options `sql.modules` sets to a value other than the managed
 * default. They are accepted in `adopt` mode only; doctor warns about each.
 */
export function migrationOptionUses(
  modules: ModulesConfig = {},
): MigrationOptionUse[] {
  return MIGRATION_OPTIONS.flatMap((entry) => {
    const config: ModuleConfig | undefined = modules[entry.module];
    const options = config?.options ?? {};
    if (!(entry.option in options)) return [];
    const value = options[entry.option];
    if (!entry.departs(value)) return [];
    return [
      {
        module: entry.module,
        option: entry.option,
        value,
        adopted: config?.mode === "adopt",
        message: `sql.modules.${entry.module}.options.${entry.option} is ${JSON.stringify(value)}. It ${entry.effect}.`,
      },
    ];
  });
}
