import { defineMetric } from "better-supabase/blocks/metrics";
import { orderMetrics } from "better-supabase/blocks/orders";
import { defineConfig } from "better-supabase/config";

// The configs on the Presets docs pages: each starts from a named preset
// (better-supabase/preset) and adds the blocks and options its app needs, with
// the app tables in a schema of their own instead of `public`. Each recipe
// also names the tables it creates, so a test can install it on an empty
// schema. A state machine is keyed by its subject type, so its status.changed
// events reach the subject's watchers.

export interface Recipe {
  readonly name: string;
  readonly schema: string;
  readonly config: ReturnType<typeof defineConfig>;
  /** The app's own tables, created before the module files. */
  readonly tables: string;
  /**
   * App SQL over module tables (views, hook functions), run after the module
   * files.
   */
  readonly after?: string;
}

const readable = (table: string): string => `
alter table ${table} enable row level security;
create policy members_read on ${table} for select to authenticated
  using (better_supabase.has_organization_role(organization_id));
create policy members_write on ${table} for update to authenticated
  using (better_supabase.has_organization_role(organization_id));
grant select, update on ${table} to authenticated;`;

export const crm: Recipe = {
  name: "crm",
  schema: "recipe_crm",
  tables: `create schema recipe_crm;
grant usage on schema recipe_crm to authenticated, service_role;
create table recipe_crm.deals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  name text not null,
  stage text not null default 'lead',
  rank text collate "C" not null default 'V'
);
create index on recipe_crm.deals (organization_id, stage, rank);
${readable("recipe_crm.deals")}`,
  config: defineConfig({
    preset: "crm",
    subjects: {
      deal: {
        table: "recipe_crm.deals",
        idType: "uuid",
        title: "name",
        url: "/deals/{id}",
        rank: { column: "rank", group: "stage" },
      },
    },
    blocks: {
      rank: {},
      reminders: {},
      "state-machine": {
        options: {
          machines: {
            deal: {
              table: "recipe_crm.deals",
              column: "stage",
              initial: "lead",
              tenant: "organization_id",
              transitions: {
                lead: ["qualified", "lost"],
                qualified: ["won", "lost"],
                won: [],
                lost: ["lead"],
              },
            },
          },
        },
      },
    },
  }),
};

export const projectManagement: Recipe = {
  name: "project-management",
  schema: "recipe_pm",
  tables: `create schema recipe_pm;
grant usage on schema recipe_pm to authenticated, service_role;
create table recipe_pm.tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  title text not null,
  status text not null default 'todo',
  rank text collate "C" not null default 'V'
);
create index on recipe_pm.tasks (organization_id, status, rank);
${readable("recipe_pm.tasks")}`,
  config: defineConfig({
    preset: "projects",
    subjects: {
      task: {
        table: "recipe_pm.tasks",
        idType: "uuid",
        title: "title",
        url: "/tasks/{id}",
        rank: { column: "rank", group: "status" },
      },
    },
    blocks: {
      "number-sequences": {},
      "state-machine": {
        options: {
          machines: {
            task: {
              table: "recipe_pm.tasks",
              column: "status",
              initial: "todo",
              tenant: "organization_id",
              transitions: {
                todo: ["doing"],
                doing: ["todo", "done"],
                done: ["doing"],
              },
            },
          },
        },
      },
    },
  }),
};

export const drive: Recipe = {
  name: "drive",
  schema: "recipe_drive",
  tables: `create schema recipe_drive;
grant usage on schema recipe_drive to authenticated, service_role;
create table recipe_drive.documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  name text not null,
  folder text not null default 'root',
  rank text collate "C" not null default 'V'
);
${readable("recipe_drive.documents")}`,
  config: defineConfig({
    preset: "saas",
    subjects: {
      document: {
        table: "recipe_drive.documents",
        idType: "uuid",
        title: "name",
        url: "/files/{id}",
        rank: { column: "rank", group: "folder" },
      },
    },
    blocks: {
      comments: {},
      tags: {},
      attachments: {},
      "share-links": {},
      rank: {},
    },
  }),
};

export const scheduling: Recipe = {
  name: "scheduling",
  schema: "recipe_scheduling",
  tables: `create schema recipe_scheduling;
grant usage on schema recipe_scheduling to authenticated, service_role;
create table recipe_scheduling.bookings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  title text not null,
  status text not null default 'requested',
  starts_at timestamptz not null
);
${readable("recipe_scheduling.bookings")}`,
  config: defineConfig({
    preset: "scheduling",
    subjects: {
      booking: {
        table: "recipe_scheduling.bookings",
        idType: "uuid",
        title: "title",
        url: "/bookings/{id}",
      },
    },
    blocks: {
      "custom-fields": {},
      "share-links": {},
      "state-machine": {
        options: {
          machines: {
            booking: {
              table: "recipe_scheduling.bookings",
              column: "status",
              initial: "requested",
              tenant: "organization_id",
              transitions: {
                requested: ["confirmed", "cancelled"],
                confirmed: ["cancelled"],
                cancelled: [],
              },
            },
          },
        },
      },
    },
  }),
};

