import { describe, expect, it } from "vitest";

import {
  adoptedColumnProblems,
  adoptedTables,
} from "../../src/sql/adopted-columns.ts";

describe("adoptedColumnProblems", () => {
  it("refuses a default optional column the adopted table does not declare", () => {
    const problems = adoptedColumnProblems(
      {
        organizations: {
          mode: "adopt",
          tables: { organizations: "public.organizations" },
        },
      },
      [
        {
          text: `create table public.organizations (
  id uuid primary key,
  name text not null,
  slug text
);`,
        },
      ],
      ["public"],
    );

    expect(problems.join("\n")).toContain("disabled_at");
    expect(problems.join("\n")).toContain("deleted_at");
  });

  it("passes when the missing columns are mapped to null", () => {
    expect(
      adoptedColumnProblems(
        {
          organizations: {
            mode: "adopt",
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
        [
          {
            text: `create table public.organizations (
  id uuid primary key,
  name text not null
);`,
          },
        ],
        ["public"],
      ),
    ).toEqual([]);
  });

  it("skips the columns a module adds or does not read under its options", () => {
    const events = {
      text: `create table public.app_events (
  id bigint generated always as identity primary key,
  type text not null,
  payload jsonb not null,
  created_at timestamptz not null
);`,
    };

    expect(
      adoptedColumnProblems(
        {
          outbox: {
            mode: "adopt",
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
        [events],
        ["public"],
      ),
    ).toEqual([]);

    const secrets = (column: string) => ({
      text: `create table public.hook_secrets (
  id uuid primary key,
  endpoint_id uuid not null,
  organization_id uuid not null,
  ${column},
  expires_at timestamptz,
  created_at timestamptz not null
);`,
    });

    const webhooks = (secretStorage: string) => ({
      "webhooks-out": {
        mode: "adopt" as const,
        tables: { secrets: "public.hook_secrets" },
        options: { secretStorage },
      },
    });

    expect(
      adoptedColumnProblems(
        webhooks("vault"),
        [secrets("vault_secret_id uuid not null")],
        ["public"],
      ),
    ).toEqual([]);
    expect(
      adoptedColumnProblems(
        webhooks("column"),
        [secrets("secret text not null")],
        ["public"],
      ),
    ).toEqual([]);
    expect(
      adoptedColumnProblems(
        webhooks("column"),
        [secrets("vault_secret_id uuid not null")],
        ["public"],
      ).join("\n"),
    ).toContain("public.hook_secrets.secret (secrets.secret)");
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
        mode: "adopt" as const,
        tables: { tags: "public.org_tags", taggings: null },
        columns: { tags: { tenant: "organization_id", rank: null } },
      },
    };

    expect(adoptedColumnProblems(tags, files, ["public"])).toEqual([]);

    expect(
      adoptedColumnProblems(
        { outbox: { mode: "adopt", tables: { events: "public.app_events" } } },
        files,
        ["public"],
      ),
    ).toEqual([
      "blocks.outbox writes text into public.app_events.type (events.type), which is the enum public.tag_kind. Postgres does not cast text to an enum, so the module's functions fail. Change the column to text with a check constraint on its values.",
    ]);

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

  it("lists the text columns each adopted table takes without a cast", () => {
    const [table] = adoptedTables({
      numbering: {
        mode: "adopt",
        tables: { sequences: "public.org_sequences" },
      },
    });

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
      adoptedTables({
        "state-machine": {
          mode: "adopt",
          tables,
          ...(options ? { options } : {}),
        },
      }).find((table) => table.logical === "history")?.textColumns;

    expect(history()).toEqual([]);
    expect(history({ machines })).toEqual([
      "subjectId",
      "fromStatus",
      "toStatus",
      "reason",
    ]);
  });
});
