'use client';

import { useActionState } from 'react';

import { createCustomer } from '../customer-actions';

type State = Awaited<ReturnType<typeof createCustomer>> | null;

export function CreateCustomerForm() {
  const [state, submit, pending] = useActionState(
    (_previous: State, form: FormData) => createCustomer(form),
    null,
  );
  return (
    <form action={submit}>
      <input name="name" placeholder="New customer" required />
      <button type="submit" disabled={pending}>
        Add
      </button>
      {state?.ok === false ? <p role="alert">{state.error.message}</p> : null}
    </form>
  );
}
