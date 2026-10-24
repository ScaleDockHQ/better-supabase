// The mapper serves the same types as the files `gen` writes without it: each
// pair below must be identical, in both directions.
import type * as files from "../shared/generated.ts";
import type * as mapped from "./mapper/generated.ts";

type Equal<A, B> =
  (<T>() => T extends A ? 1 : 2) extends <T>() => T extends B ? 1 : 2
    ? true
    : false;

const equal = <A, B>(proof: Equal<A, B>): Equal<A, B> => proof;

export const checks: readonly true[] = [
  equal<files.Models, mapped.Models>(true),
  equal<files.Database, mapped.Database>(true),
  equal<files.Functions, mapped.Functions>(true),
  equal<files.Json, mapped.Json>(true),
  equal<files.NoteKind, mapped.NoteKind>(true),
  equal<files.RowOf<"customers">, mapped.RowOf<"customers">>(true),
  equal<files.WhereOf<"customers">, mapped.WhereOf<"customers">>(true),
  equal<typeof files.schema, typeof mapped.schema>(true),
  equal<typeof files.buckets, typeof mapped.buckets>(true),
  equal<typeof files.topics, typeof mapped.topics>(true),
];
