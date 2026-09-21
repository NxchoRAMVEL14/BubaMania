-- =====================================================================
-- BubaManía · Esquema de base de datos para Supabase (versión 1.2.0)
-- Instalación NUEVA: ejecuta solo este archivo.
-- Pega TODO este archivo en Supabase > SQL Editor > New query > Run.
-- Se puede volver a ejecutar sin romper nada.
-- =====================================================================

-- ---------- 1. Tablas ----------
create table if not exists public.staff (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  nombre     text,
  created_at timestamptz not null default now()
);

create table if not exists public.config (
  id         int primary key default 1 check (id = 1),
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.menu (
  id         text primary key,
  data       jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.pedidos (
  id         text primary key,
  data       jsonb not null,
  creado     bigint generated always as ((data->>'creado')::bigint) stored,
  fecha      text   generated always as (data->>'fecha') stored,
  updated_at timestamptz not null default now()
);
create table if not exists public.mejoras (
  id         text primary key,
  data       jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.clientes (
  id         text primary key,          -- teléfono a 10 dígitos
  data       jsonb not null,
  updated_at timestamptz not null default now()
);

create index if not exists pedidos_creado_idx on public.pedidos (creado desc);
create index if not exists pedidos_fecha_idx  on public.pedidos (fecha);

-- ---------- 2. Funciones ----------
-- ¿El usuario que inició sesión es parte del personal?
create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.staff where user_id = auth.uid());
$$;
grant execute on function public.is_staff() to anon, authenticated;

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists t_config  on public.config;
drop trigger if exists t_menu    on public.menu;
drop trigger if exists t_pedidos on public.pedidos;
create trigger t_config  before update on public.config  for each row execute function public.touch_updated_at();
create trigger t_menu    before update on public.menu    for each row execute function public.touch_updated_at();
create trigger t_pedidos before update on public.pedidos for each row execute function public.touch_updated_at();
drop trigger if exists t_clientes on public.clientes;
create trigger t_clientes before update on public.clientes for each row execute function public.touch_updated_at();
drop trigger if exists t_mejoras on public.mejoras;
create trigger t_mejoras before update on public.mejoras for each row execute function public.touch_updated_at();

-- ---------- 3. Seguridad (Row Level Security) ----------
alter table public.staff   enable row level security;
alter table public.config  enable row level security;
alter table public.menu    enable row level security;
alter table public.pedidos enable row level security;
alter table public.mejoras enable row level security;
alter table public.clientes enable row level security;

-- Personal: cada usuario solo ve su propio registro
drop policy if exists "staff ve su registro" on public.staff;
create policy "staff ve su registro" on public.staff
  for select to authenticated using (user_id = auth.uid());

-- Menú y configuración: cualquiera puede LEER (menú público del QR); solo el personal escribe
drop policy if exists "menu lectura publica" on public.menu;
create policy "menu lectura publica" on public.menu
  for select to anon, authenticated using (true);
drop policy if exists "menu escritura personal" on public.menu;
create policy "menu escritura personal" on public.menu
  for all to authenticated using (public.is_staff()) with check (public.is_staff());

drop policy if exists "config lectura publica" on public.config;
create policy "config lectura publica" on public.config
  for select to anon, authenticated using (true);
drop policy if exists "config escritura personal" on public.config;
create policy "config escritura personal" on public.config
  for all to authenticated using (public.is_staff()) with check (public.is_staff());

-- Pedidos: solo el personal lee y escribe
drop policy if exists "pedidos solo personal" on public.pedidos;
create policy "pedidos solo personal" on public.pedidos
  for all to authenticated using (public.is_staff()) with check (public.is_staff());

-- Mejoras: solo el personal
drop policy if exists "mejoras solo personal" on public.mejoras;
create policy "mejoras solo personal" on public.mejoras
  for all to authenticated using (public.is_staff()) with check (public.is_staff());

-- Clientes frecuentes (teléfonos y direcciones): solo el personal
drop policy if exists "clientes solo personal" on public.clientes;
create policy "clientes solo personal" on public.clientes
  for all to authenticated using (public.is_staff()) with check (public.is_staff());

-- ---------- 4. Tiempo real (sincronización entre celulares) ----------
do $$
declare t text;
begin
  foreach t in array array['menu','pedidos','config','mejoras'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- ---------- 5. Almacenamiento de fotos y PDF ----------
insert into storage.buckets (id, name, public)
values ('menu', 'menu', true)
on conflict (id) do nothing;

drop policy if exists "menu archivos lectura" on storage.objects;
create policy "menu archivos lectura" on storage.objects
  for select to anon, authenticated using (bucket_id = 'menu');
drop policy if exists "menu archivos subir" on storage.objects;
create policy "menu archivos subir" on storage.objects
  for insert to authenticated with check (bucket_id = 'menu' and public.is_staff());
drop policy if exists "menu archivos editar" on storage.objects;
create policy "menu archivos editar" on storage.objects
  for update to authenticated using (bucket_id = 'menu' and public.is_staff());
drop policy if exists "menu archivos borrar" on storage.objects;
create policy "menu archivos borrar" on storage.objects
  for delete to authenticated using (bucket_id = 'menu' and public.is_staff());

-- ---------- 6. Datos iniciales (precios de EJEMPLO, cámbialos en la app) ----------
insert into public.config (id, data) values (1, '{
  "negocio": "BubaManía",
  "papel": "80",
  "pie": "¡Gracias por tu visita!",
  "categorias": ["Sodas italianas","Frappés","Ice","Baguettes","Croissants","Alitas","Boneless","Extras"],
  "menuFotos": [],
  "menuPdf": "",
  "meseros": [],
  "propinaModo": "individual",
  "repartidores": [],
  "plataformas": ["Didi Food","Uber Eats","Rappi"],
  "prepMin": 15,
  "envio": {"gratisHastaKm": 3, "cargoFijo": 15, "cargoPorKm": 5}
}'::jsonb) on conflict (id) do nothing;

insert into public.menu (id, data) values
  ('soda-fresa',     '{"nombre":"Soda italiana fresa","precio":55,"cat":"Sodas italianas","desc":"","foto":"","activo":true,"orden":1}'),
  ('soda-mora',      '{"nombre":"Soda italiana mora azul","precio":55,"cat":"Sodas italianas","desc":"","foto":"","activo":true,"orden":2}'),
  ('frappe-taro',    '{"nombre":"Frappé taro","precio":65,"cat":"Frappés","desc":"","foto":"","activo":true,"orden":3}'),
  ('frappe-moka',    '{"nombre":"Frappé moka","precio":65,"cat":"Frappés","desc":"","foto":"","activo":true,"orden":4}'),
  ('ice-latte',      '{"nombre":"Ice latte","precio":55,"cat":"Ice","desc":"","foto":"","activo":true,"orden":5}'),
  ('baguette-jamon', '{"nombre":"Baguette jamón y queso","precio":75,"cat":"Baguettes","desc":"","foto":"","activo":true,"orden":6}'),
  ('croissant-jq',   '{"nombre":"Croissant jamón y queso","precio":60,"cat":"Croissants","desc":"","foto":"","activo":true,"orden":7}'),
  ('alitas-10',      '{"nombre":"Alitas 10 pzas","precio":130,"cat":"Alitas","desc":"","foto":"","activo":true,"orden":8}'),
  ('boneless-250',   '{"nombre":"Boneless 250 g","precio":120,"cat":"Boneless","desc":"","foto":"","activo":true,"orden":9}'),
  ('extra-perlas',   '{"nombre":"Extra perlas de tapioca","precio":15,"cat":"Extras","desc":"","foto":"","activo":true,"orden":10}')
on conflict (id) do nothing;

-- =====================================================================
-- DAR DE ALTA AL PERSONAL (hazlo después de crear cada usuario en
-- Authentication > Users > Add user). Cambia el correo y el nombre:
--
-- insert into public.staff (user_id, nombre)
-- select id, 'Caja' from auth.users where email = 'caja@bubamania.com'
-- on conflict (user_id) do nothing;
-- =====================================================================
