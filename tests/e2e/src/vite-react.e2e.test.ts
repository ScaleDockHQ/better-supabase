import { createClient } from "@supabase/supabase-js";
import { QueryClient } from "@tanstack/react-query";
import { createBrowser } from "better-supabase/client";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

import {
  createCustomer,
  customerList,
} from "@better-supabase/example-vite-react/queries";
import { sb } from "@better-supabase/example-vite-react/supabase";

import {
  ACME,
  cleanup,
  createUser,
  reachable,
  stack,
  type TestUser,
} from "./stack.ts";

describe.skipIf(!(await reachable()))("vite-react example", () => {
  let acme: TestUser;
  const rows = cleanup("customers");

  beforeAll(async () => {
    acme = await createUser(ACME);
  });
  afterAll(async () => {
    await rows.run();
    await acme.remove();
  });

  it("signs in, creates through a mutation and refetches the list", async () => {
    const browser = createBrowser(sb, {
      client: createClient(stack.url, stack.publishableKey, {
        auth: { persistSession: false },
      }),
    });
    await browser.supabase.auth.signInWithPassword({
      email: acme.email,
      password: acme.password,
    });
    await vi.waitFor(() => {
      expect(browser.auth.current().status).toBe("signed-in");
    });

    const queryClient = new QueryClient();
    const name = `Vite e2e ${crypto.randomUUID()}`;
    const mutation = createCustomer(browser.queries);
    const created = await mutation.mutationFn({ name, organizationId: ACME });
    rows.track(created.id);
    await mutation.onSuccess(
      created,
      { name, organizationId: ACME },
      undefined,
      { client: queryClient },
    );

    const list = await queryClient.query(customerList(browser.queries, name));
    expect(list).toEqual([{ id: created.id, name, status: "lead" }]);
    await browser.supabase.auth.signOut();
  });
});
