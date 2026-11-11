-- Removes the customers, notes and tenants an earlier tier seed wrote, so a run
-- with another tier starts from the same rows. The append-only audit and
-- notification tables keep their rows; a second run adds more of them.
delete from public.notes where body like 'Tier note %';
delete from public.customers where name like 'Tier customer %';
delete from public.organizations where slug like 'scale-tenant-%';
