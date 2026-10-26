import { createDeals } from "better-supabase/blocks/deals";
import { sqlTransport } from "better-supabase/blocks/pipelines";
import { createTasks } from "better-supabase/blocks/tasks";
import { money } from "better-supabase/commerce";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Extra, Session } from "./stack.ts";

import { dbUrl, reachable, withCentraKit } from "./stack.ts";

const live = await reachable();

// CentraKit keeps its customers and contacts in its own bigint tables. Deals
// point at them through config.subjects, and work items carry a customer_id
// extra column, so adopting the blocks needs no change to those tables.
const EXTRA: Extra = {
  modules: ["subjects", "rank", "pipelines", "deals", "tasks"],
  config: {
    deals: {
      options: {
        company: "customer",
        contact: "customer_contact",
        prefix: "OPP-",
      },
    },
    tasks: { options: { extraColumns: { customer_id: "bigint" } } },
  },
  subjects: {
    customer: {
      table: "centrakit.customers",
      idType: "bigint",
      title: "company_name",
    },
    customer_contact: {
      table: "centrakit.customer_contacts",
      idType: "bigint",
      title: "name",
    },
    // What `blocks: ["deals", "tasks"]` registers in config.subjects.
    deal: {
      table: "better_supabase.deals",
      idType: "uuid",
      tenant: "tenant_id",
      title: "name",
      deletedAt: "archived_at",
      permissions: { read: "deals.read", write: "deals.write" },
      rank: { column: "rank", group: "stage_id" },
      search: { title: "name", body: ["identifier", "note"] },
    },
    work_item: {
      table: "better_supabase.work_items",
      idType: "uuid",
      tenant: "tenant_id",
      title: "title",
      deletedAt: "archived_at",
      permissions: { read: "work_items.read", write: "work_items.write" },
      rank: { column: "rank", group: "stage_id" },
      search: { title: "title", body: ["identifier", "body"] },
    },
  },
};

async function organization(s: Session): Promise<string> {
  await s.as("service");

  const { rows } = await s.client.query<{ id: string }>(
    "insert into centrakit.organizations (name, slug) values ('Acme', $1) returning id",
    [`acme-${crypto.randomUUID().slice(0, 8)}`],
  );

  const org = rows[0]!.id;

  return org;
}

describe.skipIf(!live)("CRM and work records on CentraKit", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("points deals at CentraKit customers and contacts", async () => {
    await withCentraKit(
      pool,
      async (s) => {
        const org = await organization(s);
        await s.as("service");

        const customer = (
          await s.rows<{ id: string }>(
            "insert into centrakit.customers (organization_id, company_name) values ($1, 'Bakery Jansen') returning id::text as id",
            [org],
          )
        )[0]!.id;

        const contact = (
          await s.rows<{ id: string }>(
            "insert into centrakit.customer_contacts (organization_id, customer_id, name) values ($1, $2, 'Els') returning id::text as id",
            [org, customer],
          )
        )[0]!.id;

        const deals = createDeals({ transport: sqlTransport(s.sql) });

        const deal = await deals
          .create(
            org,
            {
              name: "Maintenance contract",
              closeOn: Temporal.PlainDate.from("2026-12-31"),
              amount: money(1_250_000n, "EUR"),
              company: { type: "customer", id: customer },
            },
            [{ type: "customer_contact", id: contact, primary: true }],
          )
          .orThrow();

        expect(deal).toMatchObject({
          identifier: "OPP-1",
          company: { type: "customer", id: customer },
          contacts: [{ type: "customer_contact", id: contact, primary: true }],
        });

        const missing = await deals.create(org, {
          name: "Ghost",
          closeOn: Temporal.PlainDate.from("2026-12-31"),
          company: { type: "customer", id: "999999" },
        });

        expect(missing.ok ? "ok" : missing.error.hint).toBe(
          "DEAL_COMPANY_FORBIDDEN",
        );
        const won = await deals.win(deal.id).orThrow();
        expect(won.outcome).toBe("won");
      },
      EXTRA,
    );
  });

  it("keeps a customer on a work item through an extra column", async () => {
    await withCentraKit(
      pool,
      async (s) => {
        const org = await organization(s);
        await s.as("service");

        const customer = (
          await s.rows<{ id: string }>(
            "insert into centrakit.customers (organization_id, company_name) values ($1, 'Garage De Vries') returning id::text as id",
            [org],
          )
        )[0]!.id;

        const items = createTasks({ transport: sqlTransport(s.sql) });

        const task = await items
          .create(org, { title: "Replace boiler" })
          .orThrow();

        expect(task.identifier).toBe("TASK-1");
        await s.client.query(
          "update better_supabase.work_items set customer_id = $1 where id = $2",
          [customer, task.id],
        );
        const [read] = await items.list(org, { search: "boiler" }).orThrow();
        expect(read?.fields).toEqual({ customer_id: Number(customer) });
        expect(read?.state).toBe("triage");
      },
      EXTRA,
    );
  });
});
