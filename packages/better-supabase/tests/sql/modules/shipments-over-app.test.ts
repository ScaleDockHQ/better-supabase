import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's own shipment tables: renamed columns, enum statuses, and no
// ship-from location, record link, URL, size or event detail columns.
const APP = `
create type public.shipment_state as enum ('draft', 'label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned', 'cancelled');
create type public.tracking_state as enum ('label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned');

create table public.parcels (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  code text not null,
  state public.shipment_state not null default 'draft',
  origin jsonb not null,
  destination jsonb not null,
  carrier text,
  service text,
  tracking_number text,
  label_id text,
  label_format text,
  label_cost bigint,
  currency text,
  labeled_at timestamptz,
  delivered_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  notes text
);

create table public.parcel_boxes (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  parcel_id uuid not null references public.parcels (id) on delete cascade,
  position integer not null,
  weight_grams integer not null
);

create table public.parcel_scans (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  parcel_id uuid not null references public.parcels (id) on delete cascade,
  external_id text not null,
  state public.tracking_state not null,
  occurred_at timestamptz not null,
  source text not null,
  created_at timestamptz not null default now()
);
`;

const OWN_TABLES = {
  "public.parcels": "app.sql",
  "public.parcel_boxes": "app.sql",
  "public.parcel_scans": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  shipments: {
    tables: {
      shipments: "public.parcels",
      packages: "public.parcel_boxes",
      trackingEvents: "public.parcel_scans",
    },
    columns: {
      shipments: {
        tenant: "org_id",
        reference: "code",
        status: "state",
        fromAddress: "origin",
        toAddress: "destination",
        fromLocation: null,
        subjectType: null,
        subjectId: null,
        trackingUrl: null,
        labelUrl: null,
        createdBy: null,
      },
      packages: {
        tenant: "org_id",
        shipment: "parcel_id",
        length: null,
        width: null,
        height: null,
        reference: null,
      },
      trackingEvents: {
        tenant: "org_id",
        shipment: "parcel_id",
        status: "state",
        description: null,
        location: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(
  check: string,
  modules: AnyBlocksConfig = BLOCKS,
  app: string = APP,
): Promise<void> {
  const files = renderBlocks(["shipments"], { modules, ownTables: OWN_TABLES });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      app,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

const ADDRESS = `'{"line1": "1 Main St", "city": "Utrecht", "country": "NL"}'::jsonb`;

describe("shipments over the app's tables", BOOT, () => {
  it("creates, labels and tracks a shipment in enum status columns", async () => {
    await expect(
      run(`do $$
declare
  v_ship jsonb;
  v_id uuid;
begin
  ${SERVICE}
  v_ship := better_supabase.create_shipment('${TENANT}', ${ADDRESS}, ${ADDRESS}, '[{"weightGrams": 500, "lengthMm": 10}]'::jsonb, 'SHP-1');
  v_id := (v_ship ->> 'id')::uuid;
  if v_ship ->> 'status' <> 'draft' or v_ship -> 'subjectType' <> 'null'::jsonb then
    raise exception 'created %', v_ship;
  end if;
  perform better_supabase.set_shipment_label(v_id, 'dhl', 'express', 'TRK1', 'L1', 1200, 'EUR');
  perform better_supabase.record_tracking_events(v_id, '[{"id": "e1", "status": "in_transit", "occurredAt": "2099-01-01T10:00:00Z"}, {"id": "e2", "status": "delivered", "occurredAt": "2099-01-02T10:00:00Z"}]'::jsonb);
  perform better_supabase.record_tracking_events(v_id, '[{"id": "e2", "status": "delivered", "occurredAt": "2099-01-02T10:00:00Z"}]'::jsonb);
  if (select state from public.parcels where id = v_id) <> 'delivered' then
    raise exception 'status is %', (select state from public.parcels where id = v_id);
  end if;
  if jsonb_array_length(better_supabase.list_tracking_events(v_id)) <> 3 then
    raise exception 'events %', better_supabase.list_tracking_events(v_id);
  end if;
  if jsonb_array_length(better_supabase.list_shipments('${TENANT}', 'delivered')) <> 1 then
    raise exception 'list_shipments missed the shipment';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("tracks a shipment through status value maps", async () => {
    await expect(
      run(
        `do $$
declare
  v_ship jsonb;
  v_id uuid;
  v_other uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.create_shipment('${TENANT}', ${ADDRESS}, ${ADDRESS}, '[{"weightGrams": 500}]'::jsonb, 'SHP-1') ->> 'id')::uuid;
  perform better_supabase.set_shipment_label(v_id, 'dhl', 'express', 'TRK1', 'L1', 1200, 'EUR');
  if (select state::text from public.parcels where id = v_id) <> 'labelled'
    or (select string_agg(state::text, ',') from public.parcel_scans where parcel_id = v_id) <> 'labelled' then
    raise exception 'labelled %', (select jsonb_agg(p) from public.parcels p);
  end if;
  v_ship := better_supabase.record_tracking_events(v_id, '[{"id": "e1", "status": "in_transit", "occurredAt": "2099-01-01T10:00:00Z"}]'::jsonb);
  if v_ship ->> 'status' <> 'in_transit' or (select state::text from public.parcels where id = v_id) <> 'moving' then
    raise exception 'tracked %', v_ship;
  end if;
  v_other := (better_supabase.create_shipment('${TENANT}', ${ADDRESS}, ${ADDRESS}, '[{"weightGrams": 500}]'::jsonb, 'SHP-2') ->> 'id')::uuid;
  perform better_supabase.cancel_shipment(v_other);
  if (select state::text from public.parcels where id = v_other) <> 'voided' then
    raise exception 'cancel missed';
  end if;
end;
$$;`,
        {
          shipments: {
            ...BLOCKS["shipments"],
            values: {
              shipments: {
                status: {
                  draft: "new",
                  label_created: "labelled",
                  in_transit: "moving",
                  cancelled: "voided",
                },
              },
              trackingEvents: {
                status: { label_created: "labelled", in_transit: "moving" },
              },
            },
          },
        },
        APP.replace(
          "('draft', 'label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned', 'cancelled')",
          "('new', 'labelled', 'moving', 'out_for_delivery', 'delivered', 'exception', 'returned', 'voided')",
        )
          .replace(
            "('label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned')",
            "('labelled', 'moving', 'out_for_delivery', 'delivered', 'exception', 'returned')",
          )
          .replace("not null default 'draft'", "not null default 'new'"),
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses a record link the app's table has no columns for", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.create_shipment('${TENANT}', ${ADDRESS}, ${ADDRESS}, '[{"weightGrams": 500}]'::jsonb, null, null, 'deal', 'd1');
end;
$$;`),
    ).rejects.toThrow(/no record columns/);
  });
});
