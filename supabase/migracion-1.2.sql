-- =====================================================================
-- BubaManía · Migración a la versión 1.2.0 (pedidos a domicilio)
-- Solo si ya tenías la 1.1. Supabase > SQL Editor > New query > Run.
-- Agrega la tabla de clientes frecuentes. No borra nada.
-- =====================================================================
create table if not exists public.clientes (
  id         text primary key,          -- teléfono a 10 dígitos
  data       jsonb not null,
  updated_at timestamptz not null default now()
);

drop trigger if exists t_clientes on public.clientes;
create trigger t_clientes before update on public.clientes
  for each row execute function public.touch_updated_at();

alter table public.clientes enable row level security;
drop policy if exists "clientes solo personal" on public.clientes;
create policy "clientes solo personal" on public.clientes
  for all to authenticated using (public.is_staff()) with check (public.is_staff());
