import { describe, expect, it } from "vitest";

import {
  adoptedColumnProblems,
  adoptedTables,
} from "../../src/sql/adopted-columns.ts";

describe("adoptedColumnProblems", () => {
  it("leaves the columns the app's organizations table lacks to the block, which adds them", () => {
    const files = [
      {
        text: `create table public.organizations (
  id uuid primary key,
  name text not null,
  slug text
);`,
      },
    ];

    expect(
      adoptedColumnProblems(
        {
          organizations: { tables: { organizations: "public.organizations" } },
        },
        files,
        ["public"],
        { "public.organizations": "supabase/schemas/organizations.sql" },
      ),
    ).toEqual([]);
    expect(
      adoptedColumnProblems(
        {
          organizations: {
            tables: { organizations: "public.organizations" },
            columns: {
              organizations: {
                slug: null,
                createdBy: null,
                createdAt: null,
                updatedAt: null,
                deletedAt: null,
                disabledAt: null,
              },
            },
          },
        },
        files,
        ["public"],
        { "public.organizations": "supabase/schemas/organizations.sql" },
      ),
    ).toEqual([]);
  });

  it("finds nothing without the app's tables", () => {
    expect(
      adoptedTables({
        organizations: { tables: { organizations: "public.organizations" } },
      }),
    ).toEqual([]);
  });

  it("skips the columns a module maps to null or does not read under its options", () => {
    const events = adoptedTables(
      {
        outbox: {
          tables: { events: "public.app_events" },
          columns: {
            events: {
              position: "id",
              source: null,
              subject: null,
              tenant: null,
              key: null,
              actor: null,
            },
          },
        },
      },
      { "public.app_events": "supabase/schemas/events.sql" },
    ).find((table) => table.logical === "events");

    expect(events?.columns).toEqual({
      id: "id",
      position: "id",
      type: "type",
      payload: "payload",
      createdAt: "created_at",
    });

    const secrets = (secretStorage: string) =>
      Object.keys(
        adoptedTables(
          {
            "webhooks-out": {
              tables: { secrets: "public.hook_secrets" },
              options: { secretStorage },
            },
          },
          { "public.hook_secrets": "supabase/schemas/hooks.sql" },
        ).find((table) => table.logical === "secrets")?.columns ?? {},
      );

    expect(secrets("vault")).toContain("vaultId");
    expect(secrets("vault")).not.toContain("secret");
    expect(secrets("column")).toContain("secret");
    expect(secrets("column")).not.toContain("vaultId");
  });

  it("passes an enum locale on the app's profiles table, which the module casts", () => {
    const files = [
      {
        text: `create type public.app_locale as enum ('en', 'nl', 'de');
create table public.profiles (
  id uuid primary key,
  email text,
  username text,
  locale public.app_locale not null default 'en',
  created_at timestamptz not null,
  updated_at timestamptz not null
);`,
      },
    ];

    expect(
      adoptedColumnProblems(
        {
          profiles: {
            tables: { profiles: "public.profiles" },
            columns: { profiles: { locale: "locale" } },
          },
        },
        files,
        ["public"],
        { "public.profiles": "supabase/schemas/profiles.sql" },
      ),
    ).toEqual([]);
  });

  it("refuses an enum column the module writes as text, and passes one it casts", () => {
    const files = [
      {
        text: `create type public.tag_kind as enum ('task', 'customer');
create table public.org_tags (
  id uuid primary key,
  organization_id uuid not null,
  kind public.tag_kind not null,
  name text not null,
  slug text not null,
  color text,
  description text,
  created_at timestamptz not null,
  updated_at timestamptz not null
);
create table public.app_events (
  id uuid primary key,
  position bigint not null,
  type public.tag_kind not null,
  source text,
  subject text,
  organization_id uuid,
  key text,
  payload jsonb not null,
  actor_id uuid,
  created_at timestamptz not null,
  xid xid8 not null
);`,
      },
    ];

    const tags = {
      tags: {
        tables: { tags: "public.org_tags", taggings: null },
        columns: { tags: { tenant: "organization_id", rank: null } },
      },
    };

    expect(
      adoptedColumnProblems(tags, files, ["public"], {
        "public.org_tags": "supabase/schemas/tags.sql",
      }),
    ).toEqual([]);

    expect(
      adoptedColumnProblems(
        { outbox: { tables: { events: "public.app_events" } } },
        files,
        ["public"],
        { "public.app_events": "supabase/schemas/events.sql" },
      ),
    ).toEqual([
      "blocks.outbox writes text into public.app_events.type (events.type), which is the enum public.tag_kind. Postgres does not cast text to an enum, so the module's functions fail. Change the column to text with a check constraint on its values.",
    ]);

    expect(
      adoptedColumnProblems(
        { tags: { tables: { tags: "public.org_tags" } } },
        files,
        ["public"],
        { "public.org_tags": "supabase/schemas/tags.sql" },
      ),
    ).toEqual([]);
  });

  it("lists the text columns each app table takes without a cast", () => {
    const [table] = adoptedTables(
      { numbering: { tables: { sequences: "public.org_sequences" } } },
      { "public.org_sequences": "supabase/schemas/sequences.sql" },
    );

    expect(table?.textColumns).toEqual(["period"]);
  });

  it("reads the writes the module's options add", () => {
    const tables = { history: "public.status_history" };

    const machines = {
      quote: {
        table: "public.quotes",
        column: "status",
        initial: "draft",
        transitions: { draft: ["sent"] },
      },
    };

    const history = (options?: Record<string, unknown>) =>
      adoptedTables(
        { "state-machine": { tables, ...(options ? { options } : {}) } },
        { "public.status_history": "supabase/schemas/history.sql" },
      ).find((table) => table.logical === "history")?.textColumns;

    expect(history()).toEqual([]);
    expect(history({ machines })).toEqual(["subjectId", "reason"]);
  });
});
