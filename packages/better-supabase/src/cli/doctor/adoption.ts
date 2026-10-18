import type { FindingInput, Rule } from "./rules.ts";

import { notNullTag } from "../gen/model-functions.ts";
import { configFor } from "../gen/shared.ts";
import { catalogOf } from "./shared.ts";

const tagText = (notNull: true | readonly string[]): string =>
  notNull === true ? "@notNull" : `@notNull(${notNull.join(", ")})`;

const sameNotNull = (
  a: true | readonly string[] | undefined,
  b: true | readonly string[],
): boolean =>
  a === true || b === true
    ? a === b
    : a !== undefined &&
      a.length === b.length &&
      a.every((name) => b.includes(name));

/** Checks that point at a shorter config for adopted schemas. */
export const ADOPTION_RULES: readonly Rule[] = [
  {
    code: "BS338",
    severity: "info",
    title: "functions.notNull entry a comment tag could replace",
    description:
      "`gen` reads `@notNull` and `@notNull(a, b)` from a function's comment. A `functions.<name>.notNull` entry for a function in the read schemas can move to the comment, next to the SQL it describes. A config entry wins over the tag.",
    check: (context) => {
      const { config } = context;

      return catalogOf(context).functions.flatMap((fn): FindingInput[] => {
        const notNull = configFor(
          config.functions,
          fn.schema,
          fn.name,
        )?.notNull;

        if (notNull === undefined || !config.schemas.includes(fn.schema)) {
          return [];
        }

        const name = `${fn.schema}.${fn.name}`;
        const tag = notNullTag(fn.comment);
        const wanted = tagText(notNull);

        let message: string;

        if (sameNotNull(tag, notNull)) {
          message = `functions.${fn.name}.notNull matches the ${wanted} tag on ${name}(${fn.signature}). Remove the config entry.`;
        } else if (tag === undefined) {
          message = `functions.${fn.name}.notNull can move to the function: add \`${wanted}\` to the comment on ${name}(${fn.signature}) (\`comment on function ${name}(${fn.signature}) is '${wanted}';\`), then remove the config entry.`;
        } else {
          message = `functions.${fn.name}.notNull (${wanted}) differs from the ${tagText(tag)} tag on ${name}(${fn.signature}), and the config entry wins. Make them agree, then remove the config entry.`;
        }

        return [{ message, target: `${name}(${fn.signature})` }];
      });
    },
  },
];
