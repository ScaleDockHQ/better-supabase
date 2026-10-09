import type { Accessor } from "solid-js";
import type { ComputedRef, Ref } from "vue";

import { describe, expectTypeOf, it } from "vitest";

import type { AuthSession } from "../../src/auth/view.ts";
import type { ActionResultOf, ClientLike } from "../../src/bindings/client.ts";
import type { AuthSnapshot } from "../../src/client/index.ts";
import type { SubscriptionStatus } from "../../src/realtime/index.ts";

import * as solid from "../../src/solid/index.ts";
import * as svelte from "../../src/svelte/index.ts";
import * as vue from "../../src/vue/index.ts";

type Client = ClientLike & {
  readonly db: { readonly customers: { findMany(): Promise<string[]> } };
  readonly queries: { readonly customers: { readonly key: "customers" } };
};

declare const removeMember: (input: {
  userId: string;
}) => Promise<ActionResultOf<{ removed: true }>>;

describe("vue", () => {
  it("types the composables by the client", () => {
    const bindings = vue.createBindings<Client>();
    expectTypeOf(bindings.useDb()).toEqualTypeOf<Client["db"]>();
    expectTypeOf(bindings.useQueries()).toEqualTypeOf<Client["queries"]>();
    expectTypeOf(bindings.useAuth()).toEqualTypeOf<
      Readonly<Ref<AuthSnapshot>>
    >();
    expectTypeOf(bindings.useSession()).toEqualTypeOf<
      ComputedRef<AuthSession>
    >();
    expectTypeOf(vue.useLiveQuery).returns.toEqualTypeOf<
      Readonly<Ref<SubscriptionStatus>>
    >();
    const remove = vue.useAction(removeMember);
    expectTypeOf(remove.run).parameter(0).toEqualTypeOf<{ userId: string }>();
    expectTypeOf(remove.data).toEqualTypeOf<{ removed: true } | undefined>();
  });
});

describe("solid", () => {
  it("types the primitives by the client", () => {
    const bindings = solid.createBindings<Client>();
    expectTypeOf(bindings.useDb()).toEqualTypeOf<Client["db"]>();
    expectTypeOf(bindings.useAuth()).toEqualTypeOf<Accessor<AuthSnapshot>>();
    expectTypeOf(solid.useLiveQuery).returns.toEqualTypeOf<
      Accessor<SubscriptionStatus>
    >();
    const remove = solid.useAction(removeMember);
    expectTypeOf(remove.pendingInputs).toEqualTypeOf<
      readonly { userId: string }[]
    >();
  });
});

describe("svelte", () => {
  it("types the bound client", () => {
    const bs = svelte.getBetterSupabase<Client>();
    expectTypeOf(bs.db).toEqualTypeOf<Client["db"]>();
    expectTypeOf(bs.queries).toEqualTypeOf<Client["queries"]>();
    expectTypeOf(bs.auth.current).toEqualTypeOf<AuthSnapshot>();
    expectTypeOf(
      bs.liveQuery(() => null).current,
    ).toEqualTypeOf<SubscriptionStatus>();
    const remove = bs.action(removeMember);
    expectTypeOf(remove.error?.kind).not.toBeAny();
    expectTypeOf(remove.run).parameter(0).toEqualTypeOf<{ userId: string }>();
  });
});
