-- Strip the newlines Postgres inserts into encode(bytea, 'base64') so a
-- compact permissions bitset still decodes after 456 keys.
create or replace function better_supabase.permission_bitset(all_keys text[], held text[])
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  width integer := ceil(coalesce(cardinality(all_keys), 0) / 8.0);
  bytes bytea;
  i integer;
  slot integer;
  value integer;
begin
  if width < 1 then
    return '';
  end if;
  bytes := decode(repeat('00', width), 'hex');
  if held is null then
    return translate(rtrim(encode(bytes, 'base64'), '='), E'+/\n', '-_');
  end if;
  for i in 1 .. coalesce(cardinality(all_keys), 0) loop
    if all_keys[i] = any (held) then
      slot := (i - 1) / 8;
      value := get_byte(bytes, slot) | (1 << ((i - 1) % 8));
      bytes := set_byte(bytes, slot, value);
    end if;
  end loop;
  return translate(rtrim(encode(bytes, 'base64'), '='), E'+/\n', '-_');
end;
$$;
