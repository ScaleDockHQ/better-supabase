---
"better-supabase": patch
---

`doctor` rule BS243 no longer reports a `security definer` function because its body is wrapped in a tagged dollar quote such as `$function$`. It measures only the quoted literals inside the body, so a migration with a long body and short literals is quiet and a literal above 1,024 characters is still reported.
