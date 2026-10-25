import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";

const PATH_PARTS: Readonly<Record<string, string>> = {
  organization_id: "tenant",
  id: "id",
  subject_type: "subjectType",
  subject_id: "subjectId",
};

/**
 * `options.path`: the object path template, default
 * `{organization_id}/attachments/{id}`, as the generated column's expression.
 */
export const pathTemplate = (ctx: BlockSqlContext): string =>
  ctx.text("path", "{organization_id}/attachments/{id}");

/** Version 2 and later of a file live at its path plus `-v<version>`. */
const VERSION_SUFFIX = /-v\d+$/;

export function pathExpression(
  ctx: BlockSqlContext,
  tenantless = false,
): string {
  const template = pathTemplate(ctx);
  const where = "blocks.attachments.options.path";

  if (!template.includes("{id}")) {
    throw new TypeError(
      `${where} must contain {id}, so each file has its own path`,
    );
  }

  if (!template.startsWith("{organization_id}/")) {
    throw new TypeError(
      `${where} must start with {organization_id}/, so a tenant's files share a prefix`,
    );
  }

  if (VERSION_SUFFIX.test(template)) {
    throw new TypeError(
      `${where} must not end in -v and digits, which mark a file's later versions`,
    );
  }

  const parts = template.split(/(\{[a-z_]+\})/).filter((part) => part !== "");

  return parts
    .map((part) => {
      const match = /^\{([a-z_]+)\}$/.exec(part);

      if (!match) {
        if (!/^[A-Za-z0-9/_.-]+$/.test(part)) {
          throw new TypeError(
            `${where}: "${part}" may hold letters, digits, /, _, . and - only`,
          );
        }

        return sqlString(part);
      }

      // {ext}: the name's extension, lowercased, without the dot.
      if (match[1] === "ext") {
        return `coalesce(substring(lower(${ctx.col("attachments", "name")}) from '\\.([a-z0-9]{1,10})$'), '')`;
      }

      const logical = PATH_PARTS[match[1]!];

      if (!logical) {
        throw new TypeError(
          `${where}: {${match[1]}} is not a placeholder. Use ${[
            ...Object.keys(PATH_PARTS),
            "ext",
          ]
            .map((key) => `{${key}}`)
            .join(", ")}`,
        );
      }

      const column = ctx.col("attachments", logical);

      return logical === "subjectType" ||
        logical === "subjectId" ||
        (tenantless && logical === "tenant")
        ? `coalesce(${column}${logical === "tenant" ? "::text" : ""}, '-')`
        : `${column}::text`;
    })
    .join(" || ");
}
