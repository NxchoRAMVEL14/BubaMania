-- =====================================================================
-- BubaManía · Migración a la versión 1.1.0
-- Solo si YA ejecutaste schema.sql antes (instalación de la v1.0).
-- Supabase > SQL Editor > New query > pega este archivo > Run.
-- Agrega la tabla de mejoras. Meseros y propinas no requieren cambios.
-- =====================================================================
create table if not exists public.mejoras (
  id         text primary key,
  data       jsonb not null,
  updated_at timestamptz not null default now()
);

drop trigger if exists t_mejoras on public.mejoras;
create trigger t_mejoras before update on public.mejoras
  for each row execute function public.touch_updated_at();

alter table public.mejoras enable row level security;
drop policy if exists "mejoras solo personal" on public.mejoras;
create policy "mejoras solo personal" on public.mejoras
  for all to authenticated using (public.is_staff()) with check (public.is_staff());

do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'mejoras') then
    alter publication supabase_realtime add table public.mejoras;
  end if;
end $$;

-- Opcional: registra el nombre de cada usuario del personal (aparece como mesero sugerido y autor de mejoras)
-- update public.staff set nombre = 'Luis' where user_id = (select id from auth.users where email = 'luis@bubamania.com');
