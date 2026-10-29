import { describe, expect, it } from "vitest";

import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { formatValidatorSql } from "../../src/sql/format-checks.ts";
import { liteStack } from "../../src/testing/lite.ts";

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon;
  end if;
end;
$$;
`;

/** The examples of ISO 13616-1 and the national registries, in electronic form. */
const VALID_IBANS = [
  "NL91ABNA0417164300",
  "DE89370400440532013000",
  "GB82WEST12345698765432",
  "FR1420041010050500013M02606",
  "BE68539007547034",
];

const INVALID_IBANS = [
  // One digit off, so mod 97 is not 1.
  "NL91ABNA0417164301",
  // Check digits 00 never pass.
  "NL00ABNA0417164300",
  // The print form, with spaces, is not the electronic form.
  "NL91 ABNA 0417 1643 00",
  // The electronic form is uppercase.
  "nl91abna0417164300",
  // Too short for any country.
  "NL91ABNA",
];

const VALID_BSNS = ["111222333", "123456782", "100000009"];

const INVALID_BSNS = [
  "123456789",
  "000000000",
  "12345678",
  "1234567820",
  "12345678a",
];

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

/** Raises unless each value gets the expected answer from `fn`. */
function expectAll(
  fn: string,
  valid: readonly string[],
  invalid: readonly string[],
): string {
  return `do $$
declare
  v_wrong text;
begin
  select string_agg(v.value, ', ') into v_wrong
  from (
    select value, true as expected from unnest(array[${list(valid)}]) value
    union all
    select value, false from unnest(array[${list(invalid)}]) value
  ) v
  where public.${fn}(v.value) is distinct from v.expected;
  if v_wrong is not null then
    raise exception '${fn} is wrong for %', v_wrong;
  end if;
  if public.${fn}(null) is not null then
    raise exception '${fn}(null) is not null';
  end if;
end;
$$;`;
}

async function run(check: string): Promise<void> {
  await using stack = await liteStack({
    driver: "pglite",
    migrations: [ROLES, formatValidatorSql("public", ["bsn", "iban"])],
    seed: [check],
  });

  expect(stack.url).not.toBe("");
}

describe("ISO 13616", () => {
  it("pins the edition the iban check follows", () => {
    expect(SPEC_PINS.iso13616).toBe("2020");
  });

  it("accepts the example IBANs and refuses altered ones", BOOT, async () => {
    await expect(
      run(expectAll("bsb_valid_iban", VALID_IBANS, INVALID_IBANS)),
    ).resolves.toBeUndefined();
  });

  it("checks the BSN elfproef", BOOT, async () => {
    await expect(
      run(expectAll("bsb_valid_bsn", VALID_BSNS, INVALID_BSNS)),
    ).resolves.toBeUndefined();
  });
});
