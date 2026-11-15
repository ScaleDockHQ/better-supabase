/**
 * Inserts the demo rows that `better-supabase gen` writes for the entity pages
 * of the Next.js example (`<name>.seed.ts`, ADR 0879, 1030) into the Acme
 * organization of the local stack: `pnpm db:seed:pages`. A row goes through the
 * block's own function, so numbering, triggers and policies run as they do for
 * the app. It skips a row whose identity columns the organization already
 * holds, so a second run adds nothing. It reads the database URL that `pnpm
 * env:local` wrote.
 */
import { readFileSync } from "node:fs";
import { argv } from "node:process";
import { Client } from "pg";

import type { EntitySeed } from "../packages/better-supabase/src/list/entity-ui.ts";

import { commissionsSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/commissions.seed.ts";
import { incidentsSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/incidents.seed.ts";
import { invitationsSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/invitations.seed.ts";
import { periodsSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/periods.seed.ts";
import { referralsSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/referrals.seed.ts";
import { risksSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/risks.seed.ts";
import { workOrdersSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/work-orders.seed.ts";

const ACME = "00000000-0000-4000-8000-000000000001";

export interface SeedTarget {
  readonly seed: EntitySeed;
  /**
   * The call that creates one row. `$1` is the tenant and `$2` the row as
   * jsonb, keyed as the seed keys it (`$2::jsonb ->> 'title'`).
   */
  readonly sql: string;
  /**
   * The row keys that name a row, which are columns of the seed's table. A row
   * whose values the table already holds for the tenant is skipped.
   */
  readonly identity: readonly string[];
}

export const TARGETS: readonly SeedTarget[] = [
  {
    seed: workOrdersSeed,
    sql: "select better_supabase.create_work_order(tenant => $1::uuid, title => $2::jsonb ->> 'title')",
    identity: ["title"],
  },
  {
    seed: incidentsSeed,
    sql: "select better_supabase.open_incident(tenant => $1::uuid, attrs => $2::jsonb)",
    identity: ["title"],
  },
  {
    seed: risksSeed,
    sql: "select better_supabase.create_risk(tenant => $1::uuid, input => $2::jsonb)",
    identity: ["title"],
  },
  {
    seed: periodsSeed,
    sql: "select better_supabase.create_period(tenant => $1::uuid, kind => $2::jsonb ->> 'kind', starts_on => ($2::jsonb ->> 'starts_on')::date, ends_on => ($2::jsonb ->> 'ends_on')::date)",
    identity: ["kind", "starts_on"],
  },
  {
    seed: commissionsSeed,
    sql: "select better_supabase.accrue_commission(tenant => $1::uuid, seller_id => ($2::jsonb ->> 'seller_id')::uuid, source_type => $2::jsonb ->> 'source_type', source_id => $2::jsonb ->> 'source_id', basis => ($2::jsonb ->> 'basis')::bigint, currency => $2::jsonb ->> 'currency', occurred_on => ($2::jsonb ->> 'occurred_on')::date)",
    identity: ["seller_id", "source_type", "source_id"],
  },
  {
    seed: referralsSeed,
    sql: "select better_supabase.attribute_referral(tenant => $1::uuid, code => $2::jsonb ->> 'code', referred_email => $2::jsonb ->> 'referred_email')",
    identity: ["referred_email"],
  },
  {
    seed: invitationsSeed,
    sql: "select better_supabase.create_invitation(organization => $1::uuid, invitee_email => $2::jsonb ->> 'email', invitee_role => $2::jsonb ->> 'role')",
    identity: ["email"],
  },
];

export interface SeedCall {
  readonly sql: string;
  /** The values of the identity columns, as the table reads back as text. */
  readonly identity: readonly string[];
  readonly values: readonly [string, string];
}

/**
 * One call per row of a seed, for a tier and a tenant. A row needs a value for
 * every identity column.
 */
export function seedCalls(
  target: SeedTarget,
  tenant: string,
  tier = "demo",
): readonly SeedCall[] {
  if (!target.seed.tiers.includes(tier)) {
    return [];
  }

  return target.seed.rows.map((row) => {
    const identity = target.identity.map((key) => {
      const value = row[key];

      if (value === undefined || value === null) {
        throw new TypeError(`A ${target.seed.entity} seed row needs a ${key}.`);
      }

      return String(value);
    });

    return { sql: target.sql, identity, values: [tenant, JSON.stringify(row)] };
  });
}

/** The calls whose identity the table does not hold yet. */
export function missingCalls(
  calls: readonly SeedCall[],
  held: readonly (readonly string[])[],
): readonly SeedCall[] {
  const have = new Set(held.map((row) => JSON.stringify(row)));

  return calls.filter((call) => !have.has(JSON.stringify(call.identity)));
}

if (argv[1] === import.meta.filename) {
  const url = /^SUPABASE_DB_URL=(.*)$/m.exec(
    readFileSync(".env.development.local", "utf-8"),
  )?.[1];

  if (!url) {
    throw new Error(
      "Run pnpm supabase:start first: .env.development.local has no SUPABASE_DB_URL.",
    );
  }

  const client = new Client({ connectionString: url });

  await client.connect();

  try {
    for (const target of TARGETS) {
      const { seed } = target;

      if (seed.tenant === undefined) {
        throw new Error(`${seed.entity} has no tenant column.`);
      }

      const calls = seedCalls(target, ACME);

      const held = await client.query<Record<string, string>>(
        `select ${target.identity.map((key) => `${key}::text as ${key}`).join(", ")} from ${seed.table} where ${seed.tenant} = $1`,
        [ACME],
      );

      const missing = missingCalls(
        calls,
        held.rows.map((row) => target.identity.map((key) => row[key] ?? "")),
      );

      for (const call of missing) {
        await client.query(call.sql, [...call.values]);
      }

      console.log(
        `${seed.entity}: ${missing.length} rows added to ${seed.table}`,
      );
    }
  } finally {
    await client.end();
  }
}
