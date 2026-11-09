import type { BlockSqlContext } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";

import { uniqueContributions } from "../contributions.ts";

const FUNCTION_NAME: RegExp = /^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$/;
const ENTITY_NAME: RegExp = /^[a-z][a-z0-9_.:-]*$/i;

/**
 * Every target the module dispatches to: the contributions of the blocks that
 * use `imports`, then the app's own from `blocks.imports.options.targets`.
 * `replaces: true` takes a built-in entity's arm.
 */
export function targetsOf(
  ctx: BlockSqlContext,
): readonly ImportTargetContribution[] {
  const where = "blocks['imports'].options.targets";
  const raw: unknown = ctx.option("targets") ?? {};

  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new TypeError(`${where} must map entity names to targets`);
  }

  const own: ImportTargetContribution[] = [];

  for (const [entity, value] of new Map<string, unknown>(Object.entries(raw))) {
    if (!ENTITY_NAME.test(entity)) {
      throw new TypeError(`${where}: "${entity}" is not a valid entity name`);
    }

    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      throw new TypeError(
        `${where}.${entity} must be { subjectType, write, updatedAt? }`,
      );
    }

    const entry = new Map<string, unknown>(Object.entries(value));
    const subjectType = entry.get("subjectType");
    const write = entry.get("write");
    const updatedAt = entry.get("updatedAt");
    const ownedHash = entry.get("ownedHash");
    const naturalKey = entry.get("naturalKey");
    const batch = entry.get("batch");
    const replaces = entry.get("replaces");
    const before = entry.get("before");
    const after = entry.get("after");

    const hook = (field: string, hookValue: unknown): string | undefined => {
      if (hookValue === undefined) {
        return undefined;
      }

      if (typeof hookValue !== "string" || !FUNCTION_NAME.test(hookValue)) {
        throw new TypeError(
          `${where}.${entity}.${field} must be a "schema.function" name in lowercase`,
        );
      }

      return hookValue;
    };

    if (typeof subjectType !== "string" || subjectType === "") {
      throw new TypeError(`${where}.${entity}.subjectType must be a string`);
    }

    if (typeof write !== "string" || !FUNCTION_NAME.test(write)) {
      throw new TypeError(
        `${where}.${entity}.write must be a "schema.function" name in lowercase`,
      );
    }

    if (
      updatedAt !== undefined &&
      (typeof updatedAt !== "string" || !FUNCTION_NAME.test(updatedAt))
    ) {
      throw new TypeError(
        `${where}.${entity}.updatedAt must be a "schema.function" name in lowercase`,
      );
    }

    if (
      ownedHash !== undefined &&
      (typeof ownedHash !== "string" || !FUNCTION_NAME.test(ownedHash))
    ) {
      throw new TypeError(
        `${where}.${entity}.ownedHash must be a "schema.function" name in lowercase`,
      );
    }

    if (
      naturalKey !== undefined &&
      (typeof naturalKey !== "string" || !FUNCTION_NAME.test(naturalKey))
    ) {
      throw new TypeError(
        `${where}.${entity}.naturalKey must be a "schema.function" name in lowercase`,
      );
    }

    if (
      batch !== undefined &&
      (typeof batch !== "string" || !FUNCTION_NAME.test(batch))
    ) {
      throw new TypeError(
        `${where}.${entity}.batch must be a "schema.function" name in lowercase`,
      );
    }

    if (replaces !== undefined && replaces !== true) {
      throw new TypeError(`${where}.${entity}.replaces must be true`);
    }

    const beforeName = hook("before", before);
    const afterName = hook("after", after);

    own.push({
      entity,
      subjectType,
      write,
      ...(batch === undefined ? {} : { batch }),
      ...(updatedAt === undefined ? {} : { updatedAt }),
      ...(ownedHash === undefined ? {} : { ownedHash }),
      ...(naturalKey === undefined ? {} : { naturalKey }),
      ...(replaces === true ? { replaces: true } : {}),
      ...(beforeName === undefined ? {} : { before: beforeName }),
      ...(afterName === undefined ? {} : { after: afterName }),
    });
  }

  const replacing = own.filter((target) => target.replaces === true);
  const added = own.filter((target) => target.replaces !== true);
  const replaced = new Set(replacing.map((target) => target.entity));

  return uniqueContributions(
    "imports",
    [
      ...ctx
        .contributions("imports")
        .filter((target) => !replaced.has(target.entity)),
      ...replacing,
      ...added,
    ],
    (target) => target.entity,
  );
}

/**
 * A plpgsql `case` that assigns one reader, or `null;` when no target declares
 * it.
 */
export function assignCase(
  targets: readonly ImportTargetContribution[],
  pick: (target: ImportTargetContribution) => string | undefined,
  variable: string,
  text: (value: string) => string,
  quote: (name: string) => string,
  argument: string,
): string {
  const arms = targets.flatMap((target) => {
    const reader = pick(target);

    return reader === undefined
      ? []
      : [
          `        when ${text(target.entity)} then
          ${variable} := ${quote(reader)}(${argument});`,
        ];
  });

  return arms.length === 0
    ? "null;"
    : `case v_entity
${arms.join("\n")}
          else null;
        end case;`;
}

/** The `case` that adopts a subject when no import record exists. */
export function naturalLookupOf(
  targets: readonly ImportTargetContribution[],
  text: (value: string) => string,
  quote: (name: string) => string,
  tenant: string,
): string {
  const arms = targets
    .filter((target) => target.naturalKey !== undefined)
    .map(
      (target) => `        when ${text(target.entity)} then
          v_natural := ${quote(target.naturalKey ?? "")}(${tenant}, v_item);`,
    )
    .join("\n");

  return arms === ""
    ? "null;"
    : `case v_entity
${arms}
          else null;
        end case;`;
}

/** A `case` of per-entity readers, or `null` when none declare one. */
export function readerCaseOf(
  targets: readonly ImportTargetContribution[],
  pick: (target: ImportTargetContribution) => string | undefined,
  text: (value: string) => string,
  quote: (name: string) => string,
  subject: string,
  entity: string,
): string {
  const arms = targets.flatMap((target) => {
    const reader = pick(target);

    return reader === undefined
      ? []
      : [`when ${text(target.entity)} then ${quote(reader)}(${subject})`];
  });

  return arms.length === 0
    ? "null"
    : `case ${entity} ${arms.join(" ")} else null end`;
}
