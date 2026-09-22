-- =====================================================================
-- BubaManía · Migración a la versión 1.4.0 (roles y permisos)
-- Supabase > SQL Editor > New query > pega TODO este archivo > Run.
-- Se puede volver a ejecutar sin problema.
--
-- Roles: admin, gerente, mesero, cocinero, repartidor.
-- Los permisos se validan AQUÍ, en la base de datos, no solo en la app.
-- =====================================================================

-- ---------- 1. Columnas de rol en el personal ----------
alter table public.staff add column if not exists rol    text    not null default 'mesero';
alter table public.staff add column if not exists email  text;
alter table public.staff add column if not exists activo boolean not null default true;
alter table public.staff drop constraint if exists staff_rol_check;
alter table public.staff add constraint staff_rol_check
  check (rol in ('admin','gerente','mesero','cocinero','repartidor'));

update public.staff s set email = u.email
  from auth.users u where u.id = s.user_id and s.email is null;

-- Nombres únicos: los pedidos de cada mesero se identifican por su nombre
do $$ begin
  create unique index if not exists staff_nombre_unico on public.staff (lower(nombre));
exception when unique_violation then
  raise notice 'Hay dos personas del personal con el mismo nombre. Cámbialo en la tabla staff y vuelve a ejecutar.';
end $$;

-- ---------- 2. Funciones de identidad ----------
create or replace function public.mi_rol()
returns text language sql stable security definer set search_path = public as $$
  select rol from public.staff where user_id = auth.uid() and activo;
$$;

create or replace function public.mi_nombre()
returns text language sql stable security definer set search_path = public as $$
  select nombre from public.staff where user_id = auth.uid() and activo;
$$;

create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.staff where user_id = auth.uid() and activo);
$$;

create or replace function public.es_gestor()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.mi_rol() in ('admin','gerente'), false);
$$;

grant execute on function public.mi_rol(), public.mi_nombre(), public.is_staff(), public.es_gestor() to anon, authenticated;

-- ---------- 3. Personal: quién ve a quién ----------
drop policy if exists "staff ve su registro" on public.staff;
drop policy if exists "staff lectura" on public.staff;
create policy "staff lectura" on public.staff
  for select to authenticated using (user_id = auth.uid() or public.es_gestor());

-- Cambiar nombre, rol o estado de alguien (solo admin y gerente)
create or replace function public.actualizar_personal(uid uuid, p_nombre text, p_rol text, p_activo boolean)
returns void language plpgsql security definer set search_path = public as $$
declare yo text := public.mi_rol(); actual text;
begin
  if yo is null or yo not in ('admin','gerente') then raise exception 'Solo administrador o gerente pueden modificar usuarios'; end if;
  if p_rol not in ('admin','gerente','mesero','cocinero','repartidor') then raise exception 'Rol no válido'; end if;
  select rol into actual from public.staff where user_id = uid;
  if not found then raise exception 'Ese usuario no existe'; end if;
  if yo = 'gerente' and (actual = 'admin' or p_rol = 'admin') then
    raise exception 'Solo el administrador puede modificar administradores';
  end if;
  if uid = auth.uid() and (p_rol <> actual or not p_activo) then
    raise exception 'No puedes cambiar tu propio rol ni desactivarte';
  end if;
  if coalesce(trim(p_nombre),'') = '' then raise exception 'El nombre es obligatorio'; end if;
  update public.staff set nombre = trim(p_nombre), rol = p_rol, activo = p_activo where user_id = uid;
end $$;
revoke all on function public.actualizar_personal(uuid,text,text,boolean) from public, anon;
grant execute on function public.actualizar_personal(uuid,text,text,boolean) to authenticated;

-- ---------- 4. Menú, configuración y archivos: escriben solo admin y gerente ----------
drop policy if exists "menu escritura personal" on public.menu;
drop policy if exists "menu escritura gestores" on public.menu;
create policy "menu escritura gestores" on public.menu
  for all to authenticated using (public.es_gestor()) with check (public.es_gestor());

drop policy if exists "config escritura personal" on public.config;
drop policy if exists "config escritura gestores" on public.config;
create policy "config escritura gestores" on public.config
  for all to authenticated using (public.es_gestor()) with check (public.es_gestor());

drop policy if exists "menu archivos subir" on storage.objects;
drop policy if exists "menu archivos editar" on storage.objects;
drop policy if exists "menu archivos borrar" on storage.objects;
create policy "menu archivos subir" on storage.objects
  for insert to authenticated with check (bucket_id = 'menu' and public.es_gestor());
