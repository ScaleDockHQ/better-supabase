'use client';

import { useRouter } from 'next/navigation';
import { type FormEvent, useState } from 'react';

import { useSupabase } from '../../lib/hooks';

export default function Login() {
  const supabase = useSupabase();
  const router = useRouter();
  const [error, setError] = useState<string>();
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const { error: signInError } = await supabase.auth.signInWithPassword({
      email: String(form.get('email')),
      password: String(form.get('password')),
    });
    if (signInError) return setError(signInError.message);
    router.push('/');
    router.refresh();
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
