/** A plain JSON object. */
export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** A reader for one response shape: the value, or `undefined` when it doesn't match. */
export type Reader<TValue> = (value: unknown) => TValue | undefined;

export function arrayOf<TValue>(read: Reader<TValue>): Reader<TValue[]> {
  return (value) => {
    if (!Array.isArray(value)) {
      return;
    }

    const items: TValue[] = [];

    for (const item of value) {
      const parsed = read(item);

      if (parsed === undefined) {
        return;
      }

      items.push(parsed);
    }

    return items;
  };
}
