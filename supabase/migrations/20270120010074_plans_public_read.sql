ALTER POLICY "plan_features_read" ON "public"."plan_features" TO "anon", "authenticated";

ALTER POLICY "plans_read" ON "public"."plans" TO "anon", "authenticated";

grant select on public.plans to anon;

grant select on public.plan_features to anon;