create policy "menu archivos editar" on storage.objects
  for update to authenticated using (bucket_id = 'menu' and public.es_gestor());
create policy "menu archivos borrar" on storage.objects
  for delete to authenticated using (bucket_id = 'menu' and public.es_gestor());

-- ---------- 5. Clientes frecuentes: gestores y meseros (capturan domicilios) ----------
drop policy if exists "clientes solo personal" on public.clientes;
drop policy if exists "clientes lectura" on public.clientes;
drop policy if exists "clientes alta" on public.clientes;
drop policy if exists "clientes cambios" on public.clientes;
drop policy if exists "clientes borrar" on public.clientes;
create policy "clientes lectura" on public.clientes for select to authenticated
  using (public.es_gestor() or public.mi_rol() = 'mesero');
create policy "clientes alta" on public.clientes for insert to authenticated
  with check (public.es_gestor() or public.mi_rol() = 'mesero');
create policy "clientes cambios" on public.clientes for update to authenticated
  using (public.es_gestor() or public.mi_rol() = 'mesero')
  with check (public.es_gestor() or public.mi_rol() = 'mesero');
create policy "clientes borrar" on public.clientes for delete to authenticated
  using (public.es_gestor());

-- ---------- 6. Mejoras: todos anotan; gestores editan y borran ----------
drop policy if exists "mejoras solo personal" on public.mejoras;
drop policy if exists "mejoras lectura" on public.mejoras;
drop policy if exists "mejoras alta" on public.mejoras;
drop policy if exists "mejoras gestion" on public.mejoras;
drop policy if exists "mejoras borrar" on public.mejoras;
create policy "mejoras lectura" on public.mejoras for select to authenticated using (public.is_staff());
create policy "mejoras alta" on public.mejoras for insert to authenticated with check (public.is_staff());
create policy "mejoras gestion" on public.mejoras for update to authenticated
  using (public.es_gestor()) with check (public.es_gestor());
create policy "mejoras borrar" on public.mejoras for delete to authenticated using (public.es_gestor());

-- ---------- 7. Pedidos: quién ve y quién cambia ----------
drop policy if exists "pedidos solo personal" on public.pedidos;
drop policy if exists "pedidos lectura" on public.pedidos;
drop policy if exists "pedidos alta" on public.pedidos;
drop policy if exists "pedidos cambios" on public.pedidos;
drop policy if exists "pedidos borrar" on public.pedidos;

create or replace function public.puede_ver_pedido(d jsonb)
returns boolean language sql stable security definer set search_path = public as $$
  select case public.mi_rol()
    when 'admin'      then true
    when 'gerente'    then true
    when 'cocinero'   then true
    when 'mesero'     then d->>'mesero' = public.mi_nombre()
    when 'repartidor' then d->>'tipo' = 'domicilio'
                           and coalesce(d->'entrega'->>'repartidor','') in ('', public.mi_nombre())
    else false end;
$$;

create policy "pedidos lectura" on public.pedidos for select to authenticated
  using (public.puede_ver_pedido(data));
create policy "pedidos alta" on public.pedidos for insert to authenticated
  with check (public.es_gestor() or (public.mi_rol() = 'mesero' and data->>'mesero' = public.mi_nombre()));
create policy "pedidos cambios" on public.pedidos for update to authenticated
  using (public.puede_ver_pedido(data))
  with check (
    public.es_gestor()
    or public.mi_rol() = 'cocinero'
    or (public.mi_rol() = 'mesero' and data->>'mesero' = public.mi_nombre())
    or (public.mi_rol() = 'repartidor' and data->>'tipo' = 'domicilio'
        and data->'entrega'->>'repartidor' = public.mi_nombre()));
create policy "pedidos borrar" on public.pedidos for delete to authenticated using (public.es_gestor());

-- ---------- 8. Validación campo por campo según el rol ----------
-- Quita de cada producto las llaves indicadas (para comparar pedidos)
create or replace function public._items_sin(d jsonb, claves text[])
returns jsonb language sql immutable as $$
  select coalesce(jsonb_agg(
           (c - 'items') || jsonb_build_object('items', coalesce((
              select jsonb_agg(i - claves order by k)
              from jsonb_array_elements(coalesce(c->'items','[]'::jsonb)) with ordinality t2(i,k)), '[]'::jsonb))
         order by n), '[]'::jsonb)
  from jsonb_array_elements(coalesce(d->'comensales','[]'::jsonb)) with ordinality t(c,n);
