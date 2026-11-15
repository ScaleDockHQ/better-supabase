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
import type { EntitySeedJson } from "../packages/better-supabase/src/list/index.ts";

import { assignmentQueuesSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/assignment-queues.seed.ts";
import { commissionsSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/commissions.seed.ts";
import { contractsSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/contracts.seed.ts";
import { dealsSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/deals.seed.ts";
import { incidentsSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/incidents.seed.ts";
import { invitationsSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/invitations.seed.ts";
import { periodsSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/periods.seed.ts";
import { pipelinesSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/pipelines.seed.ts";
import { referralsSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/referrals.seed.ts";
import { risksSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/risks.seed.ts";
import { scoresSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/scores.seed.ts";
import { segmentsSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/segments.seed.ts";
import { workOrdersSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/work-orders.seed.ts";
import {
  orderSeeds,
  resolveSeedValue,
  seedRefs,
} from "../packages/better-supabase/src/list/index.ts";

const ACME = "00000000-0000-4000-8000-000000000001";

/** The Acme owner, whose permissions the block functions check. */
const OWNER = "00000000-0000-4000-8000-0000000000a1";

export interface SeedTarget {
  readonly seed: EntitySeed;
  /**
   * The call that creates one row. `$1` is the tenant and `$2` the row as
   * jsonb, keyed as the seed keys it (`$2::jsonb ->> 'title'`).
   */
  readonly sql: string;
  /**
   * A statement that runs after `sql` with the same parameters, for a change
   * the create call does not take (the statement above cannot see its own
   * insert).
   */
  readonly after?: string;
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
  {
    seed: pipelinesSeed,
    sql: `select better_supabase.save_pipeline_stage((p.pipeline ->> 'id')::uuid, null, s.value ->> 'key', s.value ->> 'name', s.value ->> 'category', (s.value ->> 'probability')::integer, null, null, null, null)
from (select better_supabase.save_pipeline(tenant => $1::uuid, pipeline => null, subject_type => $2::jsonb ->> 'subject_type', key => $2::jsonb ->> 'key', name => $2::jsonb ->> 'name', scope_id => null, is_default => ($2::jsonb ->> 'is_default')::boolean) as pipeline) p
cross join lateral jsonb_array_elements($2::jsonb -> 'stages') with ordinality as s(value, position)
order by s.position`,
    identity: ["name", "key"],
  },
  {
    seed: dealsSeed,
    // The stage is a key of the pipeline and its probability follows the stage. The
    // contact is a person of the tenant.
    sql: `select better_supabase.create_deal(
  tenant => $1::uuid,
  attrs => ($2::jsonb - 'stage' - 'age_days' - 'contact_email') || jsonb_build_object('stageId', st.id, 'probability', st.probability),
  contacts => (select jsonb_agg(jsonb_build_object('type', 'person', 'id', p.id::text, 'role', 'Billing', 'primary', true))
    from better_supabase.people p
    where p.tenant_id = $1::uuid and p.email = $2::jsonb ->> 'contact_email'))
from better_supabase.pipeline_stages st
where st.pipeline_id = ($2::jsonb ->> 'pipelineId')::uuid and st.key = $2::jsonb ->> 'stage'`,
    // The row's age moves the day the deal entered its stage; the insert has to commit first.
    after: `update better_supabase.deals
set stage_entered_at = now() - ($2::jsonb ->> 'age_days')::integer * interval '1 day'
where tenant_id = $1::uuid and name = $2::jsonb ->> 'name'`,
    identity: ["name"],
  },
  {
    seed: segmentsSeed,
    sql: "select better_supabase.refresh_segment((better_supabase.save_segment(tenant => $1::uuid, segment => $2::jsonb) ->> 'id')::uuid)",
    identity: ["name"],
  },
  {
    seed: assignmentQueuesSeed,
    sql: "select better_supabase.set_assignment_members((better_supabase.save_assignment_queue(tenant => $1::uuid, queue => $2::jsonb - 'members') ->> 'id')::uuid, $2::jsonb -> 'members')",
    identity: ["name"],
  },
  {
    seed: scoresSeed,
    // The model is saved once, then scores every company of the tenant.
    sql: `with model as (select better_supabase.save_score_model(tenant => $1::uuid, model => $2::jsonb) as saved)
select m.saved, case when c.id is not null then better_supabase.compute_score($1::uuid, $2::jsonb ->> 'key', 'company', c.id::text, jsonb_build_object('lifecycle', c.lifecycle), null) end
from model m
left join better_supabase.companies c on c.tenant_id = $1::uuid`,
    identity: ["key"],
  },
  {
    seed: contractsSeed,
    sql: "select better_supabase.create_contract(tenant => $1::uuid, attrs => $2::jsonb)",
    identity: ["title"],
  },
];

/** The targets with the rows another page refers to inserted first. */
export function orderedTargets(
  targets: readonly SeedTarget[] = TARGETS,
): readonly SeedTarget[] {
  return orderSeeds(
    targets.map((target) => ({
      entity: target.seed.entity,
      dependsOn: target.seed.dependsOn,
      target,
    })),
  ).map(({ target }) => target);
}

/**
 * Statements that run once after every page: they need rows several pages
 * insert, and a second run finds their result and skips them.
 */
export const FINISHERS: readonly string[] = [
  // The forecast of the open quarter, over the seeded deals.
  `select better_supabase.take_forecast_snapshot($1::uuid, p.id, date_trunc('quarter', current_date)::date, (date_trunc('quarter', current_date) + interval '3 months - 1 day')::date, 'EUR', 3000000)
from better_supabase.pipelines p
where p.key = 'sales' and p.tenant_id = $1::uuid
  and not exists (select 1 from better_supabase.forecast_snapshots f where f.tenant_id = $1::uuid and f.pipeline_id = p.id)`,
];

export interface SeedCall {
  readonly sql: string;
  /** The values of the identity columns, as the table reads back as text. */
  readonly identity: readonly string[];
  readonly values: readonly [string, string];
}

/** Replaces the refs and dates of a row; the default leaves it as written. */
export type RowResolver = (
  row: Readonly<Record<string, EntitySeedJson>>,
) => Readonly<Record<string, EntitySeedJson>>;

/**
 * One call per row of a seed, for a tier and a tenant. A row needs a value for
 * every identity column. `resolve` replaces its refs and dates first, so an
 * identity column that holds a ref reads as the id it names.
 */
export function seedCalls(
  target: SeedTarget,
  tenant: string,
  tier = "demo",
  resolve: RowResolver = (row) => row,
): readonly SeedCall[] {
  if (!target.seed.tiers.includes(tier)) {
    return [];
  }

  return target.seed.rows.map((written) => {
    const row = resolve(written);

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

/** The key of an id in the map a run builds for its refs. */
export const refKey = (entity: string, name: string): string =>
  JSON.stringify([entity, name]);

/**
 * A resolver for the ids a run found, keyed by `refKey`, and the day it counts
 * dates from. A ref whose id the run did not find throws.
 */
export function rowResolver(
  ids: ReadonlyMap<string, string>,
  today: Date,
): RowResolver {
  const resolver = {
    today,
    ref(entity: string, name: string): string {
      const id = ids.get(refKey(entity, name));

      if (id === undefined) {
        throw new Error(`No ${entity} row named "${name}" to refer to.`);
      }

      return id;
    },
  };

  return (row) =>
    Object.fromEntries(
      Object.entries(row).map(([key, value]) => [
        key,
        resolveSeedValue(value, resolver),
      ]),
    );
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
    // The block functions check the caller's permissions: seed as the Acme owner.
    await client.query("select set_config('request.jwt.claims', $1, false)", [
      JSON.stringify({ role: "service_role", sub: OWNER }),
    ]);

    const targets = orderedTargets();

    for (const target of targets) {
      const { seed } = target;

      if (seed.tenant === undefined) {
        throw new Error(`${seed.entity} has no tenant column.`);
      }

      const ids = new Map<string, string>();

      for (const row of seed.rows) {
        for (const { $seedRef: ref } of seedRefs(row)) {
          const source = targets.find(
            (each) => each.seed.entity === ref.entity,
          );

          const [first] = source?.identity ?? [];

          if (source === undefined || first === undefined) {
            throw new Error(`${ref.entity} has no target to refer to.`);
          }

          const found = await client.query<{ id: string }>(
            `select id::text as id from ${source.seed.table} where ${source.seed.tenant ?? "tenant_id"} = $1 and ${first}::text = $2`,
            [ACME, ref.name],
          );

          if (found.rows[0] !== undefined) {
            ids.set(refKey(ref.entity, ref.name), found.rows[0].id);
          }
        }
      }

      const calls = seedCalls(
        target,
        ACME,
        "demo",
        rowResolver(ids, new Date()),
      );

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

        if (target.after !== undefined) {
          await client.query(target.after, [...call.values]);
        }
      }

      console.log(
        `${seed.entity}: ${missing.length} rows added to ${seed.table}`,
      );
    }

    for (const sql of FINISHERS) {
      await client.query(sql, [ACME]);
    }
  } finally {
    await client.end();
  }
}
