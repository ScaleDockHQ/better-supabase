import { expect } from "vitest";

import type { PageOptions } from "../../src/core/block-helpers.ts";
import type { Result } from "../../src/core/result.ts";

/** An id no row has. */
export const MISSING = "00000000-0000-4000-8000-000000000000";

export const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.kind);

interface Surface {
  readonly sorts?: readonly string[];
  readonly facets?: readonly string[];
  readonly search?: boolean | readonly string[];
}

/** Every declared sort in both directions, with `q` when the entity has it. */
export async function everySort(
  surface: Surface,
  page: (options: PageOptions) => PromiseLike<Result<unknown>>,
): Promise<void> {
  for (const by of surface.sorts ?? []) {
    for (const direction of ["asc", "desc"] as const) {
      const q = surface.search === undefined ? {} : { q: "x" };

      expect(hint(await page({ sort: { by, direction }, ...q }))).toBe("ok");
    }
  }
}

interface SmokeTarget<Item extends { readonly id: string }> {
  readonly surface: Surface;
  readonly page: (
    options: PageOptions,
  ) => PromiseLike<Result<{ readonly items: readonly Item[] }>>;
  readonly facets: () => PromiseLike<Result<unknown>>;
  readonly count: () => PromiseLike<Result<unknown>>;
  readonly get?: (id: string) => PromiseLike<Result<unknown>>;
}

/**
 * Runs a list through every sort, the facets and the count, then reads the
 * first row back with `get` and a missing id as `not_found`. It returns how
 * many rows the first page held.
 */
export async function smokeList<Item extends { readonly id: string }>(
  target: SmokeTarget<Item>,
): Promise<number> {
  await everySort(target.surface, target.page);
  expect(hint(await target.facets())).toBe("ok");
  expect(hint(await target.count())).toBe("ok");

  const first = await target.page({ limit: 1 });

  expect(hint(first)).toBe("ok");

  const [row] = first.ok ? first.data.items : [];

  if (target.get !== undefined) {
    if (row !== undefined) {
      expect(hint(await target.get(row.id))).toBe("ok");
    }

    const missing = await target.get(MISSING);

    expect(missing.ok).toBe(false);
    expect(missing.ok ? "ok" : missing.error.kind).toBe("not_found");
  }

  return first.ok ? first.data.items.length : 0;
}
