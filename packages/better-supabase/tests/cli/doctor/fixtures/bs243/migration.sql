-- A migration whose function body is wrapped in a tagged dollar quote.
-- The body is far longer than the literal limit; every literal inside it is short.
create or replace function private.record_steps()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into private.audit_trail (kind, note) values ('step 0', 'recorded step 0 of the migration');
  insert into private.audit_trail (kind, note) values ('step 1', 'recorded step 1 of the migration');
  insert into private.audit_trail (kind, note) values ('step 2', 'recorded step 2 of the migration');
  insert into private.audit_trail (kind, note) values ('step 3', 'recorded step 3 of the migration');
  insert into private.audit_trail (kind, note) values ('step 4', 'recorded step 4 of the migration');
  insert into private.audit_trail (kind, note) values ('step 5', 'recorded step 5 of the migration');
  insert into private.audit_trail (kind, note) values ('step 6', 'recorded step 6 of the migration');
  insert into private.audit_trail (kind, note) values ('step 7', 'recorded step 7 of the migration');
  insert into private.audit_trail (kind, note) values ('step 8', 'recorded step 8 of the migration');
  insert into private.audit_trail (kind, note) values ('step 9', 'recorded step 9 of the migration');
  insert into private.audit_trail (kind, note) values ('step 10', 'recorded step 10 of the migration');
  insert into private.audit_trail (kind, note) values ('step 11', 'recorded step 11 of the migration');
  insert into private.audit_trail (kind, note) values ('step 12', 'recorded step 12 of the migration');
  insert into private.audit_trail (kind, note) values ('step 13', 'recorded step 13 of the migration');
  insert into private.audit_trail (kind, note) values ('step 14', 'recorded step 14 of the migration');
  insert into private.audit_trail (kind, note) values ('step 15', 'recorded step 15 of the migration');
  insert into private.audit_trail (kind, note) values ('step 16', 'recorded step 16 of the migration');
  insert into private.audit_trail (kind, note) values ('step 17', 'recorded step 17 of the migration');
  insert into private.audit_trail (kind, note) values ('step 18', 'recorded step 18 of the migration');
  insert into private.audit_trail (kind, note) values ('step 19', 'recorded step 19 of the migration');
  insert into private.audit_trail (kind, note) values ('step 20', 'recorded step 20 of the migration');
  insert into private.audit_trail (kind, note) values ('step 21', 'recorded step 21 of the migration');
  insert into private.audit_trail (kind, note) values ('step 22', 'recorded step 22 of the migration');
  insert into private.audit_trail (kind, note) values ('step 23', 'recorded step 23 of the migration');
  insert into private.audit_trail (kind, note) values ('step 24', 'recorded step 24 of the migration');
  insert into private.audit_trail (kind, note) values ('step 25', 'recorded step 25 of the migration');
  insert into private.audit_trail (kind, note) values ('step 26', 'recorded step 26 of the migration');
  insert into private.audit_trail (kind, note) values ('step 27', 'recorded step 27 of the migration');
  insert into private.audit_trail (kind, note) values ('step 28', 'recorded step 28 of the migration');
  insert into private.audit_trail (kind, note) values ('step 29', 'recorded step 29 of the migration');
  insert into private.audit_trail (kind, note) values ('step 30', 'recorded step 30 of the migration');
  insert into private.audit_trail (kind, note) values ('step 31', 'recorded step 31 of the migration');
  insert into private.audit_trail (kind, note) values ('step 32', 'recorded step 32 of the migration');
  insert into private.audit_trail (kind, note) values ('step 33', 'recorded step 33 of the migration');
  insert into private.audit_trail (kind, note) values ('step 34', 'recorded step 34 of the migration');
  insert into private.audit_trail (kind, note) values ('step 35', 'recorded step 35 of the migration');
  insert into private.audit_trail (kind, note) values ('step 36', 'recorded step 36 of the migration');
  insert into private.audit_trail (kind, note) values ('step 37', 'recorded step 37 of the migration');
  insert into private.audit_trail (kind, note) values ('step 38', 'recorded step 38 of the migration');
  insert into private.audit_trail (kind, note) values ('step 39', 'recorded step 39 of the migration');
  insert into private.audit_trail (kind, note) values ('step 40', 'recorded step 40 of the migration');
  insert into private.audit_trail (kind, note) values ('step 41', 'recorded step 41 of the migration');
  insert into private.audit_trail (kind, note) values ('step 42', 'recorded step 42 of the migration');
  insert into private.audit_trail (kind, note) values ('step 43', 'recorded step 43 of the migration');
  insert into private.audit_trail (kind, note) values ('step 44', 'recorded step 44 of the migration');
  insert into private.audit_trail (kind, note) values ('step 45', 'recorded step 45 of the migration');
  insert into private.audit_trail (kind, note) values ('step 46', 'recorded step 46 of the migration');
  insert into private.audit_trail (kind, note) values ('step 47', 'recorded step 47 of the migration');
  insert into private.audit_trail (kind, note) values ('step 48', 'recorded step 48 of the migration');
  insert into private.audit_trail (kind, note) values ('step 49', 'recorded step 49 of the migration');
  insert into private.audit_trail (kind, note) values ('step 50', 'recorded step 50 of the migration');
  insert into private.audit_trail (kind, note) values ('step 51', 'recorded step 51 of the migration');
  insert into private.audit_trail (kind, note) values ('step 52', 'recorded step 52 of the migration');
  insert into private.audit_trail (kind, note) values ('step 53', 'recorded step 53 of the migration');
  insert into private.audit_trail (kind, note) values ('step 54', 'recorded step 54 of the migration');
  insert into private.audit_trail (kind, note) values ('step 55', 'recorded step 55 of the migration');
  insert into private.audit_trail (kind, note) values ('step 56', 'recorded step 56 of the migration');
  insert into private.audit_trail (kind, note) values ('step 57', 'recorded step 57 of the migration');
  insert into private.audit_trail (kind, note) values ('step 58', 'recorded step 58 of the migration');
  insert into private.audit_trail (kind, note) values ('step 59', 'recorded step 59 of the migration');
end;
$function$;
