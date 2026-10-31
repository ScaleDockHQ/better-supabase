import { describe, expect, it } from "vitest";

import { driveSubject } from "../../../src/blocks/drive/subject.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";
import { ownTablesOf } from "../../fixtures/own-tables.ts";

const sqlOf = (
  layout: Parameters<typeof renderBlocks>[1] = {},
  blocks: readonly string[] = [],
): string =>
  renderBlocks(["custom-fields", ...blocks], layout)
    .filter((file) => file.module === "custom-fields")
    .map((file) => file.contents)
    .join("\n");

describe("custom-fields module", () => {
  it("appends a rank key per tenant and entity on a new definition", () => {
    const sql = sqlOf();
    expect(sql).toContain(`"rank" text collate "C" not null default 'V',`);
    expect(sql).toContain(
      `where d."tenant_id" = save_field_definition.tenant and d."entity" = save_field_definition.entity;`,
    );
    expect(sql).toContain(`do update set "label" = excluded."label"`);
    expect(sql).not.toMatch(/do update set[^\n]*"rank"/);
    expect(sql).toContain(
      `"rank_field_definition"(definition uuid, rank text)`,
    );
    expect(sql).not.toContain("position");
  });

  it("has no rank in the inline layout", () => {
    const sql = sqlOf({
      modules: { "custom-fields": { options: { layout: "inline" } } },
    });

    expect(sql).not.toContain("rank_field_definition");
    expect(sql).not.toContain(`"rank"`);
  });

  it("backfills rank keys in position order when upgrading from version 1", () => {
    const [plan] = upgradePlan([{ module: "custom-fields", version: 1 }]);
    expect(plan).toMatchObject({ module: "custom-fields", from: 1, to: 4 });
    const sql = plan!.steps[0]!.sql;
    expect(sql).toContain(
      `row_number() over (partition by "tenant_id", "entity" order by position, "key", "id") as nth`,
    );
    expect(sql).toContain(
      `alter table "better_supabase"."field_definitions" drop column if exists position;`,
    );
  });

  it("skips the upgrade for the inline layout", () => {
    const [plan] = upgradePlan([{ module: "custom-fields", version: 1 }], {
      modules: { "custom-fields": { options: { layout: "inline" } } },
    });

    expect(plan!.steps[0]!.sql).toBe("");
  });

  it("adds the encrypted flag when upgrading from version 2", () => {
    const [plan] = upgradePlan([{ module: "custom-fields", version: 2 }]);

    expect(plan).toMatchObject({ module: "custom-fields", from: 2, to: 4 });
    expect(plan!.steps[0]!.sql).toBe(
      `alter table "better_supabase"."field_definitions" add column if not exists "encrypted" boolean not null default false;`,
    );
  });

  it("skips the encrypted flag for the inline layout", () => {
    const [plan] = upgradePlan([{ module: "custom-fields", version: 2 }], {
      modules: { "custom-fields": { options: { layout: "inline" } } },
    });

    expect(plan!.steps[0]!.sql).toBe("");
  });

  it("encrypts and decrypts text values with the field-encryption block", () => {
    const sql = sqlOf({}, ["field-encryption"]);

    expect(sql).toContain(`"encrypted" boolean not null default false,`);
    expect(sql).toContain(`"encrypt_field_definition"(definition uuid)`);
    expect(sql).toContain(
      `then "better_supabase"."field_encrypt"('tenant:' || set_field_value.tenant::text, set_field_value.value)`,
    );
    expect(sql).toContain(
      `case when coalesce(d."encrypted", false) then "better_supabase"."field_open"(v_key, v."value_text")`,
    );
    expect(sql).not.toContain("audit_event");
  });

  it("stores plaintext without the field-encryption block", () => {
    const sql = sqlOf();

    expect(sql).not.toContain("encrypt_field_definition");
    expect(sql).not.toContain("field_open");
  });

  it("adds the encrypted flag to the app's definitions table", () => {
    const overApp = (columns: Record<string, Record<string, null>> = {}) => {
      const modules = {
        "custom-fields": {
          tables: {
            definitions: "app.field_definitions",
            options: "app.field_options",
            values: "app.field_values",
          },
          columns,
        },
      };

      return sqlOf({ modules, ownTables: ownTablesOf(modules) });
    };

    expect(overApp()).toContain(
      `alter table "app"."field_definitions" add column if not exists "encrypted" boolean not null default false;`,
    );
    expect(overApp()).not.toContain(
      `create table if not exists "app"."field_definitions"`,
    );
    expect(overApp({ definitions: { encrypted: null } })).not.toContain(
      `"encrypted"`,
    );
  });

  it("audits protected reads once per call with auditReads", () => {
    const sql = sqlOf(
      { modules: { "custom-fields": { options: { auditReads: true } } } },
      ["field-encryption", "audit"],
    );

    expect(sql).toContain("event_type => 'field_value.viewed'");
    expect(sql).toContain("category => 'read'");
    expect(sql).toContain(
      `jsonb_agg(v."id") filter (where coalesce(d."encrypted", false) or coalesce(d."sensitive", false))`,
    );
  });

  it("audits every read in the inline layout", () => {
    const sql = sqlOf(
      {
        modules: {
          "custom-fields": { options: { layout: "inline", auditReads: true } },
        },
      },
      ["audit"],
    );

    expect(sql).toContain(`jsonb_agg(v."id") filter (where true)`);
    expect(sql).not.toContain("encrypt_field_definition");
  });

  it("reads values of a record-checked type through the record", () => {
    const sql = sqlOf(
      {
        subjects: {
          drive_node: driveSubject(),
          task: {
            table: "public.tasks",
            idType: "bigint",
            permissions: { read: "tasks.read" },
          },
        },
      },
      ["subjects", "drive"],
    );

    expect(sql).toContain(
      `case when read_field_values.subject_type in ('drive_node') then case read_field_values.subject_type`,
    );
    expect(sql).toContain(
      `coalesce("better_supabase"."drive_node_readable"(s."id"), false)`,
    );
    expect(sql).toContain(
      `else coalesce(better_supabase.can('tenant', read_field_values.tenant, 'custom_fields.read'), false) end`,
    );
    expect(sql).toContain(
      `coalesce("better_supabase"."can_subject"(set_field_value.subject_type, set_field_value.subject_id, 'fields'), false)`,
    );
  });

  it("reads every type through the record with the readAccess option", () => {
    const sql = sqlOf(
      {
        subjects: {
          task: {
            table: "public.tasks",
            idType: "bigint",
            permissions: { read: "tasks.read" },
          },
        },
        modules: { "custom-fields": { options: { readAccess: "record" } } },
      },
      ["subjects"],
    );

    expect(sql).not.toContain("read_field_values.tenant, 'custom_fields.read'");
    expect(sql).toContain(
      `when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (read_field_values.subject_id)::bigint`,
    );
  });

  it("keeps the tenant read key without record-checked types", () => {
    expect(sqlOf()).toContain(
      `and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', read_field_values.tenant, 'custom_fields.read'), false))`,
    );
  });

  it("needs record types for the readAccess option", () => {
    expect(() =>
      sqlOf({
        modules: { "custom-fields": { options: { readAccess: "record" } } },
      }),
    ).toThrow(/readAccess "record" needs record types/u);
  });

  it("needs the audit block for auditReads", () => {
    expect(() =>
      sqlOf({
        modules: { "custom-fields": { options: { auditReads: true } } },
      }),
    ).toThrow("auditReads needs the audit block");
  });

  describe("registered entities, packs and per-entity values", () => {
    const registry = {
      subjects: {
        task: {
          table: "public.tasks",
          idType: "bigint",
          permissions: { read: "tasks.read" },
        },
      },
    } as const;

    it("rejects an entity that is not a registered subject type", () => {
      const sql = sqlOf(registry, ["subjects"]);

      expect(sql).toContain(
        `if save_field_definition.entity is null or save_field_definition.entity <> all (array['task']::text[]) then`,
      );
      expect(sql).toContain("FIELD_ENTITY_UNKNOWN");
    });

    it("leaves the entity free text without registered types", () => {
      expect(sqlOf()).not.toContain("FIELD_ENTITY_UNKNOWN");
    });

    it("installs a field pack idempotently by pack and key", () => {
      const sql = sqlOf(registry, ["subjects"]);

      expect(sql).toContain(
        'create or replace function "better_supabase"."install_field_pack"(tenant uuid, pack jsonb)',
      );
      expect(sql).toContain("FIELD_PACK_INVALID");
      expect(sql).toContain("FIELD_PACK_CONFLICT");
      expect(sql).toContain(`"pack" text,`);
      expect(sql).toContain(`"pack_version" integer,`);
    });

    it("has no pack function in the inline layout", () => {
      const sql = sqlOf({
        modules: { "custom-fields": { options: { layout: "inline" } } },
      });

      expect(sql).not.toContain("install_field_pack");
    });

    it("writes values by external key through an imports target", () => {
      const sql = sqlOf(registry, ["subjects", "imports"]);

      expect(sql).toContain("import_field_value");
      expect(sql).toContain("FIELD_VALUE_INVALID");
    });

    it("keeps values per legal entity with the legal-entities block", () => {
      const sql = sqlOf({}, [
        "memberships",
        "permissions",
        "settings",
        "legal-entities",
      ]);

      expect(sql).toContain(
        `read_field_values"(tenant uuid, subject_type text, subject_id text, legal_entity uuid default null)`,
      );
      expect(sql).toContain("x.legal_entity_id nulls last");
      expect(sql).toContain("legal_entity uuid default null)");
    });

    it("maps stored entities when upgrading from version 3", () => {
      const [plan] = upgradePlan([{ module: "custom-fields", version: 3 }], {
        modules: {
          "custom-fields": {
            options: { entityMap: { invoice: "sales_invoice" } },
          },
        },
      });

      expect(plan).toMatchObject({ module: "custom-fields", from: 3, to: 4 });
      expect(plan!.steps[0]!.sql).toContain(`set "entity" = 'sales_invoice'`);
      expect(plan!.steps[0]!.sql).toContain(
        `add column if not exists "pack" text`,
      );
    });
  });
});
