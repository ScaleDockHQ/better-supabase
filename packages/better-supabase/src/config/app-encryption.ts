import type { AppColumnConfig } from "./types/app-tables.ts";

function booleanOf(where: string, value: unknown): boolean | undefined {
  if (value !== undefined && typeof value !== "boolean") {
    throw new TypeError(`${where} must be true or false`);
  }

  return value;
}

/**
 * `tables.<t>.columns.<c>.encrypted` checked: the database stores ciphertext,
 * so it can't compare, index or reference the value.
 */
export function encryptedOf(
  where: string,
  value: unknown,
  column: {
    readonly type: AppColumnConfig["type"];
    readonly unique: boolean | undefined;
    readonly references: AppColumnConfig["references"] | undefined;
    readonly identity: boolean | undefined;
  },
): boolean | undefined {
  const encrypted = booleanOf(`${where}.encrypted`, value);

  if (encrypted !== true) {
    return encrypted;
  }

  const refused =
    column.type === "text[]"
      ? "a text[] column"
      : column.unique === true
        ? "a unique column"
        : column.references === undefined
          ? column.identity === true
            ? "an identity"
            : undefined
          : "a reference";

  if (refused !== undefined) {
    throw new TypeError(
      `${where}.encrypted: ${refused} can't be encrypted, since the database only sees ciphertext; drop encrypted or the other key`,
    );
  }

  return encrypted;
}

/**
 * `tables.<t>.auditReads` checked: reads are audited where they are decrypted,
 * so the table needs an encrypted column.
 */
export function auditReadsOf(
  where: string,
  value: unknown,
  columns: Readonly<Record<string, AppColumnConfig>>,
): boolean | undefined {
  const audited = booleanOf(`${where}.auditReads`, value);

  if (
    audited === true &&
    !Object.values(columns).some((column) => column.encrypted === true)
  ) {
    throw new TypeError(
      `${where}.auditReads: reads are audited through ${where.replace("tables.", "")}_reveal, which needs an encrypted column; set encrypted on one`,
    );
  }

  return audited;
}

/** Throws when a `unique` or `indexes` key names an encrypted column. */
export function checkEncryptedKeys(
  where: string,
  columns: Readonly<Record<string, AppColumnConfig>>,
  keys: Readonly<
    Record<"unique" | "indexes", readonly (readonly string[])[] | undefined>
  >,
): void {
  for (const [key, sets] of Object.entries(keys)) {
    const column = (sets ?? [])
      .flat()
      .find((name) => columns[name]?.encrypted === true);

    if (column !== undefined) {
      throw new TypeError(
        `${where}.${key}: ${column} is encrypted, so the database can't compare it; drop it from the key`,
      );
    }
  }
}
