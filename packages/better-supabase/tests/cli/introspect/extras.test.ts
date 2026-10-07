import { describe, expect, it } from "vitest";

import { readExtras } from "../../../src/cli/introspect/extras.ts";
import { fakeSql } from "../fixtures/fake-sql.ts";

const catalog = (present: { buckets?: boolean } = {}) =>
  fakeSql([
    ["to_regclass('storage.buckets')", [{ present: present.buckets ?? true }]],
    [
      "c.reltuples >=",
      [
        { id: "10", schema: "public", name: "notes", large: false },
        { id: 11, schema: "public", name: "events", large: true },
      ],
    ],
    [
      "from pg_constraint con",
      [
        {
          table_id: "10",
          name: "notes_pkey",
          type: "p",
          columns: ["org_id", "id"],
          on_delete: " ",
          on_update: " ",
          definition: "PRIMARY KEY (org_id, id)",
        },
        {
          table_id: 10,
          name: "notes_slug_key",
          type: "u",
          columns: ["slug"],
          on_delete: " ",
          on_update: " ",
          definition: "UNIQUE (slug)",
        },
        {
          table_id: 10,
          name: "notes_organization_fkey",
          type: "f",
          columns: ["org_id"],
          on_delete: "c",
          on_update: "z",
          definition: "FOREIGN KEY ...",
        },
        {
          table_id: 10,
          name: "notes_title_check",
          type: "c",
          columns: ["title"],
          on_delete: " ",
          on_update: " ",
          definition: "CHECK (length(title) > 0)",
        },
      ],
    ],
    [
      "from pg_index ix",
      [
        {
          table_id: 10,
          name: "notes_pkey",
          unique: true,
          primary: true,
          partial: false,
          columns: ["org_id", "id"],
        },
        {
          table_id: 10,
          name: "notes_slug_key",
          unique: true,
          primary: false,
          partial: false,
          columns: ["slug"],
        },
        {
          table_id: 10,
          name: "notes_lower_title",
          unique: true,
          primary: false,
          partial: false,
          columns: ["title"],
        },
        {
          table_id: 10,
          name: "notes_live_title",
          unique: true,
          primary: false,
          partial: true,
          method: "btree",
          predicate: "(deleted_at IS NULL)",
          columns: ["title"],
        },
        {
          table_id: 10,
          name: "notes_organization_idx",
          unique: false,
          primary: false,
          partial: false,
          columns: ["org_id"],
        },
      ],
    ],
    [
      "from pg_policies p",
      [
        {
          table_id: 10,
          name: "notes_read",
          permissive: true,
          roles: ["authenticated"],
          command: "select",
          using_expr: "org_id = current_org()",
          check_expr: null,
          functions: ["public.current_org"],
        },
        {
          table_id: 11,
          name: "events_insert",
          permissive: false,
          roles: ["anon"],
          command: "insert",
          using_expr: null,
          check_expr: "true",
          functions: null,
        },
      ],
    ],
    [
      "from pg_trigger t",
      [
        {
          table_id: 10,
          name: "notes_touch",
          function: "public.touch",
          timing: "before",
          events: ["update"],
          level: "row",
        },
      ],
    ],
    [
      "aclexplode(coalesce(c.relacl",
      [{ table_id: 10, role: "authenticated", privileges: ["SELECT"] }],
    ],
    [
      "aclexplode(a.attacl)",
      [
        {
          table_id: 10,
          column: "title",
          role: "authenticated",
          privileges: ["UPDATE"],
        },
      ],
    ],
    [
      "from storage.buckets",
      [
        {
          id: "avatars",
          public: true,
          file_size_limit: "1048576",
          allowed_mime_types: ["image/png"],
        },
        {
          id: "docs",
          public: false,
          file_size_limit: null,
          allowed_mime_types: null,
        },
      ],
    ],
    ["from pg_publication_tables", [{ name: "public.notes" }]],
    [
      "pg_db_role_setting",
      [
        {
          role: "authenticator",
          config: ["statement_timeout=8s", "pgrst.db_aggregates_enabled=true"],
        },
        { role: "authenticator", config: ["statement_timeout=10s", "bad"] },
        { role: "anon", config: null },
      ],
    ],
    [
      "as public_execute",
      [
        {
          schema: "rbac",
          name: "hook",
          signature: "event jsonb",
          language: "plpgsql",
          volatility: "s",
          security_definer: false,
          config: ["search_path="],
          execute: ["supabase_auth_admin"],
          public_execute: false,
          schema_usage: ["supabase_auth_admin"],
          source: "begin return event; end",
        },
        {
          schema: "rbac",
          name: "hook",
          signature: "",
          language: "sql",
          volatility: "v",
          security_definer: true,
          config: null,
          execute: [],
          public_execute: true,
          schema_usage: [],
          source: null,
        },
        {
          schema: "other",
          name: "unrelated",
          signature: "",
          language: "sql",
          volatility: "i",
          security_definer: false,
          config: null,
          execute: [],
          public_execute: false,
          schema_usage: [],
          source: null,
        },
      ],
    ],
    [
      "from pg_proc p",
      [
        {
          schema: "public",
          name: "current_org",
          signature: "",
          language: "sql",
          volatility: "s",
          security_definer: true,
          config: ["search_path=", "statement_timeout=5s"],
          execute: ["authenticated"],
        },
        {
          schema: "public",
          name: "pure",
          signature: "x int",
          language: "sql",
          volatility: "i",
          security_definer: false,
          config: null,
          execute: ["anon", "authenticated"],
        },
      ],
    ],
  ]);

