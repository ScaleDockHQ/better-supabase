type Override<R, O> = {
  [K in keyof R]: K extends keyof O
    ? null extends R[K]
      ? O[K] | null
      : O[K]
    : R[K];
};

type EnrichTables<Tables, O> = {
  [T in keyof Tables]: T extends keyof O
    ? {
        [P in keyof Tables[T]]: P extends "Row" | "Insert" | "Update"
          ? Override<Tables[T][P], O[T]>
          : Tables[T][P];
      }
    : Tables[T];
};

type EnrichSchema<S, O> = {
  [P in keyof S]: P extends "Tables" | "Views" ? EnrichTables<S[P], O> : S[P];
};

/**
 * Narrows column types of a `supabase gen types` `Database`: CHECK-constraint
 * unions and typed jsonb. Overrides are keyed `{ schema: { table: { column } } }`.
 */
export type EnrichDatabase<D, O> = {
  [S in keyof D]: S extends keyof O ? EnrichSchema<D[S], O[S]> : D[S];
};
