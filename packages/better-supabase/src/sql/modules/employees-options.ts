import type { BlockSqlContext } from "../context.ts";

const WHERE = "blocks.employees.options";

function choice<T extends string>(
  ctx: BlockSqlContext,
  name: string,
  values: readonly T[],
): T {
  const raw = ctx.option(name) ?? values[0];

  if (typeof raw !== "string" || !values.some((value) => value === raw)) {
    throw new TypeError(
      `${WHERE}.${name} must be ${values.map((value) => `"${value}"`).join(" or ")}`,
    );
  }

  return values.find((value) => value === raw) ?? values[0]!;
}

export const splitName = (ctx: BlockSqlContext): boolean =>
  choice(ctx, "name", ["single", "split"]) === "split";

export const flatDetails = (ctx: BlockSqlContext): boolean =>
  choice(ctx, "privateDetails", ["json", "flat"]) === "flat";

export const editableContracts = (ctx: BlockSqlContext): boolean =>
  choice(ctx, "contracts", ["append", "editable"]) === "editable";

export const majorSalary = (ctx: BlockSqlContext): boolean =>
  choice(ctx, "salaryUnits", ["minor", "major"]) === "major";

export function overlappingContracts(ctx: BlockSqlContext): boolean {
  const allow = choice(ctx, "contractOverlap", ["end", "allow"]) === "allow";

  if (allow && !editableContracts(ctx)) {
    throw new TypeError(
      `${WHERE}.contractOverlap "allow" needs contracts "editable"`,
    );
  }

  return allow;
}

export const FLAT_DETAILS = [
  "addressLine1",
  "addressLine2",
  "postalCode",
  "city",
  "region",
  "country",
  "emergencyName",
  "emergencyPhone",
  "emergencyRelation",
] as const;
