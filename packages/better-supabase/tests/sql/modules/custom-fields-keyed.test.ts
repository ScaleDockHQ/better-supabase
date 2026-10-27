import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { modulePermissionKeys } from "../../../src/sql/introspect.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const OTHER = "99999999-9999-4999-8999-999999999999";
const ALICE = "22222222-2222-4222-8222-222222222222";
const PRODUCT = "44444444-4444-4444-8444-444444444444";
const ASSET = "55555555-5555-4555-8555-555555555555";
const FOREIGN = "66666666-6666-4666-8666-666666666666";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// An app's attribute table: one foreign key per record type with an
// exactly-one check, an enum type column whose label for bool is "boolean",
// and one value column per type, of which exactly the matching one is set.
const APP = `
create type public.attribute_type as enum ('text', 'number', 'boolean', 'date', 'url');

create table public.products (id uuid primary key, organization_id uuid not null);
create table public.assets (id uuid primary key, organization_id uuid not null);

create table public.attributes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  product_id uuid references public.products (id) on delete cascade,
  asset_id uuid references public.assets (id) on delete cascade,
  key text not null,
  label text not null,
  value_type public.attribute_type not null,
  text_value text,
  number_value numeric,
  boolean_value boolean,
  date_value date,
  url_value text,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attributes_one_target check (num_nonnulls(product_id, asset_id) = 1),
  constraint attributes_one_value check (
    case value_type
      when 'text' then text_value is not null and num_nonnulls(number_value, boolean_value, date_value, url_value) = 0
      when 'number' then number_value is not null and num_nonnulls(text_value, boolean_value, date_value, url_value) = 0
      when 'boolean' then boolean_value is not null and num_nonnulls(text_value, number_value, date_value, url_value) = 0
      when 'date' then date_value is not null and num_nonnulls(text_value, number_value, boolean_value, url_value) = 0
      when 'url' then url_value is not null and num_nonnulls(text_value, number_value, boolean_value, date_value) = 0
    end
  )
);
`;

const BLOCKS: AnyBlocksConfig = {
  "custom-fields": {
    tables: { definitions: null, options: null, values: "public.attributes" },
    columns: {
      values: {
        tenant: "organization_id",
        definition: null,
        subjectType: null,
        subjectId: null,
        optionId: null,
        valueJson: null,
        valueEmail: null,
        rank: null,
        valueText: "text_value",
        valueNumber: "number_value",
        valueBool: "boolean_value",
        valueDate: "date_value",
        valueUrl: "url_value",
        type: "value_type",
      },
    },
    values: { values: { type: { bool: "boolean" } } },
    on: {
      product: {
        table: "public.products",
        idType: "uuid",
        column: "product_id",
      },
      asset: { table: "public.assets", idType: "uuid", column: "asset_id" },
    },
    options: { layout: "keyed" },
  },
};

