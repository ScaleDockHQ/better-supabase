---
"better-supabase": minor
---

`useAction(action, { onSuccess, onError })` and `useActionForm(action, { onSuccess, onError, resetOnSuccess })` in `better-supabase/react` call a `bs.action()` Server Action and track its result. `useAction` gives `run(input)`, `pending`, `data`, `error` and `pendingInputs` (the inputs in flight, for a row that shows its change before the server confirms it); its input type drops `FormData` (`ActionInputOf`). `useActionForm` gives `formProps` to spread on the `<form>`, keeps the fields when the action fails, and returns `fieldErrors` from a `validation` error. `fieldErrorsOf(error)` does the same for any `DbError`.

`createErrorMessages(messages)` in `better-supabase` takes a message for every `DbError` kind and returns the function that formats one; leaving a kind out is a type error.
