import Link from 'next/link';

import { next } from '../lib/supabase.server';
import { createCustomer } from './actions';

export default async function Home() {
  const { auth, db } = await next.server();
  if (auth.kind !== 'user') {
    return (
      <main>
        <p>
          <Link href="/login">Sign in</Link> to see your customers.
        </p>
      </main>
    );
  }
  const customers = await db.customers
    .findMany({
      select: ['id', 'name', 'status'],
      orderBy: { name: 'asc' },
      limit: 50,
    })
    .orThrow();
  return (
    <main>
      <h1>Customers</h1>
      <ul>
        {customers.map((customer) => (
          <li key={customer.id}>
            {customer.name} <small>{customer.status}</small>
          </li>
        ))}
      </ul>
      <form
        action={async (form: FormData) => {
          'use server';
          await createCustomer(form);
        }}
      >
        <input name="name" placeholder="New customer" required />
        <button type="submit">Add</button>
      </form>
    </main>
  );
}
