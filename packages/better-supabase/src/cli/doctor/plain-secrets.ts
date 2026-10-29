import type { CatalogColumn, CatalogTable } from "../introspect/types.ts";
import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { blockTables } from "../../sql/index.ts";
import { appTablesOf } from "./app-tables.ts";
import { catalogOf, qualified, tableObject } from "./shared.ts";

/**
 * The blocks that keep a secret out of the row, in the order doctor offers
 * them.
 */
const SECRET_BLOCKS = ["field-encryption", "credentials"] as const;

type SecretBlock = (typeof SECRET_BLOCKS)[number];

/**
 * A column named for a secret: `credentials`, `access_token`, `client_secret`.
 * `token_hash`, `secret_id` and `credential_ref` end in another word, so they
 * don't match.
 */
const SECRET_NAME = /(?:^|_)(?:credentials?|tokens?|secrets?)$/i;

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

const encryptedInConfig = (
  context: DoctorContext,
  table: CatalogTable,
  column: CatalogColumn,
): boolean =>
  table.schema === "public" &&
  context.config.appTables[table.name]?.columns?.[column.name]?.encrypted ===
    true;

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
            !encryptedInConfig(context, table, column),
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

export const PLAIN_SECRET_RULES: readonly Rule[] = [
  {
    code: "BS352",
    severity: "warning",
    title: "Plain secret column next to a block that encrypts it",
    description:
      "One of your tables has a `text`, `varchar` or `json` column whose name ends in `credentials`, `token` or `secret`, and `field-encryption` or `credentials` is installed. The value sits in the row as written, so every role that reads the row, and every backup, has the secret. Mark the column `encrypted: true` under `tables.<name>.columns` in the config (field-encryption), or move the secret to Vault with the credentials block and store a `credential_ref` instead. Block tables, columns already marked `encrypted` and names such as `token_hash` or `secret_id` are not reported.",
    check: plainSecretColumns,
  },
];
