import { dbError } from "./errors.ts";
import { type Jwks, jwksOf, type JwksOfOptions } from "./jws.ts";
import { err, ok, type Result } from "./result.ts";

/** Where a key set comes from: inline, a URL fetched and cached, or a loader. */
export type JwksInput = Jwks | URL | (() => Promise<Jwks>);

export interface JwksSourceOptions extends JwksOfOptions {
  /** How long a fetched key set is used before it is fetched again. Default: 300. */
  readonly cacheSeconds?: number;
  /** The least time between two fetches for an unknown `kid`. Default: 30. */
  readonly refetchSeconds?: number;
  readonly fetch?: typeof fetch;
  /** Epoch milliseconds. */
  readonly now?: () => number;
}

/** A key set to verify with; `refresh` asks for a fresh copy after an unknown `kid`. */
export type JwksSource = (refresh: boolean) => Promise<Result<Jwks>>;

/** The most bytes read from a JWKS response. */
const MAX_JWKS_BYTES = 256 * 1024;

/**
 * A cached key set. A URL is fetched on first use and again after
 * `cacheSeconds`; a refresh for an unknown `kid` refetches at most once per
 * `refetchSeconds`, so a stream of forged `kid`s can't hammer the issuer.
 * Concurrent callers share one fetch.
 */
export function jwksSource(
  input: JwksInput,
  options: JwksSourceOptions = {},
): JwksSource {
  const parse = (value: unknown): Jwks =>
    jwksOf(value, options.rsa === undefined ? {} : { rsa: options.rsa });

  if (!(input instanceof URL) && typeof input !== "function") {
    const keys = parse(input);

    return () => Promise.resolve(ok(keys));
  }

  const now = options.now ?? Date.now;
  const cacheMs = (options.cacheSeconds ?? 300) * 1000;
  const refetchMs = (options.refetchSeconds ?? 30) * 1000;
  let cached: { readonly keys: Jwks; readonly at: number } | undefined;
  let pending: Promise<Result<Jwks>> | undefined;

  const load = async (): Promise<Result<Jwks>> => {
    if (typeof input === "function") {
      return ok(parse(await input()));
    }

    const response = await (options.fetch ?? fetch)(input, {
      headers: { accept: "application/jwk-set+json, application/json" },
    });

    if (!response.ok) {
      return err(
        dbError("network", `The JWKS answered ${response.status}`, {
          code: "JWKS_FETCH_FAILED",
        }),
      );
    }

    const text = await response.text();

    if (text.length > MAX_JWKS_BYTES) {
      return err(
        dbError("network", "The JWKS response is too large", {
          code: "JWKS_FETCH_FAILED",
        }),
      );
    }

    return ok(parse(JSON.parse(text)));
  };

  return async (refresh) => {
    const age = cached ? now() - cached.at : Number.POSITIVE_INFINITY;

    if (cached && age < (refresh ? refetchMs : cacheMs)) {
      return ok(cached.keys);
    }

    pending ??= load()
      .catch((cause: unknown) =>
        err(
          dbError(
            "network",
            `The JWKS could not be loaded: ${cause instanceof Error ? cause.message : String(cause)}`,
            { code: "JWKS_FETCH_FAILED" },
          ),
        ),
      )
      .then((result) => {
        if (result.ok) {
          cached = { keys: result.data, at: now() };
        }

        return result;
      })
      .finally(() => {
        pending = undefined;
      });

    const result = await pending;

    // A failed refetch keeps verifying with the keys already known.
    return !result.ok && cached ? ok(cached.keys) : result;
  };
}
