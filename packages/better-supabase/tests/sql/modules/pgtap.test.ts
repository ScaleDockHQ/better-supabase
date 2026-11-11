import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const body = (): string =>
  renderBlocks(["pgtap"], {})
    .filter((file) => file.module === "pgtap")
    .map((file) => file.contents)
    .join("\n");

describe("pgtap module", () => {
  it("looks users up in security definer helpers so an authenticated test can switch users", () => {
    const sql = body();

    expect(sql).toMatch(
      /function tests\._user_id_by_email\(user_email text\)\s+returns uuid\s+language sql\s+stable\s+security definer/u,
    );
    expect(sql).toMatch(
      /function tests\._email_of\(user_id uuid\)\s+returns text\s+language sql\s+stable\s+security definer/u,
    );
    expect(sql).toContain("found_id := tests._user_id_by_email(user_email);");
    expect(sql).not.toMatch(
      /from auth\.users u where u\.email = user_email;\n\s*if/u,
    );
  });

  it("keeps authenticate_as itself security invoker, since set role is refused in a definer", () => {
    expect(body()).toMatch(
      /function tests\.authenticate_as\(user_email text\)\s+returns void\s+language plpgsql\s+set search_path/u,
    );
  });
});

/** Lite migrates PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 120_000 };

// The pgtap extension is not in PGlite, and the helpers only call it in bodies.
const EXTENSION = /^create extension if not exists pgtap[^;]*;$/m;

const SETUP = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated;
  end if;
end;
$$;
create schema if not exists extensions;
create schema if not exists better_supabase;
create function extensions.is(anyelement, anyelement, text) returns text language sql as $f$ select 'ok' $f$;
create function extensions.plan(integer) returns text language sql as $f$ select 'ok' $f$;
create function extensions.pass(text) returns text language sql as $f$ select 'ok' $f$;
create function extensions.finish() returns setof text language sql as $f$ select 'ok' $f$;
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key, email text);
`;

describe("pgtap module in Postgres", BOOT, () => {
  it("loads with only the pgtap block installed", async () => {
    const files = renderBlocks(["pgtap"], {});
    expect(files.length).toBeGreaterThan(0);

    await using stack = await liteStack({
      driver: "pglite",
      seed: [
        SETUP,
        ...files.map((file) => file.contents.replace(EXTENSION, "")),
      ],
    });

    expect(stack.url).not.toBe("");
  });

  it("keeps age_import_run in plpgsql so its table is read on first call", () => {
    const text = renderBlocks(["pgtap"], {})
      .map((file) => file.contents)
      .join("\n");

    const start = text.indexOf("function tests.age_import_run");
    expect(start).toBeGreaterThan(-1);
    expect(text.slice(start, start + 200)).toContain("language plpgsql");
  });
});
