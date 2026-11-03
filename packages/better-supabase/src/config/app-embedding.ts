import type { AppColumnConfig, AppTableEmbedding } from "./types/app-tables.ts";

const SCHEDULE = /^(\d{1,2} seconds?|[0-9*/, -]+( [0-9*/, -]+){4})$/u;
const MAX_DIMENSIONS = { vector: 2000, halfvec: 4000 } as const;

/** The column the vector lives in. */
const APP_EMBEDDING_COLUMN = "embedding";

function isObject(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * `tables.<t>.embedding` checked (ADR 0229): the embedded columns are own plain
 * `text` columns (not encrypted), the table has no column of its own named
 * `embedding`, and the size fits the index of the vector type.
 */
export function embeddingOf(
  where: string,
  value: unknown,
  columns: Readonly<Record<string, AppColumnConfig>>,
): AppTableEmbedding | undefined {
  if (value === undefined) {
    return undefined;
  }

  const at = `${where}.embedding`;

  if (!isObject(value)) {
    throw new TypeError(`${at} must be an object with content and dimensions`);
  }

  for (const key of Object.keys(value)) {
    if (!["content", "dimensions", "type", "schedule", "batch"].includes(key)) {
      throw new TypeError(
        `${at}.${key} is not an option; use content, dimensions, type, schedule or batch`,
      );
    }
  }

  const { content, dimensions, type, schedule, batch } = value;

  if (
    !Array.isArray(content) ||
    content.length === 0 ||
    content.length > 20 ||
    content.some((name) => typeof name !== "string")
  ) {
    throw new TypeError(`${at}.content must list 1 to 20 text columns`);
  }

  // SAFETY: every entry was checked to be a string above.
  const names: string[] = content as string[];

  if (new Set(names).size !== names.length) {
    throw new TypeError(`${at}.content lists a column twice`);
  }

  for (const name of names) {
    const column = columns[name];

    if (column === undefined) {
      throw new TypeError(
        `${at}.content names "${name}", which is not a column of the table`,
      );
    }

    if (column.type !== "text" || column.encrypted === true) {
      throw new TypeError(
        `${at}.content column "${name}" must be a plain text column (not encrypted)`,
      );
    }
  }

  if (columns[APP_EMBEDDING_COLUMN] !== undefined) {
    throw new TypeError(
      `${at} adds a column named "${APP_EMBEDDING_COLUMN}"; rename your column of that name`,
    );
  }

  if (type !== undefined && type !== "vector" && type !== "halfvec") {
    throw new TypeError(`${at}.type must be "vector" or "halfvec"`);
  }

  const kind = type ?? "halfvec";
  const max = MAX_DIMENSIONS[kind];

  if (
    typeof dimensions !== "number" ||
    !Number.isInteger(dimensions) ||
    dimensions < 1 ||
    dimensions > max
  ) {
    throw new TypeError(
      `${at}.dimensions must be a whole number from 1 to ${String(max)} for ${kind}`,
    );
  }

  if (
    schedule !== undefined &&
    (typeof schedule !== "string" || !SCHEDULE.test(schedule))
  ) {
    throw new TypeError(
      `${at}.schedule must be "N seconds" or a five-field cron expression`,
    );
  }

  if (
    batch !== undefined &&
    (typeof batch !== "number" ||
      !Number.isInteger(batch) ||
      batch < 1 ||
      batch > 200)
  ) {
    throw new TypeError(`${at}.batch must be a whole number from 1 to 200`);
  }

  return {
    content: names,
    dimensions,
    ...(type === undefined ? {} : { type }),
    ...(schedule === undefined ? {} : { schedule }),
    ...(batch === undefined ? {} : { batch }),
  };
}
