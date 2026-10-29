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

const overlap = (ctx: BlockSqlContext): "end" | "allow" | "deny" =>
  choice(ctx, "contractOverlap", ["end", "allow", "deny"]);

export function overlappingContracts(ctx: BlockSqlContext): boolean {
  const allow = overlap(ctx) === "allow";

  if (allow && !editableContracts(ctx)) {
    throw new TypeError(
      `${WHERE}.contractOverlap "allow" needs contracts "editable"`,
    );
  }

  return allow;
}

export const denyOverlaps = (ctx: BlockSqlContext): boolean =>
  overlap(ctx) === "deny";

/**
 * Whether offboarding or deleting an employee moves the reports to their
 * manager.
 */
export function reportsMoveUp(ctx: BlockSqlContext): boolean {
  const raw = ctx.option("offboarding");

  if (raw === undefined) {
    return true;
  }

  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new TypeError(`${WHERE}.offboarding must be an object`);
  }

  const reports: unknown = "reports" in raw ? raw.reports : "manager";

  if (reports !== "manager" && reports !== "keep") {
    throw new TypeError(
      `${WHERE}.offboarding.reports must be "keep" or "manager"`,
    );
  }

  return reports === "manager";
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
