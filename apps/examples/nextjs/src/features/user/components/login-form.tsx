"use client";

import { useRouter } from "next/navigation";
import { useActionState } from "react";

import { useSupabase } from "@/lib/hooks";

import { sessionChanged } from "../user-actions";

export function LoginForm() {
  const supabase = useSupabase();
  const router = useRouter();
  const [error, submit, pending] = useActionState(
    async (_previous: string | null, form: FormData) => {
      const { error: signInError } = await supabase.auth.signInWithPassword({
        email: String(form.get("email")),
        password: String(form.get("password")),
      });
      if (signInError) return signInError.message;
      await sessionChanged();
      router.push("/");
      return null;
    },
    null,
  );
  return (
    <form action={submit}>
      <input name="email" type="email" placeholder="Email" required />
      <input name="password" type="password" placeholder="Password" required />
      <button type="submit" disabled={pending}>
        Sign in
      </button>
      {error ? <p role="alert">{error}</p> : null}
    </form>
  );
}
