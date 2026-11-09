/** One source row compared with the stored import record. */
export interface DiffItem {
  readonly key: string;
  readonly data: unknown;
  readonly refs?: unknown;
  readonly sourceUpdatedAt?: string;
}

/** What a previous import stored for one key. */
export interface DiffState {
  readonly hash: string;
  readonly sourceUpdatedAt?: string;
}

export interface ItemDiff {
  readonly created: readonly string[];
  readonly changed: readonly string[];
  readonly unchanged: readonly string[];
}

/** Stable JSON: object keys are sorted, so two equal values hash equally. */
export function stableJson(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableJson(item)).join(",")}]`;
  }

  if (value !== null && typeof value === "object") {
    const entries = Object.entries(value).toSorted(([left], [right]) =>
      left < right ? -1 : left > right ? 1 : 0,
    );

    return `{${entries
      .map(([key, item]) => `${JSON.stringify(key)}:${stableJson(item)}`)
      .join(",")}}`;
  }

  return JSON.stringify(value);
}

async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);

  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Classifies items as created, changed or unchanged. A source time that is not
 * newer than the stored one is unchanged and is not hashed.
 */
export async function diffItems(
  items: readonly DiffItem[],
  state: Readonly<Record<string, DiffState>>,
): Promise<ItemDiff> {
  const created: string[] = [];
  const changed: string[] = [];
  const unchanged: string[] = [];

  for (const item of items) {
    const stored = state[item.key];

    if (stored === undefined) {
      created.push(item.key);
      continue;
    }

    if (
      item.sourceUpdatedAt !== undefined &&
      stored.sourceUpdatedAt !== undefined &&
      item.sourceUpdatedAt <= stored.sourceUpdatedAt
    ) {
      unchanged.push(item.key);
      continue;
    }

    const hash = await sha256(
      stableJson({ data: item.data, refs: item.refs ?? null }),
    );

    if (hash === stored.hash) {
      unchanged.push(item.key);
    } else {
      changed.push(item.key);
    }
  }

  return { created, changed, unchanged };
}
