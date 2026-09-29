import { useMutation, useQuery } from '@tanstack/react-query';
import { type SubmitEvent, useState } from 'react';

import { useAuth, useQueries, useSupabase } from './lib/hooks';
import { createCustomer, customerList } from './queries';

function organizationOf(
  claims: Readonly<Record<string, unknown>>,
): string | undefined {
  const metadata = claims['app_metadata'];
  if (typeof metadata !== 'object' || metadata === null) return undefined;
  const orgId = (metadata as Record<string, unknown>)['org_id'];
  return typeof orgId === 'string' ? orgId : undefined;
}

function SignIn() {
  const supabase = useSupabase();
  const [error, setError] = useState<string>();
  const submit = async (event: SubmitEvent<HTMLFormElement>) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const { error: signInError } = await supabase.auth.signInWithPassword({
      email: String(form.get('email')),
      password: String(form.get('password')),
    });
    setError(signInError?.message);
  };
  return (
    <form onSubmit={(event) => void submit(event)}>
      <input name="email" type="email" placeholder="Email" required />
      <input name="password" type="password" placeholder="Password" required />
      <button type="submit">Sign in</button>
      {error ? <p role="alert">{error}</p> : null}
    </form>
  );
}

function Customers({ organizationId }: { organizationId: string }) {
  const queries = useQueries();
  const [search, setSearch] = useState('');
  const list = useQuery(customerList(queries, search));
  const create = useMutation(createCustomer(queries));
  const add = (event: SubmitEvent<HTMLFormElement>) => {
    event.preventDefault();
    const form = event.currentTarget;
    const name = String(new FormData(form).get('name'));
    create.mutate({ name, organizationId }, { onSuccess: () => form.reset() });
  };
  return (
    <section>
      <input
        value={search}
        onChange={(event) => setSearch(event.target.value)}
        placeholder="Search"
      />
      {list.error ? <p role="alert">{list.error.message}</p> : null}
      <ul>
        {list.data?.map((customer) => (
          <li key={customer.id}>
            {customer.name} <small>{customer.status}</small>
          </li>
        ))}
      </ul>
      <form onSubmit={add}>
        <input name="name" placeholder="New customer" required />
        <button type="submit" disabled={create.isPending}>
          Add
        </button>
      </form>
    </section>
  );
}

export function App() {
  const auth = useAuth();
  const supabase = useSupabase();
  switch (auth.status) {
    case 'loading':
      return <p>Loading…</p>;
    case 'signed-out':
      return <SignIn />;
    case 'signed-in': {
      const organizationId = organizationOf(auth.claims);
      return (
        <main>
          <header>
            {auth.user.email}{' '}
            <button onClick={() => void supabase.auth.signOut()}>
              Sign out
            </button>
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
