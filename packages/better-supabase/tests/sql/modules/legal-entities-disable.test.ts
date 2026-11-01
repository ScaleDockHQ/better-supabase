import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { LEGAL_ENTITIES } from "../../../src/sql/modules/legal-entities.ts";
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

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '', true);`;

const BOOT = { timeout: 90_000 };

const MODULES = ["invoices", "legal-entities"] as const;

const options = (on: readonly string[]) => ({
  modules: { "legal-entities": { options: { on } } },
});

/** The legal-entities schema file with legal entities off for every kind. */
function turnedOff(): string {
  const file = renderBlocks([...MODULES], options([])).find(
    (candidate) =>
      candidate.module === "legal-entities" && candidate.kind === "schema",
  );

  expect(file).toBeDefined();
  expect(file?.contents).not.toMatch(/\$off\$|\$t\$/);

  return file!.contents;
}

async function run(check: string): Promise<void> {
  const files = renderBlocks([...MODULES], options(["invoices"]));

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
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

const draft = (title: string): string =>
  `(better_supabase.create_invoice('${TENANT}', '{"title": "${title}", "currency": "EUR"}'::jsonb,
    '[{"description": "Work", "quantity": 1, "unitAmount": "10000"}]'::jsonb) ->> 'id')::uuid`;

/** Two entities with an issued invoice each, numbered so they may collide. */
const SETUP = `
  v_a uuid;
  v_b uuid;
  v_one uuid;
  v_two uuid;`;

const BODY = (identifierOfTwo: string): string => `
  ${SERVICE}
  perform better_supabase.create_legal_entity('${TENANT}', 'DE01', 'Acme GmbH');
  v_b := (better_supabase.create_legal_entity('${TENANT}', 'BE01', 'Acme NV') ->> 'id')::uuid;
  v_one := ${draft("One")};
  v_two := ${draft("Two")};
  update better_supabase.invoices set legal_entity_id = v_b where id = v_two;
  perform better_supabase.issue_invoice(v_one, date '2026-05-01');
  perform better_supabase.issue_invoice(v_two, date '2026-05-02');
  update better_supabase.invoices set number = 7, identifier = 'INV-7' where id = v_one;
  update better_supabase.invoices set number = ${identifierOfTwo === "INV-7" ? "7" : "8"}, identifier = '${identifierOfTwo}' where id = v_two;`;

describe("turning legal entities off", BOOT, () => {
  it("lists the colliding numbers and refuses the restore with a hint", async () => {
    await expect(
      run(`do $t$
declare${SETUP}
  v_hint text;
  v_check jsonb;
begin${BODY("INV-7")}
  v_check := better_supabase.legal_entities_disable_check('${TENANT}');
  if v_check ->> 'ok' <> 'false' or jsonb_array_length(v_check -> 'collisions') < 1 then
    raise exception 'the check found no collision: %', v_check;
  end if;
  begin
    execute $off$${turnedOff()}$off$;
    raise exception 'the restore ran over a colliding number';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'LEGAL_ENTITIES_DISABLE_COLLISION' then
      raise exception 'the restore failed without its hint (%): %', v_hint, sqlerrm;
    end if;
  end;
  if not exists (select 1 from pg_indexes where tablename = 'invoices' and indexdef like '%legal_entity_id%' and indexdef like '%UNIQUE%') then
    raise exception 'the per-entity key was dropped although the restore failed';
  end if;
end;
$t$;`),
    ).resolves.toBeUndefined();
  });

  it("restores the per-organization key and loses no data when numbers are distinct", async () => {
    await expect(
      run(`do $t$
declare${SETUP}
  v_check jsonb;
  v_before bigint;
begin${BODY("INV-8")}
  v_check := better_supabase.legal_entities_disable_check('${TENANT}');
  if v_check ->> 'ok' <> 'true' then
    raise exception 'the check reports a collision: %', v_check;
  end if;
  select count(*) into v_before from better_supabase.invoices;
  execute $off$${turnedOff()}$off$;
  if (select count(*) from better_supabase.invoices) <> v_before
    or (select legal_entity_id from better_supabase.invoices where id = v_two) is distinct from v_b then
    raise exception 'the restore changed the invoices';
  end if;
  if exists (select 1 from pg_indexes where tablename = 'invoices' and indexdef like '%legal_entity_id%' and indexdef like '%UNIQUE%') then
    raise exception 'a per-entity unique key is left';
  end if;
  begin
    update better_supabase.invoices set number = 7, identifier = 'INV-7' where id = v_two;
    raise exception 'two documents hold one number after the restore';
  exception when unique_violation then
    null;
  end;
  if exists (select 1 from pg_trigger where tgname = 'bsb_invoices_entity_numbers') then
    raise exception 'the number guard is left';
  end if;
end;
$t$;`),
    ).resolves.toBeUndefined();
  });
});

describe("legal entity number guards (render)", () => {
  const guards = (names: readonly string[], on: readonly string[]): string =>
    renderBlocks([...names], options(on))
      .filter((file) => file.module === "legal-entities")
      .map((file) => file.contents)
      .join("\n");

  it("guards every kind that is on and nothing else", () => {
    const some = guards(
      ["invoices", "quotes", "orders", "legal-entities"],
      ["quotes"],
    );

    expect(some).toContain("bsb_quotes_entity_numbers");
    expect(some).not.toMatch(
      /create (or replace )?trigger "?bsb_invoices_entity_numbers/,
    );
    expect(some).not.toMatch(
      /create (or replace )?trigger "?bsb_orders_entity_numbers/,
    );
  });

  it("scopes the check by the columns that make a number unique", () => {
    const all = guards(
      ["invoices", "quotes", "orders", "legal-entities"],
      ["invoices", "quotes", "orders"],
    );

    expect(all).toContain("bsb_invoices_entity_numbers");
    expect(all).toContain("bsb_orders_entity_numbers");
    expect(all).toContain("legal_entities_disable_check");
  });

  it("has no guard when no kind is on", () => {
    expect(guards(["invoices", "legal-entities"], [])).not.toMatch(
      /create (or replace )?trigger/,
    );
  });

  it("sends the correction event only when the option is on", () => {
    const render = (correctionEvents: boolean): string =>
      renderBlocks(["invoices", "outbox"], {
        modules: { invoices: { options: { correctionEvents } } },
      })
        .map((file) => file.contents)
        .join("\n");

    const emitted = /emit_event\(\s*'invoice\.totals_corrected'/;

    expect(render(true)).toMatch(emitted);
    expect(render(false)).not.toMatch(emitted);
  });

  it("renders nothing in custom mode", () => {
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;

    expect(LEGAL_ENTITIES.build(context, {})).toBe("");
  });
});
