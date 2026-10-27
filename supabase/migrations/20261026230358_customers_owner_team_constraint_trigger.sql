DROP TRIGGER "customers_owner_team_check" ON "public"."customers";

CREATE CONSTRAINT TRIGGER customers_owner_team_check
  AFTER INSERT OR UPDATE OF owner_team_id ON public.customers NOT DEFERRABLE INITIALLY IMMEDIATE
  FOR EACH ROW
  WHEN ((new.owner_team_id IS NOT NULL))
  EXECUTE FUNCTION public.customers_owner_team_check();
