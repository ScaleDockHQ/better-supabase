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
 * tenant: `current_tenant_id()`, `tenant_ids_with`, `member_<tenant>_ids`,
 * `can('tenant', ...)` or `member_can`, joined by `and`, with a soft-delete
 * `is null` allowed. A permission call passes only with one of `keys`.
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
    `${col}\\s+in\\s+\\(\\s*select\\s+better_supabase\\.tenant_ids_with\\(\\s*${key}\\s*\\)(?:\\s+as\\s+\\w+)?\\s*\\)`,
    `${col}\\s+in\\s+\\(\\s*select\\s+better_supabase\\.member_\\w+_ids\\(\\s*\\)(?:\\s+as\\s+\\w+)?\\s*\\)`,
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

          // Many tables let nobody update; that says nothing about who may add rows.
          if (command === "update" && applying.length === 0) {
            return false;
          }

          return !applying.some((policy) => {
            const expression =
              command === "select"
                ? policy.using
                : (policy.check ?? policy.using);

            return (
              expression !== null &&
              tenantOnly(expression, tenant, new Set([blockKey]))
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
