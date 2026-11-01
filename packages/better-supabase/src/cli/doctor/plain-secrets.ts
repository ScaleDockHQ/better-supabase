import type { ResolvedConfig } from "../../config/index.ts";
import type { CatalogColumn, CatalogTable } from "../introspect/types.ts";
import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { blockTables, tableTagComments } from "../../sql/index.ts";
import { withTableTags } from "../gen/table-tags.ts";
import { appTablesOf } from "./app-tables.ts";
import { catalogOf, qualified, tableObject } from "./shared.ts";

/**
 * The blocks that keep a secret out of the row, in the order doctor offers
 * them.
 */
const SECRET_BLOCKS = ["field-encryption", "credentials"] as const;

type SecretBlock = (typeof SECRET_BLOCKS)[number];

/**
 * A column named for a secret: `credentials`, `access_token`, `client_secret`,
 * `auth_header_value`. `token_hash`, `secret_id` and `credential_ref` end in
 * another word, so they don't match.
 */
const SECRET_NAME = /(?:^|_)(?:credentials?|tokens?|secrets?|header_values?)$/i;

/** Types that hold the value as written. */
const PLAIN_TYPES: ReadonlySet<string> = new Set([
  "text",
  "varchar",
  "bpchar",
  "json",
  "jsonb",
]);

function remedy(
  block: SecretBlock,
  table: CatalogTable,
  column: string,
): string {
  switch (block) {
    case "field-encryption": {
      return `set \`encrypted: true\` on tables.${table.name}.columns.${column} so field-encryption stores it as ciphertext under a Vault data key`;
    }

    case "credentials": {
      return "store the secret in Vault with the credentials block and keep a credential_ref jsonb in the row";
    }

    default: {
      const never: never = block;

      return never;
    }
  }
}

/**
 * The app tables with the columns that `@bsb encrypted` tags in the schema
 * files and migrations mark, next to the config's own.
 */
function encryptedTables(context: DoctorContext): ResolvedConfig["appTables"] {
  const comments = (context.sqlFiles ?? []).flatMap((file) =>
    tableTagComments(file.text),
  );

  return withTableTags(context.config, comments).appTables;
}

/**
 * Whether a row-level `before` trigger on the table runs one of the app's seal
 * functions (`tooling.doctor.sealTriggers`) and, when doctor knows the columns
 * it assigns, assigns this one.
 */
function sealedByTrigger(
  context: DoctorContext,
  table: CatalogTable,
  column: CatalogColumn,
): boolean {
  const seals = context.config.doctor.sealTriggers;

  return table.triggers.some(
    (trigger) =>
      trigger.timing === "before" &&
      trigger.level === "row" &&
      seals.includes(trigger.function) &&
      (trigger.fills === undefined || trigger.fills.includes(column.name)),
  );
}

/**
 * Plain secret columns in the app's tables while a block that would keep them
 * out of the row is installed (BS352).
 */
function plainSecretColumns(context: DoctorContext): FindingInput[] {
  const offered = SECRET_BLOCKS.filter((block) =>
    context.config.blockNames.includes(block),
  );

  if (offered.length === 0) {
    return [];
  }

  const own = appTablesOf(context);
  const encrypted = encryptedTables(context);

  const encryptedInConfig = (
    table: CatalogTable,
    column: CatalogColumn,
  ): boolean =>
    table.schema === "public" &&
    encrypted[table.name]?.columns?.[column.name]?.encrypted === true;

  const blockOwned = new Set(
    Object.values(blockTables(context.config).byBlock).flatMap((tables) =>
      Object.values(tables).map((table) => table.table),
    ),
  );

  return catalogOf(context)
    .tables.filter(
      (table) =>
        table.kind === "table" &&
        Object.hasOwn(own, qualified(table)) &&
        !blockOwned.has(qualified(table)),
    )
    .flatMap((table) =>
      table.columns
        .filter(
          (column) =>
            SECRET_NAME.test(column.name) &&
            PLAIN_TYPES.has(column.udt) &&
            !column.generated &&
            !encryptedInConfig(table, column) &&
            !sealedByTrigger(context, table, column),
        )
        .map((column) => {
          const target = `${qualified(table)}.${column.name}`;

          const fixes = offered.map((block) =>
            remedy(block, table, column.name),
          );

          return {
            message: `${target} stores a ${column.udt} value named like a secret in plain text, and ${offered.join(" and ")} ${offered.length === 1 ? "is" : "are"} installed. Anyone who can read the row or a backup reads the secret. To keep it out of the row, ${fixes.join(", or ")}.`,
            target,
            object: tableObject(table),
          };
        }),
    );
}

/**
 * Plain secret columns in the app's tables while neither `field-encryption` nor
 * `credentials` is installed (BS360). BS352 covers the projects that have one
 * of them.
 */
function secretsOutsideVault(context: DoctorContext): FindingInput[] {
  if (
    SECRET_BLOCKS.some((block) => context.config.blockNames.includes(block))
  ) {
    return [];
  }

  const own = appTablesOf(context);

  return catalogOf(context)
    .tables.filter(
      (table) => table.kind === "table" && Object.hasOwn(own, qualified(table)),
    )
    .flatMap((table) =>
      table.columns
        .filter(
          (column) =>
            SECRET_NAME.test(column.name) &&
            PLAIN_TYPES.has(column.udt) &&
            !column.generated &&
            !sealedByTrigger(context, table, column),
        )
        .map((column) => {
          const target = `${qualified(table)}.${column.name}`;

          return {
            message: `${target} stores a ${column.udt} value named like a secret in plain text. Anyone who can read the row or a backup reads the secret. Store the value with vault.create_secret, keep the returned id in a uuid column such as ${column.name}_secret_id, and read it through vault.decrypted_secrets in a security definer function.`,
            target,
            object: tableObject(table),
          };
        }),
    );
}

export const PLAIN_SECRET_RULES: readonly Rule[] = [
  {
    code: "BS360",
    severity: "warning",
    title: "Secret column outside Vault",
    description:
      "One of your tables has a `text`, `varchar` or `json` column whose name ends in `credentials`, `token`, `secret` or `header_value`, and neither `field-encryption` nor `credentials` is installed. The value sits in the row as written, so every role that reads the row, and every backup, has the secret. Store it with `vault.create_secret` and keep the returned id in a `uuid` column, or install `field-encryption` and mark the column `encrypted`. Block tables, columns that a seal function listed in `tooling.doctor.sealTriggers` assigns in a `before` trigger, and names such as `token_hash` or `secret_id` are not reported. BS352 reports the same columns when one of those blocks is installed.",
    check: secretsOutsideVault,
  },
  {
    code: "BS352",
    severity: "warning",
    title: "Plain secret column next to a block that encrypts it",
    description:
      "One of your tables has a `text`, `varchar` or `json` column whose name ends in `credentials`, `token`, `secret` or `header_value`, and `field-encryption` or `credentials` is installed. The value sits in the row as written, so every role that reads the row, and every backup, has the secret. Mark the column `encrypted: true` under `tables.<name>.columns` in the config (field-encryption), or move the secret to Vault with the credentials block and store a `credential_ref` instead. Block tables, columns marked `encrypted` in the config or by an `@bsb encrypted` tag in the schema files, columns that a seal function listed in `tooling.doctor.sealTriggers` assigns in a `before` trigger, and names such as `token_hash` or `secret_id` are not reported.",
    check: plainSecretColumns,
  },
];