/**
 * The commerce page's metrics: orders, revenue and order value from the orders
 * block, units from paid lines.
 */
export const commerceMetrics = [
  ...orderMetrics({ currency: "EUR" }),
  defineMetric({
    key: "units_sold",
    label: "Units sold",
    table: "recipe_commerce.units_sold",
    tenant: "tenant_id",
    measure: { sum: "quantity" },
    timeColumn: "paid_at",
  }),
] as const;

/** Refunds above this many cents need an approved `refund` request on the order. */
export const REFUND_APPROVAL_ABOVE = 5000;

/**
 * Percentage promotions above this need an approved `activate` request on the
 * promotion.
 */
export const PROMOTION_APPROVAL_ABOVE = 30;

export const commerce: Recipe = {
  name: "commerce",
  schema: "recipe_commerce",
  // Products, carts and orders are module tables; the app adds none.
  tables: "",
  // Order lines carry no time, so units sold reads them through their paid order.
  after: `create schema recipe_commerce;
grant usage on schema recipe_commerce to authenticated, service_role;
create view recipe_commerce.units_sold with (security_invoker = true) as
  select l.tenant_id, o.paid_at, l.quantity
  from better_supabase.order_lines l
  join better_supabase.orders o on o.id = l.order_id;
grant select on recipe_commerce.units_sold to authenticated, service_role;

create function public.after_refund_create(refund uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_refund record;
begin
  select r.order_id, r.amount into v_refund
  from better_supabase.order_refunds r where r.id = refund;
  if v_refund.amount > ${String(REFUND_APPROVAL_ABOVE)}
    and not better_supabase.is_approved('order', v_refund.order_id::text, 'refund') then
    raise exception 'a refund above 50.00 needs an approved refund request'
      using errcode = '42501', hint = 'REFUND_APPROVAL_REQUIRED';
  end if;
end;
$$;
revoke execute on function public.after_refund_create(uuid) from public, anon, authenticated;

create function public.before_promotion_activate(promotion uuid)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1 from better_supabase.promotions p
    where p.id = promotion and p.kind = 'percentage'
      and p.percent > ${String(PROMOTION_APPROVAL_ABOVE)}
  ) and not better_supabase.is_approved('promotion', promotion::text, 'activate') then
    raise exception 'a discount above ${String(PROMOTION_APPROVAL_ABOVE)} percent needs an approved activate request'
      using errcode = '42501', hint = 'PROMOTION_APPROVAL_REQUIRED';
  end if;
end;
$$;
revoke execute on function public.before_promotion_activate(uuid) from public, anon, authenticated;`,
  config: defineConfig({
    preset: "commerce",
    subjects: {
      order: {
        table: "better_supabase.orders",
        idType: "uuid",
        tenant: "tenant_id",
        title: "number",
      },
      promotion: {
        table: "better_supabase.promotions",
        idType: "uuid",
        tenant: "tenant_id",
        title: "name",
      },
      product: {
        table: "better_supabase.products",
        idType: "uuid",
        tenant: "tenant_id",
        title: "title",
        url: "/admin/products/{id}",
        search: { body: ["description"] },
      },
      // The shared stack indexes variants (the Next.js example installs
      // catalogSubjects), and reinstalling search keeps that trigger.
      product_variant: {
        table: "better_supabase.product_variants",
        idType: "uuid",
        tenant: "tenant_id",
        title: "sku",
        search: { body: ["title", "barcode"] },
      },
    },
    blocks: {
      imports: {},
      "number-sequences": {
        options: {
          entities: {
            order: { period: "none", format: "SO-{n:4}" },
            invoice: { period: "year", format: "INV-{yyyy}-{n:5}" },
          },
        },
      },
      search: {},
      "saved-views": {},
      metrics: { options: { metrics: commerceMetrics } },
      approvals: {
        options: {
          policies: {
            order: { refund: { steps: [{ approvers: { role: "admin" } }] } },
            promotion: {
              activate: { steps: [{ approvers: { role: "admin" } }] },
            },
          },
        },
      },
    },
  }),
};

export const RECIPES: readonly Recipe[] = [
  crm,
  projectManagement,
  drive,
  scheduling,
  commerce,
];
