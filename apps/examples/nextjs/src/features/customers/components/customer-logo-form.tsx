"use client";

import { useActionState } from "react";

import { uploadCustomerLogo } from "../customer-actions";

type State = Awaited<ReturnType<typeof uploadCustomerLogo>> | null;

export function CustomerLogoForm({ customerId }: { customerId: string }) {
  const [state, submit, pending] = useActionState(
    (_previous: State, form: FormData) => uploadCustomerLogo(form),
    null,
  );
  return (
    <form action={submit}>
      <input type="hidden" name="customerId" value={customerId} />
      <input
        type="file"
        name="logo"
        accept="image/png,image/jpeg,image/webp"
        aria-label="Logo"
        required
      />
      <button type="submit" disabled={pending}>
        Upload logo
      </button>
      {state?.ok === false ? <p role="alert">{state.error.message}</p> : null}
    </form>
  );
}
