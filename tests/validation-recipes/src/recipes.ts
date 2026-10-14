import { defineConfig } from "better-supabase/config";

// The configs on the Recipes docs pages, with the app tables in a schema of
// their own instead of `public`. Each recipe also names the tables it creates,
// so a test can install it on an empty schema. A state machine is keyed by its
// subject type, so its status.changed events reach the subject's watchers.

export interface Recipe {
  readonly name: string;
  readonly schema: string;
  readonly config: ReturnType<typeof defineConfig>;
  /** The app's own tables, created before the module files. */
  readonly tables: string;
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
    subjects: {
      deal: {
        table: "recipe_crm.deals",
        idType: "uuid",
        title: "name",
        url: "/deals/{id}",
        rank: { column: "rank", group: "stage" },
      },
    },
    sql: {
      modules: {
        organizations: {},
        outbox: {},
        notifications: {},
        comments: {},
        tags: {},
        "custom-fields": {},
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
    subjects: {
      task: {
        table: "recipe_pm.tasks",
        idType: "uuid",
        title: "title",
        url: "/tasks/{id}",
        rank: { column: "rank", group: "status" },
      },
    },
    sql: {
      modules: {
        organizations: {},
        teams: {},
        outbox: {},
        notifications: {},
        comments: {},
        tags: {},
        rank: {},
        reminders: {},
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
    subjects: {
      document: {
        table: "recipe_drive.documents",
        idType: "uuid",
        title: "name",
        url: "/files/{id}",
        rank: { column: "rank", group: "folder" },
      },
    },
    sql: {
      modules: {
        organizations: {},
        outbox: {},
        notifications: {},
        comments: {},
        tags: {},
        attachments: {},
        "share-links": {},
        rank: {},
      },
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
    subjects: {
      booking: {
        table: "recipe_scheduling.bookings",
        idType: "uuid",
        title: "title",
        url: "/bookings/{id}",
      },
    },
    sql: {
      modules: {
        organizations: {},
        outbox: {},
        notifications: {},
        "custom-fields": {},
        "share-links": {},
        reminders: {},
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
    },
  }),
};

export const commerce: Recipe = {
  name: "commerce",
  schema: "recipe_commerce",
  // Products, carts and orders are module tables; the app adds none.
  tables: "",
  config: defineConfig({
    sql: {
      modules: {
        organizations: {},
        outbox: {},
        notifications: {},
        catalog: {},
        inventory: {},
        imports: {},
        "number-sequences": {
          options: {
            entities: {
              order: { period: "none", format: "SO-{n:4}" },
              invoice: { period: "year", format: "INV-{yyyy}-{n:5}" },
            },
          },
        },
        orders: {},
        promotions: {},
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
