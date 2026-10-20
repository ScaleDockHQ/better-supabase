import type { DoctorContext, FindingInput } from "./rules.ts";

import { isRecord } from "../guards.ts";
import { appliesTo, escape } from "./rls.ts";
import { catalogOf, tableObject } from "./shared.ts";

/** The attachments subjects as the block resolves them, with the per-subject keys each one has. */
function attachmentSubjects(context: DoctorContext): {
  readonly type: string;
  readonly table: string;
  readonly tenant: string;
  readonly keys: ReadonlySet<string>;
}[] {
  const registry = context.config.subjects;
  const raw = context.config.blocks["attachments"]?.options?.["subjects"];

  const listed: [string, Readonly<Record<string, unknown>>][] =
    raw === undefined
      ? Object.keys(registry).map((type) => [type, {}])
      : Array.isArray(raw)
        ? raw
            .filter((type): type is string => typeof type === "string")
            .map((type) => [type, {}])
        : isRecord(raw)
          ? Object.entries(raw).flatMap(([type, entry]) =>
              isRecord(entry) ? [[type, entry]] : [],
            )
          : [];

  return listed.flatMap(([type, entry]) => {
    const registered = registry[type];
    const table = entry["table"] ?? registered?.table;
    const tenant = entry["tenant"] ?? registered?.tenant ?? "organization_id";

    if (typeof table !== "string" || typeof tenant !== "string") {
      return [];
    }

    const own = isRecord(entry["permissions"])
      ? Object.keys(entry["permissions"])
      : [];

    const fromRegistry = Object.keys(registered?.permissions ?? {}).filter(
      (key) => key !== "read",
    );

    return [{ type, table, tenant, keys: new Set([...own, ...fromRegistry]) }];
  });
}

/**
 * Whether `expression` only checks that the caller is a member of the row's
 * tenant: `current_tenant_id()`, a `*_ids_with` or `*member_*ids` function in
 * any schema (the provider's own helpers included), `can('tenant', ...)` or
 * `member_can`, joined by `and`, with a soft-delete `is null` allowed. A
 * permission call passes only with one of `keys`.
 */
function tenantOnly(
  expression: string,
  column: string,
  keys: ReadonlySet<string>,
): boolean {
  const col = `(?:"?\\w+"?\\.)?"?${escape(column)}"?(?:::\\w+)?`;
  const key = `'([^']*)'(?:::text)?`;

  const atoms = [
    `${col}\\s*=\\s*\\(?\\s*(?:select\\s+)?better_supabase\\.current_tenant_id\\(\\)(?:\\s+as\\s+\\w+)?`,
    `${col}\\s+in\\s+\\(\\s*select\\s+(?:\\w+\\.)?\\w*_ids_with\\(\\s*${key}\\s*\\)(?:\\s+as\\s+\\w+)?\\s*\\)`,
    `${col}\\s+in\\s+\\(\\s*select\\s+(?:\\w+\\.)?\\w*member_\\w*ids\\(\\s*\\)(?:\\s+as\\s+\\w+)?\\s*\\)`,
    `better_supabase\\.can\\(\\s*'tenant'(?:::text)?\\s*,\\s*${col}\\s*,\\s*${key}\\s*\\)`,
    `better_supabase\\.member_can\\(\\s*${col}\\s*,\\s*${key}\\s*\\)`,
    `(?:"?\\w+"?\\.)?"?\\w+"?\\s+is\\s+null`,
  ];

  const used: string[] = [];
  let rest = expression;

  for (const atom of atoms) {
    rest = rest.replaceAll(new RegExp(atom, "gi"), (_match, key?: unknown) => {
      if (typeof key === "string") {
        used.push(key);
      }

      return " ";
    });
  }

  return (
    used.every((key) => keys.has(key)) &&
    rest.replaceAll(/\band\b|[()\s]/gi, "") === ""
  );
}

/** The top-level `or` branches of `expression`, outer parentheses removed. */
function branches(expression: string): string[] {
  let text = expression.trim();

  while (text.startsWith("(") && closingParen(text) === text.length - 1) {
    text = text.slice(1, -1).trim();
  }

  const parts: string[] = [];
  let depth = 0;
  let start = 0;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];

    if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;
    } else if (depth === 0 && /^\sor\s/i.test(text.slice(index, index + 4))) {
      parts.push(text.slice(start, index));
      start = index + 4;
    }
  }

  parts.push(text.slice(start));

  return parts;
}

/** The index of the parenthesis closing the one at the start of `text`. */
function closingParen(text: string): number {
  let depth = 0;

  for (let index = 0; index < text.length; index += 1) {
    if (text[index] === "(") {
      depth += 1;
    } else if (text[index] === ")") {
      depth -= 1;

      if (depth === 0) {
        return index;
      }
    }
  }

  return -1;
}

/** Tenant membership alone lets the caller through: the whole check, or one `or` branch of it. */
function tenantSuffices(
  expression: string,
  column: string,
  keys: ReadonlySet<string>,
): boolean {
  return [expression, ...branches(expression)].some((part) =>
    tenantOnly(part, column, keys),
  );
}

export function attachmentSubjectsOnDefaults(
  context: DoctorContext,
): FindingInput[] {
  if (!context.config.blockNames.includes("attachments")) {
    return [];
  }

  const { tables } = catalogOf(context);
  const overrides = context.config.blocks["attachments"]?.permissions ?? {};

  const actions = [
    { action: "read", commands: ["select"], what: "reads" },
    { action: "upload", commands: ["insert", "update"], what: "writes" },
  ] as const;

  return attachmentSubjects(context).flatMap(
    ({ type, table: name, tenant, keys }): FindingInput[] => {
      const [schema, bare] = name.includes(".")
        ? name.split(".", 2)
        : ["public", name];

      const table = tables.find(
        (candidate) => candidate.schema === schema && candidate.name === bare,
      );

      if (table?.kind !== "table" || !table.rls) {
        return [];
      }

      const stricter = actions.filter(({ action, commands }) => {
        if (keys.has(action)) {
          return false;
        }

        const blockKey = overrides[action] ?? `attachments.${action}`;

        return commands.some((command) => {
          const applying = table.policies.filter(
            (policy) =>
              policy.permissive &&
              (policy.command === "all" || policy.command === command) &&
              appliesTo(policy, "authenticated"),
          );

          // Many tables let no client add or change rows; that says nothing about who may attach files.
          if (command !== "select" && applying.length === 0) {
            return false;
          }

          return !applying.some((policy) => {
            const expression =
              command === "select"
                ? policy.using
                : (policy.check ?? policy.using);

            return (
              expression !== null &&
              tenantSuffices(expression, tenant, new Set([blockKey]))
            );
          });
        });
      });

      if (stricter.length === 0) {
        return [];
      }

      const target = `${table.schema}.${table.name}`;
      const names = stricter.map(({ action }) => action).join(" and ");
      const what = stricter.map(({ what: verb }) => verb).join(" and ");

      const fixes = stricter.map(({ action }) =>
        action === "read"
          ? `blocks.attachments.options.subjects.${type}.permissions.read`
          : `subjects.${type}.permissions.upload`,
      );

      return [
        {
          message: `Attachments on ${type} use the block-wide ${names} key, but ${target} checks more than tenant membership for ${what}, so any member of the tenant gets the files of a ${type} they can't open. Set ${fixes.join(" and ")} to the key the table checks.`,
          target,
          object: tableObject(table),
        },
      ];
    },
  );
}
