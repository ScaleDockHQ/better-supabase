import type { FindingInput, Rule } from "./rules.ts";

import { errorText } from "../core/errors.ts";
import { literal as sqlString } from "./live.ts";
import { moduleFiles } from "./module-files.ts";
import { catalogOf } from "./shared.ts";

const PARTIAL_INDEX =
  /^create\s+(?:unique\s+)?index\s+(?:if\s+not\s+exists\s+)?("[^"]+"|\w+)\s+on\s+("[^"]+"|\w+)\.("[^"]+"|\w+)\s+\([^\n]*\)\s+where\s+([^\n;]+);/gim;

const LITERAL = /'((?:[^']|'')*)'/g;

const unquote = (name: string): string => name.replace(/^"(.*)"$/, "$1");

/**
 * The string literals of a predicate, sorted, so `in (...)` and `= any
 * (array[...])` compare.
 */
function literals(predicate: string): string {
  return [...new Set([...predicate.matchAll(LITERAL)].map((m) => m[1]!))]
    .toSorted()
    .join("|");
}

interface EmittedIndex {
  readonly name: string;
  readonly table: string;
  readonly predicate: string;
}

function emittedIndexes(text: string): EmittedIndex[] {
  return [...text.matchAll(PARTIAL_INDEX)].map((match) => ({
    name: unquote(match[1]!),
    table: `${unquote(match[2]!)}.${unquote(match[3]!)}`,
    predicate: match[4]!,
  }));
}

export const LIVE_DRIFT_RULES: readonly Rule[] = [
  {
    code: "BS363",
    severity: "warning",
    title: "A partial index differs from the module's definition",
    description:
      "`create index if not exists` never changes an index that already exists, so a module that now writes another `where` predicate (for example the mapped status values of `blocks.webhooks-out`) leaves the old index in a database that was set up earlier. Doctor compares the string literals of each partial index the module files create with the live index of the same name and table, and lists the ones that differ. Drop the index and run `sql upgrade`, then apply the migration. Needs a database; saved snapshots skip it.",
    async check(context) {
      const db = context.database;

      if (!db || "skipped" in db) {
        return [];
      }

      const emitted = (await moduleFiles(context)).flatMap((state) =>
        emittedIndexes(state.file.contents),
      );

      if (emitted.length === 0) {
        return [];
      }

      const names = emitted.map((index) => sqlString(index.name)).join(", ");

      try {
        const live = await db.query<{
          name: string;
          table: string;
          predicate: string;
        }>(
          `select c.relname::text as name, (n.nspname || '.' || t.relname)::text as "table", pg_get_expr(i.indpred, i.indrelid) as predicate from pg_index i join pg_class c on c.oid = i.indexrelid join pg_class t on t.oid = i.indrelid join pg_namespace n on n.oid = t.relnamespace where i.indpred is not null and c.relname in (${names})`,
        );

        return live.flatMap((row): FindingInput[] => {
          const index = emitted.find(
            (entry) => entry.name === row.name && entry.table === row.table,
          );

          if (
            index === undefined ||
            literals(index.predicate) === literals(row.predicate)
          ) {
            return [];
          }

          return [
            {
              message: `The index ${row.name} on ${row.table} has the predicate ${row.predicate}, but the module now writes where ${index.predicate}. Drop the index (\`drop index ${row.name}\`) and apply the module again so it is created with the current predicate.`,
              target: `${row.table}.${row.name}`,
            },
          ];
        });
      } catch (cause) {
        return [
          {
            message: `Could not compare the partial indexes (${db.describe}): ${errorText(cause)}`,
          },
        ];
      }
    },
  },
  {
    code: "BS364",
    severity: "warning",
    title: "An API wrapper is volatile around a stable function",
    description:
      "A `language sql` wrapper without `stable` is volatile, so Postgres can't inline it into a policy or cache it for the statement, even when the function it calls is `stable`. The module wrappers (`gen.api`) copy the volatility of the function they wrap. Doctor lists a volatile `security invoker` SQL function that has the same name and arguments as a `stable` or `immutable` function in another schema, which is how a wrapper written by an older release looks. Run `sql upgrade` to rewrite the wrappers. Reads the snapshot.",
    check(context) {
      const functions = catalogOf(context).functions.filter(
        (fn) => fn.language === "sql" && !fn.securityDefiner,
      );

      return functions.flatMap((wrapper): FindingInput[] => {
        if (wrapper.volatility !== "volatile") {
          return [];
        }

        const inner = functions.find(
          (fn) =>
            fn.schema !== wrapper.schema &&
            fn.name === wrapper.name &&
            fn.signature === wrapper.signature &&
            fn.volatility !== "volatile",
        );

        return inner === undefined
          ? []
          : [
              {
                message: `${wrapper.schema}.${wrapper.name}(${wrapper.signature}) is volatile, but ${inner.schema}.${inner.name} is ${inner.volatility}, so the wrapper can't be inlined or cached. Run \`better-supabase sql upgrade\` to rewrite the wrapper with the same volatility.`,
                target: `${wrapper.schema}.${wrapper.name}`,
              },
            ];
      });
    },
  },
];
