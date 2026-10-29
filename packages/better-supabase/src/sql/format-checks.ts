import type {
  FieldFormatName,
  FieldFormatValidator,
} from "../core/contracts/field-formats.ts";

import {
  CUSTOM_FIELD_CHECKED_FORMATS,
  FIELD_FORMAT_VALIDATORS,
  FIELD_FORMATS,
} from "../core/contracts/field-formats.ts";
import { sqlIdent, sqlString } from "../core/template.ts";

/** `<schema>.bsb_valid_<name>`, quoted. */
export function validatorFunction(
  schema: string,
  validator: FieldFormatValidator,
): string {
  return `${sqlIdent(schema)}.${sqlIdent(`bsb_valid_${validator}`)}`;
}

/** The validators the formats in `formats` need, in a fixed order. */
export function validatorsOf(
  formats: Iterable<FieldFormatName | undefined>,
): readonly FieldFormatValidator[] {
  const used = new Set<FieldFormatValidator>();

  for (const format of formats) {
    const validator =
      format === undefined ? undefined : FIELD_FORMATS[format].validator;

    if (validator !== undefined) {
      used.add(validator);
    }
  }

  return FIELD_FORMAT_VALIDATORS.filter((validator) => used.has(validator));
}

/**
 * The SQL conditions a `format` puts on the text expression `ident`: its
 * pattern and its validator in `schema`. Bounds are the caller's.
 */
export function formatConditions(
  format: FieldFormatName,
  ident: string,
  schema: string,
): string[] {
  const spec = FIELD_FORMATS[format];

  return [
    ...(spec.pattern === undefined
      ? []
      : [`${ident} ~* ${sqlString(spec.pattern)}`]),
    ...(spec.validator === undefined
      ? []
      : [`${validatorFunction(schema, spec.validator)}(${ident})`]),
  ];
}

/**
 * Whether the text `value` passes the format the custom field type `type`
 * checks (`CUSTOM_FIELD_CHECKED_FORMATS`); `true` for the other types, and not
 * false for a `null` value.
 */
export function customFieldValueCheck(
  type: string,
  value: string,
  schema: string,
): string {
  const whens = Object.entries(CUSTOM_FIELD_CHECKED_FORMATS).map(
    ([field, format]) =>
      `when ${sqlString(field)} then ${formatConditions(format, value, schema).join(" and ")}`,
  );

  return `case ${type} ${whens.join(" ")} else true end`;
}

/** The validators the checked custom field types call. */
export const CUSTOM_FIELD_VALIDATORS: readonly FieldFormatValidator[] =
  validatorsOf(Object.values(CUSTOM_FIELD_CHECKED_FORMATS));

function bodyOf(validator: FieldFormatValidator): string {
  switch (validator) {
    // The elfproef: 9 digits weighted 9 down to 2, the last one weighted -1,
    // sum to a multiple of 11. All zeros passes the sum, so it's refused.
    case "bsn": {
      return `  select case
    when value !~ '^[0-9]{9}$' or value = '000000000' then false
    else (
      select sum(substr(value, i, 1)::integer * case when i = 9 then -1 else 10 - i end)
      from generate_series(1, 9) as i
    ) % 11 = 0
  end`;
    }

    // ISO 13616: move the first 4 characters to the end, turn each letter
    // into 10 to 35, and the number mod 97 is 1.
    case "iban": {
      return `  select case
    when value !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' then false
    else (
      select string_agg(case when ascii(c.ch) between 65 and 90 then (ascii(c.ch) - 55)::text else c.ch end, '' order by c.n)
      from regexp_split_to_table(substr(value, 5) || substr(value, 1, 4), '') with ordinality as c(ch, n)
    )::numeric % 97 = 1
  end`;
    }

    default: {
      const never: never = validator;

      throw new TypeError(`Unknown format validator "${String(never)}"`);
    }
  }
}

/**
 * The `bsb_valid_<name>(value text)` functions of `validators` in `schema`:
 * immutable, `null` for `null`, callable by signed-in users and the service
 * role so a check constraint that calls one runs for them.
 */
export function formatValidatorSql(
  schema: string,
  validators: readonly FieldFormatValidator[],
): string {
  return validators
    .map((validator) => {
      const fn = validatorFunction(schema, validator);

      return `create or replace function ${fn}(value text)
returns boolean
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
${bodyOf(validator)}
$$;
revoke execute on function ${fn}(text) from public, anon;
grant execute on function ${fn}(text) to authenticated, service_role;`;
    })
    .join("\n");
}
