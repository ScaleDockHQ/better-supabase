CREATE OR REPLACE FUNCTION public.projects_reject_archived_rename()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if old.archived_at is not null and new.name <> old.name then
    raise exception 'an archived project cannot be renamed'
      using hint = 'PROJECT_ARCHIVED';
  end if;
  return new;
end;
$function$;