describe("readExtras", () => {
  it("joins the catalog rows into one record per relation", async () => {
    const db = catalog();
    const extras = await readExtras(db.pg, ["public", "it's"]);

    expect(db.texts()[0]).toContain("array['public', 'it''s']::text[]");
    const [notes, events] = extras.tables;
    expect(notes).toEqual({
      id: 10,
      schema: "public",
      name: "notes",
      primaryKey: ["org_id", "id"],
      uniques: [
        { name: "notes_slug_key", columns: ["slug"] },
        { name: "notes_lower_title", columns: ["title"] },
      ],
      foreignKeys: [
        {
          name: "notes_organization_fkey",
          onDelete: "cascade",
          onUpdate: "no action",
        },
      ],
      checks: [
        { name: "notes_title_check", definition: "CHECK (length(title) > 0)" },
      ],
      indexes: [
        {
          name: "notes_pkey",
          columns: ["org_id", "id"],
          unique: true,
          primary: true,
          partial: false,
        },
        {
          name: "notes_slug_key",
          columns: ["slug"],
          unique: true,
          primary: false,
          partial: false,
        },
        {
          name: "notes_lower_title",
          columns: ["title"],
          unique: true,
          primary: false,
          partial: false,
        },
        {
          name: "notes_live_title",
          columns: ["title"],
          unique: true,
          primary: false,
          partial: true,
          method: "btree",
          predicate: "(deleted_at IS NULL)",
        },
        {
          name: "notes_organization_idx",
          columns: ["org_id"],
          unique: false,
          primary: false,
          partial: false,
        },
      ],
      policies: [
        {
          name: "notes_read",
          command: "select",
          roles: ["authenticated"],
          permissive: true,
          using: "org_id = current_org()",
          check: null,
          functions: ["public.current_org"],
        },
      ],
      triggers: [
        {
          name: "notes_touch",
          timing: "before",
          events: ["update"],
          level: "row",
          function: "public.touch",
        },
      ],
      grants: [{ role: "authenticated", privileges: ["SELECT"] }],
      columnGrants: [
        { column: "title", role: "authenticated", privileges: ["UPDATE"] },
      ],
    });
    expect(events).toEqual({
      id: 11,
      schema: "public",
      name: "events",
      primaryKey: [],
      uniques: [],
      foreignKeys: [],
      checks: [],
      indexes: [],
      policies: [
        {
          name: "events_insert",
          command: "insert",
          roles: ["anon"],
          permissive: false,
          using: null,
          check: "true",
          functions: [],
        },
      ],
      triggers: [],
      grants: [],
      columnGrants: [],
      large: true,
    });
  });

  it("reads buckets, realtime, role settings and functions", async () => {
    const extras = await readExtras(catalog().pg, ["public"]);
    expect(extras.buckets).toEqual([
      {
        id: "avatars",
        public: true,
        fileSizeLimit: 1048576,
        allowedMimeTypes: ["image/png"],
      },
      {
        id: "docs",
        public: false,
        fileSizeLimit: null,
        allowedMimeTypes: null,
      },
    ]);
    expect(extras.realtime).toEqual(["public.notes"]);
    expect(extras.roleSettings).toEqual({
      authenticator: {
        statement_timeout: "10s",
        "pgrst.db_aggregates_enabled": "true",
      },
      anon: {},
    });
    expect(extras.functions).toEqual([
      {
        schema: "public",
        name: "current_org",
        signature: "",
        language: "sql",
        volatility: "stable",
        securityDefiner: true,
        settings: { search_path: "", statement_timeout: "5s" },
        execute: ["authenticated"],
      },
      {
        schema: "public",
        name: "pure",
        signature: "x int",
        language: "sql",
        volatility: "immutable",
        securityDefiner: false,
        settings: {},
        execute: ["anon", "authenticated"],
      },
    ]);
    expect(extras).not.toHaveProperty("hooks");
  });

  it("skips service tables that do not exist", async () => {
    const db = catalog({ buckets: false });
    const extras = await readExtras(db.pg, ["public"]);
    expect(extras.buckets).toEqual([]);
    expect(
      db.texts().some((text) => text.includes("from storage.buckets")),
    ).toBe(false);
  });

  it("reads Auth hook functions with their ACLs, by target", async () => {
    const db = catalog();
    const extras = await readExtras(
      db.pg,
      ["public"],
      [
        { hook: "custom_access_token", schema: "rbac", name: "hook" },
        { hook: "send_email", schema: "public", name: "missing" },
      ],
    );
    expect(
      db.texts().find((text) => text.includes("as public_execute")),
    ).toContain("array['rbac.hook', 'public.missing']::text[]");
    expect(extras.hooks).toEqual([
      {
        hook: "custom_access_token",
        schema: "rbac",
        name: "hook",
        functions: [
          {
            schema: "rbac",
            name: "hook",
            signature: "event jsonb",
            language: "plpgsql",
            volatility: "stable",
            securityDefiner: false,
            settings: { search_path: "" },
            execute: ["supabase_auth_admin"],
            publicExecute: false,
            schemaUsage: ["supabase_auth_admin"],
            source: "begin return event; end",
          },
          {
            schema: "rbac",
            name: "hook",
            signature: "",
            language: "sql",
            volatility: "volatile",
            securityDefiner: true,
            settings: {},
            execute: [],
            publicExecute: true,
            schemaUsage: [],
          },
        ],
      },
      { hook: "send_email", schema: "public", name: "missing", functions: [] },
    ]);
  });
});
