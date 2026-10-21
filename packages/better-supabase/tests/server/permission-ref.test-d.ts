import { describe, expectTypeOf, it } from "vitest";

import { createAstro } from "../../src/astro/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { createReactRouter } from "../../src/react-router/index.ts";
import { createSolidStart } from "../../src/solid-start/index.ts";
import { createSvelteKit } from "../../src/sveltekit/index.ts";
import { createTanStackStart } from "../../src/tanstack-start/index.ts";
import { staticAuthorizer } from "../../src/testing/authorizer.ts";
import { schema } from "../fixtures/generated-camel.ts";

type PermissionKey = "tasks.read" | "tasks.write";

const authorizer = staticAuthorizer<PermissionKey>({
  roles: { authenticated: ["tasks.read"] },
});

const supabase = defineSupabase(schema);

describe("permission", () => {
  it("takes the authorizer's keys in every framework adapter", () => {
    const svelte = createSvelteKit(supabase, { authorizer });
    const astro = createAstro(supabase, { authorizer });
    const tanstack = createTanStackStart(supabase, { authorizer });

    const router = createReactRouter(supabase, {
      authorizer,
      createContext: () => ({}),
    });

    const solid = createSolidStart(supabase, {
      authorizer,
      getRequestEvent: () => undefined,
    });

    svelte.action({ permission: "tasks.write" }, () => "done");
    tanstack.action({ permission: "tasks.read" }, () => "done");
    router.action({ permission: "tasks.read" }, () => "done");
    solid.action({ permission: "tasks.read" }, () => "done");
    astro.action({ permission: "tasks.write" }, () => "done");

    // @ts-expect-error the authorizer has no such permission
    svelte.action({ permission: "tasks.delete" }, () => "done");
    // @ts-expect-error the authorizer has no such permission
    tanstack.action({ permission: "tasks.delete" }, () => "done");
    // @ts-expect-error the authorizer has no such permission
    router.action({ permission: "tasks.delete" }, () => "done");
    // @ts-expect-error the authorizer has no such permission
    solid.action({ permission: "tasks.delete" }, () => "done");
    // @ts-expect-error the authorizer has no such permission
    astro.action({ permission: "tasks.delete" }, () => "done");

    expectTypeOf<Parameters<typeof astro.guard>[1]>()
      .exclude<undefined>()
      .toHaveProperty("permission")
      .toEqualTypeOf<PermissionKey | undefined>();
  });

  it("takes any string without an authorizer", () => {
    const svelte = createSvelteKit(supabase);

    expectTypeOf<Parameters<typeof svelte.require>[1]>()
      .exclude<undefined>()
      .toHaveProperty("permission")
      .toEqualTypeOf<string | undefined>();
  });
});