$$;

-- Costo de envío según la regla guardada en Ajustes
create or replace function public.calc_envio(km numeric)
returns numeric language sql stable security definer set search_path = public as $$
  select case
    when km is null or km <= coalesce((c.data->'envio'->>'gratisHastaKm')::numeric, 0) then 0
    else coalesce((c.data->'envio'->>'cargoFijo')::numeric, 0)
         + ceil(km - coalesce((c.data->'envio'->>'gratisHastaKm')::numeric, 0))
           * coalesce((c.data->'envio'->>'cargoPorKm')::numeric, 0)
  end
  from public.config c where c.id = 1;
$$;

-- El mesero solo puede usar precios del menú (no productos libres ni precios cambiados)
create or replace function public._check_precios_mesero(o jsonb, n jsonb)
returns void language plpgsql stable security definer set search_path = public as $$
declare it jsonb; prev jsonb; pm numeric;
begin
  for it in
    select i from jsonb_array_elements(coalesce(n->'comensales','[]'::jsonb)) c,
                  jsonb_array_elements(coalesce(c->'items','[]'::jsonb)) i
  loop
    prev := null;
    if o is not null then
      select i2 into prev
        from jsonb_array_elements(coalesce(o->'comensales','[]'::jsonb)) c2,
             jsonb_array_elements(coalesce(c2->'items','[]'::jsonb)) i2
       where i2->>'id' = it->>'id' limit 1;
    end if;
    -- Producto que ya estaba con el mismo precio y nombre: sin cambios
    if prev is not null and (prev->>'precio')::numeric = (it->>'precio')::numeric
       and prev->>'nombre' is not distinct from it->>'nombre' then continue; end if;
    if coalesce(it->>'prodId','') = '' then
      raise exception 'Solo gerente o administrador pueden agregar productos libres o combinaciones';
    end if;
    select (data->>'precio')::numeric into pm from public.menu where id = it->>'prodId';
    if pm is null or pm <> (it->>'precio')::numeric then
      raise exception 'Solo gerente o administrador pueden cambiar precios';
    end if;
  end loop;
end $$;

create or replace function public.validar_cambio_pedido()
returns trigger language plpgsql security definer set search_path = public as $$
declare r text := public.mi_rol(); yo text := public.mi_nombre();
        base_old jsonb; base_new jsonb;
begin
  -- Procesos del sistema (borrado de datos) y el editor SQL no se validan
  if current_setting('buba.sistema', true) = 'on' or auth.uid() is null then return new; end if;
  if r in ('admin','gerente') then return new; end if;

  if tg_op = 'INSERT' then
    if r = 'mesero' then perform public._check_precios_mesero(null, new.data); return new; end if;
    raise exception 'Tu rol no puede crear pedidos';
  end if;

  if r = 'cocinero' then
    -- Solo puede marcar productos como listos y cambiar el estado a "listo"
    base_old := (old.data - 'estado') || jsonb_build_object('comensales', public._items_sin(old.data, array['listo']));
    base_new := (new.data - 'estado') || jsonb_build_object('comensales', public._items_sin(new.data, array['listo']));
    if base_old <> base_new or new.data->>'estado' not in ('cocina','listo') then
      raise exception 'La cocina solo puede marcar pedidos como listos';
    end if;
    return new;

  elsif r = 'repartidor' then
    -- Solo puede actualizar la entrega (salida, entrega, cobro) y tomar entregas sin asignar
    base_old := (old.data - array['estado','cerrado'])
      || jsonb_build_object('entrega', coalesce(old.data->'entrega','{}'::jsonb) - array['estado','salida','entregado','recibido','envioPagado','repartidor'])
      || jsonb_build_object('comensales', (select coalesce(jsonb_agg(c - 'pago' order by n), '[]'::jsonb)
                                           from jsonb_array_elements(coalesce(old.data->'comensales','[]'::jsonb)) with ordinality t(c,n)));
    base_new := (new.data - array['estado','cerrado'])
      || jsonb_build_object('entrega', coalesce(new.data->'entrega','{}'::jsonb) - array['estado','salida','entregado','recibido','envioPagado','repartidor'])
      || jsonb_build_object('comensales', (select coalesce(jsonb_agg(c - 'pago' order by n), '[]'::jsonb)
                                           from jsonb_array_elements(coalesce(new.data->'comensales','[]'::jsonb)) with ordinality t(c,n)));
    if base_old <> base_new then
      raise exception 'El repartidor solo puede actualizar la entrega y el cobro';
    end if;
    if new.data->>'estado' is distinct from old.data->>'estado' and new.data->>'estado' <> 'pagado' then
      raise exception 'El repartidor solo puede marcar el pedido como pagado';
    end if;
    if coalesce(old.data->'entrega'->>'repartidor','') not in ('', yo) then
      raise exception 'Esta entrega está asignada a otro repartidor';
    end if;
    return new;

  elsif r = 'mesero' then
    if new.data->>'estado' = 'cancelado' and old.data->>'estado' is distinct from 'cancelado' then
      raise exception 'Solo gerente o administrador pueden cancelar pedidos';
    end if;
    if new.data->>'mesero' is distinct from old.data->>'mesero' then
      raise exception 'Solo gerente o administrador pueden reasignar pedidos';
    end if;
    perform public._check_precios_mesero(old.data, new.data);
    if (new.data->'entrega'->>'costoEnvio') is distinct from (old.data->'entrega'->>'costoEnvio')
       and coalesce((new.data->'entrega'->>'costoEnvio')::numeric, 0)
           <> coalesce(public.calc_envio((new.data->'entrega'->>'km')::numeric), 0) then
      raise exception 'Solo gerente o administrador pueden cambiar el costo de envío';
    end if;
    return new;
  end if;

  raise exception 'Tu usuario no tiene permiso para modificar pedidos';
