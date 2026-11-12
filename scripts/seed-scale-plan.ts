// The volume tiers of `pnpm db:seed:scale` and the batches each one runs. Pure,
// so a test can check the arithmetic without a database.

export type Tier = "smoke" | "m" | "l" | "xl";

export const TIER_NAMES: readonly Tier[] = ["smoke", "m", "l", "xl"];

export interface TierSpec {
  /** Organizations, the Acme organization included. */
  readonly tenants: number;
  /** Rows of the hot tables that the hot tenant (Acme) holds. */
  readonly hotRows: number;
  /** Customers and notes in each of the other tenants. */
  readonly rowsPerTenant: number;
  /** Rows of the append-only tables, in the hot tenant and around it. */
  readonly audit: number;
  readonly notifications: number;
}

/**
 * `smoke` checks the generators in seconds. `m` is the 60,000-row CI tier with
 * 150 organizations. `l` is 1,000 tenants with one holding 1,000,000 rows per
 * hot table. `xl` adds 10,000,000 rows on the append-only tables.
 */
export const TIERS: Readonly<Record<Tier, TierSpec>> = {
  smoke: {
    tenants: 4,
    hotRows: 300,
    rowsPerTenant: 100,
    audit: 1000,
    notifications: 500,
  },
  m: {
    tenants: 150,
    hotRows: 60_000,
    rowsPerTenant: 0,
    audit: 0,
    notifications: 0,
  },
  l: {
    tenants: 1000,
    hotRows: 1_000_000,
    rowsPerTenant: 100,
    audit: 1_000_000,
    notifications: 1_000_000,
  },
  xl: {
    tenants: 1000,
    hotRows: 1_000_000,
    rowsPerTenant: 100,
    audit: 10_000_000,
    notifications: 10_000_000,
  },
};

export type SeedArea =
  | "tenants"
  | "customers"
  | "notes"
  | "audit"
  | "notifications";

export interface SeedStep {
  readonly area: SeedArea;
  /** The generator under `supabase/seeds/scale`. */
  readonly file: string;
  readonly from: number;
  readonly to: number;
  /** Values for the `{{name}}` placeholders besides `from` and `to`. */
  readonly vars: Readonly<Record<string, number>>;
}

const ROW_BATCH = 250_000;
const EVENT_BATCH = 500_000;

const batches = (
  area: SeedArea,
  file: string,
  total: number,
  size: number,
  vars: Readonly<Record<string, number>>,
): SeedStep[] => {
  const steps: SeedStep[] = [];

  for (let from = 1; from <= total; from += size) {
    steps.push({
      area,
      file,
      from,
      to: Math.min(from + size - 1, total),
      vars,
    });
  }

  return steps;
};

export const tierSpec = (tier: Tier, tenants?: number): TierSpec => {
  const spec = TIERS[tier];

  return tenants === undefined ? spec : { ...spec, tenants };
};

/** The rows of customers (and notes, one per customer) a tier writes. */
export const customerRows = (spec: TierSpec): number =>
  spec.hotRows + (spec.tenants - 1) * spec.rowsPerTenant;

/** The steps of a tier, in the order they run. */
export const planSeed = (tier: Tier, tenants?: number): readonly SeedStep[] => {
  const spec = tierSpec(tier, tenants);
  const others = spec.tenants - 1;
  const rows = customerRows(spec);
  const vars = { hot: spec.hotRows, tenants: Math.max(others, 1) };

  return [
    ...batches("tenants", "tenants.sql", others, ROW_BATCH, {}),
    ...batches("customers", "customers.sql", rows, ROW_BATCH, vars),
    ...batches("notes", "notes.sql", rows, ROW_BATCH, vars),
    ...batches("audit", "audit-events.sql", spec.audit, EVENT_BATCH, {
      total: spec.audit,
    }),
    ...batches(
      "notifications",
      "notification-events.sql",
      spec.notifications,
      EVENT_BATCH,
      { total: spec.notifications },
    ),
  ];
};

/** Fills the `{{name}}` placeholders of a generator. */
export const renderStep = (template: string, step: SeedStep): string => {
  const values = new Map<string, number>([
    ...Object.entries(step.vars),
    ["from", step.from],
    ["to", step.to],
  ]);

  return template.replaceAll(/\{\{(\w+)\}\}/g, (placeholder, name: string) => {
    const value = values.get(name);

    if (value === undefined) {
      throw new Error(`${step.file} uses ${placeholder}, which no step sets`);
    }

    return String(value);
  });
};

/** The run every tier batch writes under, so import mode skips row triggers. */
export const SEED_RUN = "00000000-0000-4000-8000-5ca1e5eed000";

/** One batch in its own transaction, in import mode. */
export const inImportMode = (sql: string): string =>
  `begin;\nselect better_supabase.begin_import_session('${SEED_RUN}');\n${sql.trimEnd().replace(/;$/, "")};\ncommit;\n`;

export interface SeedArgs {
  readonly tier: Tier | undefined;
  readonly tenants: number | undefined;
  readonly dryRun: boolean;
  /** Delete the rows of an earlier tier seed first. */
  readonly clean: boolean;
  readonly notificationsOnly: boolean;
}

export const parseArgs = (args: readonly string[]): SeedArgs => {
  let tier: Tier | undefined;
  let tenants: number | undefined;

  const value = (flag: string): string | undefined => {
    const at = args.indexOf(flag);

    return at === -1 ? undefined : args[at + 1];
  };

  const rawTier = value("--tier");

  if (rawTier !== undefined) {
    const named = TIER_NAMES.find((name) => name === rawTier);

    if (!named) {
      throw new Error(`--tier takes ${TIER_NAMES.join(", ")}, not ${rawTier}`);
    }

    tier = named;
  }

  const rawTenants = value("--tenants");

  if (rawTenants !== undefined) {
    tenants = Number(rawTenants);

    if (!Number.isInteger(tenants) || tenants < 2) {
      throw new Error("--tenants takes a whole number of at least 2");
    }
  }

  return {
    tier,
    tenants,
    dryRun: args.includes("--dry-run"),
    clean: args.includes("--clean"),
    notificationsOnly: args.includes("notifications"),
  };
};