const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into public.products (id, organization_id) values ('${PRODUCT}', '${TENANT}'), ('${FOREIGN}', '${OTHER}');
insert into public.assets (id, organization_id) values ('${ASSET}', '${TENANT}');
`;

const AS_ALICE = `perform set_config('request.jwt.claims', '{"sub":"${ALICE}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${ALICE}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const BOOT = { timeout: 60_000 };

const sqlOf = (modules: AnyBlocksConfig = BLOCKS) =>
  renderBlocks(["custom-fields"], {
    modules,
    ownTables: { "public.attributes": "app.sql" },
  });

async function run(
  check: string,
  files = sqlOf(),
  allow = ALLOW,
): Promise<void> {
  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      APP,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      allow,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("custom-fields keyed layout over the app's table", BOOT, () => {
  it("writes typed values into per-record columns and reads them back as labels", async () => {
    await expect(
      run(`do $$
declare
  v_row jsonb;
  v_list jsonb;
  v_hint text;
begin
  ${AS_ALICE}
  v_row := better_supabase.set_field_value('${TENANT}', 'product', '${PRODUCT}', 'color', 'Color', 'text', '"red"');
  if v_row ->> 'value' <> 'red' or v_row ->> 'subjectType' <> 'product' or v_row ->> 'subjectId' <> '${PRODUCT}' then
    raise exception 'text %', v_row;
  end if;
  perform better_supabase.set_field_value('${TENANT}', 'product', '${PRODUCT}', 'color', 'Colour', 'number', '3');
  if (select count(*) from public.attributes) <> 1
    or (select number_value from public.attributes) <> 3
    or (select text_value from public.attributes) is not null
    or (select label from public.attributes) <> 'Colour' then
    raise exception 'upsert %', (select jsonb_agg(a) from public.attributes a);
  end if;
  v_row := better_supabase.set_field_value('${TENANT}', 'asset', '${ASSET}', 'insured', 'Insured', 'bool', 'true');
  if (select value_type::text from public.attributes where asset_id = '${ASSET}') <> 'boolean'
    or v_row ->> 'type' <> 'bool' or (v_row -> 'value')::boolean is not true then
    raise exception 'bool %', v_row;
  end if;
  perform better_supabase.set_field_value('${TENANT}', 'asset', '${ASSET}', 'manual', 'Manual', 'url', '"https://example.test"');
  if (select url_value from public.attributes where key = 'manual') <> 'https://example.test' then
    raise exception 'url column';
  end if;
  v_list := better_supabase.read_field_values('${TENANT}', 'asset', '${ASSET}');
  if jsonb_array_length(v_list) <> 2 or v_list -> 0 ->> 'key' <> 'insured' or v_list -> 1 ->> 'value' <> 'https://example.test' then
    raise exception 'read %', v_list;
  end if;
  begin
    perform better_supabase.set_field_value('${TENANT}', 'asset', '${ASSET}', 'insured', 'Insured', 'bool', 'false', null, true);
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint <> 'FIELD_EXISTS' then
    raise exception 'if_absent %', v_hint;
  end if;
  begin
    perform better_supabase.set_field_value('${TENANT}', 'product', '${FOREIGN}', 'color', 'Color', 'text', '"x"');
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint <> 'FIELD_SUBJECT_FORBIDDEN' then
    raise exception 'foreign record %', v_hint;
  end if;
  if not better_supabase.delete_field_value((v_row ->> 'id')::uuid) then
    raise exception 'delete';
  end if;
  if exists (select 1 from public.attributes where key = 'insured') then
    raise exception 'still there';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses null subject columns outside keyed layout or without a column per record", () => {
    const entry = BLOCKS["custom-fields"]!;

    expect(() =>
      sqlOf({ "custom-fields": { ...entry, options: { layout: "inline" } } }),
    ).toThrow(/can be null only with layout "keyed"/u);
    expect(() =>
      sqlOf({
        "custom-fields": {
          ...entry,
          on: { product: { table: "public.products", idType: "uuid" } },
        },
      }),
    ).toThrow(/a column in every/u);
  });

  it("keeps a managed keyed table polymorphic, with a unique key per subject", () => {
    const sql = renderBlocks(["custom-fields"], {
      modules: { "custom-fields": { options: { layout: "keyed" } } },
    })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      'unique ("tenant_id", "subject_type", "subject_id", "key")',
    );
    expect(sql).toContain("delete_field_value");
    expect(sql).not.toContain("save_field_definition");
  });

  it("ranks by an integer column of the app's own type", async () => {
    const entry = BLOCKS["custom-fields"]!;

    const modules: AnyBlocksConfig = {
      "custom-fields": {
        ...entry,
        columns: { values: { ...entry.columns!["values"], rank: "position" } },
        options: { layout: "keyed", rankType: "integer" },
      },
    };

    const sql = sqlOf(modules)
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain('collate "C"');

    await expect(
      run(
        `do $$
declare
  v_row jsonb;
  v_list jsonb;
  v_hint text;
begin
  ${AS_ALICE}
  perform better_supabase.set_field_value('${TENANT}', 'product', '${PRODUCT}', 'b', 'B', 'text', '"b"', '10');
  v_row := better_supabase.set_field_value('${TENANT}', 'product', '${PRODUCT}', 'a', 'A', 'text', '"a"', '9');
  if v_row ->> 'rank' <> '9' then
    raise exception 'rank %', v_row;
  end if;
  perform better_supabase.set_field_value('${TENANT}', 'product', '${PRODUCT}', 'a', 'A', 'text', '"a"');
  v_list := better_supabase.read_field_values('${TENANT}', 'product', '${PRODUCT}');
  if v_list -> 0 ->> 'key' <> 'a' or v_list -> 1 ->> 'key' <> 'b' then
    raise exception 'order %', v_list;
  end if;
  v_row := better_supabase.set_field_value('${TENANT}', 'product', '${PRODUCT}', 'd', 'D', 'text', '"d"');
  if v_row ->> 'rank' <> '11' then
    raise exception 'appended rank %', v_row;
  end if;
  begin
    perform better_supabase.set_field_value('${TENANT}', 'product', '${PRODUCT}', 'c', 'C', 'text', '"c"', 'x');
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint <> 'FIELD_VALUE_INVALID' then
    raise exception 'rank text %', v_hint;
  end if;
end;
$$;`,
        sqlOf(modules),
      ),
    ).resolves.toBeUndefined();
  });

  it("keeps an integer rank column on a managed keyed table", () => {
    const sql = renderBlocks(["custom-fields"], {
      modules: {
        "custom-fields": { options: { layout: "keyed", rankType: "integer" } },
      },
    })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain('"rank" integer');
    expect(sql).toContain('"rank"::text');
    expect(sql).toContain('v."rank" nulls last');
  });

  it("reads values by the record's own read check with readAccess record", async () => {
    const entry = BLOCKS["custom-fields"]!;

    const subjects = {
      product: {
        table: "public.products",
        idType: "uuid",
        permissions: { read: "product.read" },
      },
      asset: { table: "public.assets", idType: "uuid" },
    };

    const modules: AnyBlocksConfig = {
      "custom-fields": {
        ...entry,
        options: { layout: "keyed", readAccess: "record" },
      },
    };

    const files = renderBlocks(["subjects", "custom-fields"], {
      modules,
      subjects,
      ownTables: { "public.attributes": "app.sql" },
    });

    const sql = files.map((file) => file.contents).join("\n");

    expect(sql).toContain('can_subject"(read_field_values.subject_type');

    const deny = ALLOW.replace(
      "returns boolean language sql stable as $$ select true $$;",
      () =>
        "returns boolean language sql stable as $$ select permission not in ('product.read', 'custom_fields.read') $$;",
    );

    await expect(
      run(
        `do $$
declare
  v_list jsonb;
begin
  insert into public.attributes (organization_id, product_id, key, label, value_type, text_value)
  values ('${TENANT}', '${PRODUCT}', 'color', 'Color', 'text', 'red');
  insert into public.attributes (organization_id, asset_id, key, label, value_type, text_value)
  values ('${TENANT}', '${ASSET}', 'serial', 'Serial', 'text', 'A1');
  ${AS_ALICE}
  v_list := better_supabase.read_field_values('${TENANT}', 'asset', '${ASSET}');
  if jsonb_array_length(v_list) <> 1 then
    raise exception 'asset %', v_list;
  end if;
  v_list := better_supabase.read_field_values('${TENANT}', 'product', '${PRODUCT}');
  if jsonb_array_length(v_list) <> 0 then
    raise exception 'product %', v_list;
  end if;
  v_list := better_supabase.read_field_values('${OTHER}', 'asset', '${ASSET}');
  if jsonb_array_length(v_list) <> 0 then
    raise exception 'other tenant %', v_list;
  end if;
end;
$$;`,
        files,
        deny,
      ),
    ).resolves.toBeUndefined();
  });

  it("reports no sensitive key in keyed layout and no read key with readAccess record", () => {
    const actions = (options: Record<string, unknown>) =>
      modulePermissionKeys({ "custom-fields": { options } }, [
        "custom-fields",
      ]).map((entry) => entry.action);

    expect(actions({})).toContain("sensitive");
    expect(actions({ layout: "keyed" })).toEqual(["manage", "read"]);
    expect(actions({ layout: "keyed", readAccess: "record" })).toEqual([
      "manage",
    ]);
  });

  it("refuses unknown keyed options and keyed options in another layout", () => {
    const keyed = (options: Record<string, unknown>) => () =>
      renderBlocks(["custom-fields"], {
        modules: { "custom-fields": { options } },
      });

    expect(keyed({ layout: "keyed", rankType: "float" })).toThrow(
      /rankType must be/u,
    );
    expect(keyed({ layout: "keyed", readAccess: "any" })).toThrow(
      /readAccess must be/u,
    );
    expect(keyed({ layout: "keyed", readAccess: "record" })).toThrow(
      /add the subjects block/u,
    );
    expect(keyed({ rankType: "integer" })).toThrow(
      /apply only to layout "keyed"/u,
    );
  });
});