end $$;

drop trigger if exists t_validar_pedido on public.pedidos;
create trigger t_validar_pedido before insert or update on public.pedidos
  for each row execute function public.validar_cambio_pedido();

-- ---------- 9. Privacidad: ajustar permisos de las funciones de la v1.3 ----------
create or replace function public.borrar_cliente(tel text)
returns json language plpgsql security definer set search_path = public as $$
declare n_c int; n_p int;
begin
  if not public.es_gestor() then raise exception 'Solo administrador o gerente pueden borrar datos de clientes'; end if;
  perform set_config('buba.sistema', 'on', true);
  delete from public.clientes where id = tel;
  get diagnostics n_c = row_count;
  update public.pedidos set data = public.anonimizar_pedido(data)
   where data->'entrega'->>'telefono' = tel;
  get diagnostics n_p = row_count;
  return json_build_object('clientes', n_c, 'pedidos', n_p);
end $$;

create or replace function public.limpiar_datos_personales(meses int default 12)
returns json language plpgsql security definer set search_path = public as $$
declare corte timestamptz := now() - make_interval(months => greatest(coalesce(meses,12), 1));
        n_c int; n_p int;
begin
  if not public.is_staff() then raise exception 'No autorizado'; end if;
  perform set_config('buba.sistema', 'on', true);
  delete from public.clientes where updated_at < corte;
  get diagnostics n_c = row_count;
  update public.pedidos set data = public.anonimizar_pedido(data)
   where creado < (extract(epoch from corte) * 1000)::bigint
     and not coalesce((data->>'anonimizado')::boolean, false);
  get diagnostics n_p = row_count;
  return json_build_object('clientes', n_c, 'pedidos', n_p);
end $$;

-- ---------- 10. Roles iniciales ----------
-- Administrador y gerente. Si todavía no existen sus usuarios, créalos en
-- Authentication > Users > Add user (con Auto Confirm) y vuelve a ejecutar este archivo.
insert into public.staff (user_id, nombre, rol, email, activo)
select id, 'Administrador', 'admin', email, true from auth.users where lower(email) = 'osirv92@gmail.com'
on conflict (user_id) do update set rol = 'admin', activo = true, email = excluded.email;

insert into public.staff (user_id, nombre, rol, email, activo)
select id, 'Rudy', 'gerente', email, true from auth.users where lower(email) = 'wakoshill21@gmail.com'
on conflict (user_id) do update set rol = 'gerente', activo = true, email = excluded.email;

do $$
begin
  if not exists (select 1 from auth.users where lower(email) = 'osirv92@gmail.com') then
    raise notice 'FALTA crear el usuario osirv92@gmail.com (administrador). Créalo y vuelve a ejecutar.';
  end if;
  if not exists (select 1 from auth.users where lower(email) = 'wakoshill21@gmail.com') then
    raise notice 'FALTA crear el usuario wakoshill21@gmail.com (gerente). Créalo y vuelve a ejecutar.';
  end if;
end $$;

-- Revisa el resultado:
select s.nombre, s.rol, s.email, s.activo from public.staff s order by s.rol, s.nombre;
