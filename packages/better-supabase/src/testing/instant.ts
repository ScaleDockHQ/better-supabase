import {
  type BudgetPage,
  expectDbBudget,
  type MeasuredRender,
} from "./budget.ts";

/** The part of a Playwright `BrowserContext` that `instant()` uses. */
export interface InstantBrowserContext {
  addCookies(
    cookies: {
      name: string;
      value: string;
      url?: string;
      domain?: string;
      path?: string;
      expires?: number;
    }[],
  ): Promise<void>;
  cookies(): Promise<
    { name: string; value: string; domain: string; path: string }[]
  >;
}

/** The part of a Playwright `Page` that `expectInstant` uses. */
export interface InstantPage extends BudgetPage {
  url(): string;
  context(): InstantBrowserContext;
}

/** The part of a Playwright `Locator` that `expectInstant` checks. */
export interface InstantLocator {
  waitFor(options: { state: "visible"; timeout?: number }): Promise<void>;
  count(): Promise<number>;
}

export interface InstantExpectation {
  /** The navigation to hold, such as a click on a `<Link>`. */
  readonly during: () => Promise<unknown>;
  /** Locators that must be visible while the lock holds. */
  readonly visible: readonly InstantLocator[];
  /** Locators that must not exist while the lock holds. */
  readonly absent?: readonly InstantLocator[];
  /** Fails when one render of the navigation makes more database calls. */
  readonly maxCalls?: number;
  /** Fails when one render of the navigation makes more sequential waves. */
  readonly maxWaves?: number;
  /** Scopes the lock on a page that has not loaded yet. */
  readonly baseURL?: string;
  /** How long each `visible` locator may take. Defaults to 5 seconds. */
  readonly timeoutMs?: number;
}

type Instant = <T>(
  page: InstantPage,
  fn: () => Promise<T>,
  options?: { baseURL?: string },
) => Promise<T>;

/**
 * `@next/playwright` is an optional peer: loading it on demand keeps it out
 * of apps that never call `expectInstant`, and a missing install returns
 * `undefined` so the caller can say how to add it.
 */
async function loadInstant(): Promise<Instant | undefined> {
  const specifier = "@next/playwright";
  try {
    // SAFETY: @next/playwright exports `instant` with this signature; the
    // catch covers a missing install.
    const module = (await import(specifier)) as { instant: Instant };
    return module.instant;
  } catch {
    return undefined;
  }
}

async function assertUnderLock(expectation: InstantExpectation): Promise<void> {
  const timeout = expectation.timeoutMs ?? 5000;
  for (const locator of expectation.visible) {
    try {
      await locator.waitFor({ state: "visible", timeout });
    } catch (error) {
      throw new Error(
        `expectInstant: ${String(locator)} was not visible under the instant() lock. It is not in the prefetched UI.`,
        { cause: error },
      );
    }
  }
  for (const locator of expectation.absent ?? []) {
    const count = await locator.count();
    if (count > 0) {
      throw new Error(
        `expectInstant: ${String(locator)} matched ${count} elements under the instant() lock. It should stream in after the navigation.`,
      );
    }
  }
}

/**
 * Runs `during` inside `@next/playwright`'s `instant()`, checks what the
 * prefetched UI shows while the lock holds, and with `maxCalls` or
 * `maxWaves` checks the navigation's database budget like `expectDbBudget`.
 * Needs a `next build` with the testing API exposed.
 */
export async function expectInstant(
  page: InstantPage,
  expectation: InstantExpectation,
): Promise<readonly MeasuredRender[]> {
  const instant = await loadInstant();
  if (!instant) {
    throw new Error(
      "expectInstant: install @next/playwright as a dev dependency (pnpm add -D @next/playwright).",
    );
  }
  const run = (): Promise<void> =>
    instant(
      page,
      async () => {
        await expectation.during();
        await assertUnderLock(expectation);
      },
      expectation.baseURL === undefined
        ? undefined
        : { baseURL: expectation.baseURL },
    );
  if (
    expectation.maxCalls === undefined &&
    expectation.maxWaves === undefined
  ) {
    await run();
    return [];
  }
  return expectDbBudget(page, {
    during: run,
    ...(expectation.maxCalls === undefined
      ? {}
      : { maxCalls: expectation.maxCalls }),
    ...(expectation.maxWaves === undefined
      ? {}
      : { maxWaves: expectation.maxWaves }),
  });
}
