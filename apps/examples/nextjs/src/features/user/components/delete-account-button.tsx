"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";

import { useSupabase } from "@/lib/hooks";

import { deleteMyAccount, sessionChanged } from "../user-actions";

export function DeleteAccountButton() {
  const supabase = useSupabase();
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string>();
  return (
    <>
      <button
        type="button"
        disabled={pending}
        onClick={() =>
          startTransition(async () => {
            if (!confirm("Delete your account and all your data?")) return;
            const result = await deleteMyAccount(undefined);
            if (!result.ok) {
              setError(result.error.message);
              return;
            }
            // The user is gone: drop the session without calling Auth.
            await supabase.auth.signOut({ scope: "local" });
            await sessionChanged();
            router.push("/login");
          })
        }
      >
        Delete account
      </button>
      {error ? <p role="alert">{error}</p> : null}
    </>
  );
}
