import { describe, expect, it } from "vitest";

import { declaredPolicies } from "../../../src/cli/sql-facts.ts";
import { primeAll } from "../../helpers/facts.ts";

describe("declaredPolicies", () => {
  it("keeps what the files leave, in order, for the listed schemas", async () => {
    const files = [
      {
        text: `-- create policy hidden on public.t using (false);
create policy a on public.t for select using (true);
create policy b on public.t for select using (false);
create policy c on private.t using (true);`,
      },
      {
        text: "drop policy if exists b on public.t; drop policy x on public.u;",
      },
    ];

    await primeAll(...files.map((file) => file.text));

    expect(declaredPolicies(files, ["public"])).toStrictEqual({
      "public.t": [
        {
          name: "a",
          command: "select",
          roles: ["public"],
          permissive: true,
          using: "true",
          check: null,
        },
      ],
    });
  });
});
