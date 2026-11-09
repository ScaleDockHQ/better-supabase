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
