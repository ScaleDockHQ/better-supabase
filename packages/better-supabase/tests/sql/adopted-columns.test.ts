import { describe, expect, it } from "vitest";

import { adoptedColumnProblems } from "../../src/sql/adopted-columns.ts";

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
});
