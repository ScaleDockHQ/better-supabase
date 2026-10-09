import { useMutation, useQuery } from "@tanstack/react-query";
import { optimistic } from "better-supabase/query";
import {
  tenantOf,
  useDebouncedSearch,
  useLiveQuery,
  useSignIn,
  useSignOut,
} from "better-supabase/react";
import { type SubmitEvent } from "react";

import { useAuth, useQueries } from "./lib/hooks";
import { createCustomer, customerSpec } from "./queries";

function SignIn() {
  const signIn = useSignIn();
  const submit = async (event: SubmitEvent<HTMLFormElement>) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    await signIn.password({
      email: String(form.get("email")),
      password: String(form.get("password")),
    });
  };
  return (
    <form onSubmit={(event) => void submit(event)}>
      <input name="email" type="email" placeholder="Email" required />
      <input name="password" type="password" placeholder="Password" required />
      <button type="submit" disabled={signIn.pending}>
        Sign in
      </button>
      {signIn.error ? <p role="alert">{signIn.error.message}</p> : null}
    </form>
  );
}

function Customers({ organizationId }: { organizationId: string }) {
  const queries = useQueries();
  const search = useDebouncedSearch();
  const spec = customerSpec(search.term);
  const listQuery = queries.$spec(spec);
  const list = useQuery(listQuery);
  // Refetches the list when another tab or user changes a customer.
  useLiveQuery(spec);
  // The new row shows at once and rolls back if the insert fails.
  const create = useMutation({
    ...createCustomer(queries),
    ...optimistic.create(
      listQuery,
      (input: { readonly name: string }) => ({
        id: `pending-${input.name}`,
        name: input.name,
        status: "active",
      }),
      { position: "start" },
    ),
  });
  const add = (event: SubmitEvent<HTMLFormElement>) => {
    event.preventDefault();
    const form = event.currentTarget;
    const name = String(new FormData(form).get("name"));
    create.mutate({ name, organizationId });
    form.reset();
  };
  return (
    <section>
      <input
        value={search.value}
        onChange={(event) => {
          search.setValue(event.target.value);
        }}
        placeholder="Search"
      />
      {list.error ? <p role="alert">{list.error.message}</p> : null}
      {create.error ? <p role="alert">{create.error.message}</p> : null}
      <ul>
        {list.data?.map((customer) => (
          <li key={customer.id}>
            {customer.name} <small>{customer.status}</small>
          </li>
        ))}
      </ul>
      <form onSubmit={add}>
        <input name="name" placeholder="New customer" required />
        <button type="submit">Add</button>
      </form>
    </section>
  );
}

export function App() {
  const auth = useAuth();
  const { signOut } = useSignOut();
  switch (auth.status) {
    case "loading":
      return <p>Loading…</p>;
    case "signed-out":
      return <SignIn />;
    case "signed-in": {
      const organizationId = tenantOf(auth);
      return (
        <main>
          <header>
            {auth.user.email}{" "}
            <button onClick={() => void signOut()}>Sign out</button>
          </header>
          {organizationId ? (
            <Customers organizationId={organizationId} />
          ) : (
            <p>Your account has no organization.</p>
          )}
        </main>
      );
    }
    default: {
      const unreachable: never = auth;
      throw new TypeError(`Unknown auth state ${String(unreachable)}`);
    }
  }
}
