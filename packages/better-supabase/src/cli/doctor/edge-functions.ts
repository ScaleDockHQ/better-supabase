import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { tomlGet } from "../supabase-toml.ts";
import { lineOf } from "./shared.ts";

/** `auth: 'user'` in a function's source, the option that expects a user JWT. */
const USER_AUTH = /\bauth\s*:\s*["'`]user["'`]/;

/** The function that verifies the OAuth token itself (`templates.ts`, `mcp`). */
const OAUTH_FUNCTION = "mcp";

/** The functions `config.toml` sets `verify_jwt = false` for. */
function unverified(context: DoctorContext): readonly string[] {
  const functions = context.configToml
    ? tomlGet(context.configToml.document, ["functions"])
    : undefined;

  if (typeof functions !== "object" || Array.isArray(functions)) {
    return [];
  }

  const document = context.configToml?.document;

  return Object.keys(functions).filter(
    (name) =>
      document !== undefined &&
      tomlGet(document, ["functions", name, "verify_jwt"]) === false,
  );
}

/** Edge Function settings held against the function's source. */
export const EDGE_FUNCTION_RULES: readonly Rule[] = [
  {
    code: "BS395",
    severity: "error",
    title: "verify_jwt is off for a function that expects a user",
    description:
      "`[functions.<name>] verify_jwt = false` turns off the gateway's JWT check, and a function written with `auth: 'user'` relies on it to refuse anonymous callers before any code runs. With the check off, the function's own handler is the only gate. Turn `verify_jwt` back on, or verify the token in the function and drop `auth: 'user'`. The `mcp` function is the documented exception: it verifies the OAuth token itself, because the gateway would reject the MCP client first. Reads `supabase/config.toml` and the files under `supabase/functions`.",
    check(context) {
      const files = context.functionFiles ?? [];

      return unverified(context)
        .filter((name) => name !== OAUTH_FUNCTION)
        .flatMap((name): FindingInput[] => {
          const folder = `/functions/${name}/`;

          const user = files.find(
            (file) =>
              `/${file.path}`.includes(folder) && USER_AUTH.test(file.text),
          );

          return user === undefined
            ? []
            : [
                {
                  message: `[functions.${name}] has verify_jwt = false, and ${user.path} uses auth: 'user', so the gateway no longer refuses requests without a user token. Set verify_jwt = true, or verify the token in the function.`,
                  target: `[functions.${name}] verify_jwt`,
                  location: {
                    file: user.path,
                    line: lineOf(user.text, USER_AUTH) ?? 1,
                  },
                },
              ];
        });
    },
  },
];
