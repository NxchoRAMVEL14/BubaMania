-- =====================================================================
-- BubaManía · Migración a la versión 1.3.0 (privacidad)
-- Solo si ya tenías la 1.2. Supabase > SQL Editor > New query > Run.
-- Agrega funciones para borrar datos de un cliente (derechos ARCO)
-- y para el borrado automático de datos vencidos. No borra nada al ejecutarse.
-- =====================================================================

-- Quita nombre, teléfono y dirección de un pedido (conserva productos y montos)
create or replace function public.anonimizar_pedido(d jsonb)
returns jsonb language sql immutable as $$
  select d
    || jsonb_build_object(
         'nombre', case d->>'tipo' when 'domicilio' then 'Domicilio' when 'llevar' then 'Para llevar' else coalesce(d->>'nombre','Pedido') end,
         'anonimizado', true,
         'comensales', coalesce((
            select jsonb_agg(c || '{"nombre":"Cliente"}'::jsonb order by n)
            from jsonb_array_elements(coalesce(d->'comensales','[]'::jsonb)) with ordinality as t(c, n)
         ), '[]'::jsonb))
    || case when d ? 'entrega'
            then jsonb_build_object('entrega', (d->'entrega') - array['telefono','cliente','ubicacion','referencias','lat','lng','pagaCon'])
            else '{}'::jsonb end;
$$;

-- Derecho de cancelación: borra al cliente y anonimiza sus pedidos
create or replace function public.borrar_cliente(tel text)
returns json language plpgsql security definer set search_path = public as $$
declare n_c int; n_p int;
begin
  if not public.is_staff() then raise exception 'No autorizado'; end if;
  delete from public.clientes where id = tel;
  get diagnostics n_c = row_count;
  update public.pedidos set data = public.anonimizar_pedido(data)
   where data->'entrega'->>'telefono' = tel;
  get diagnostics n_p = row_count;
  return json_build_object('clientes', n_c, 'pedidos', n_p);
end $$;

-- Conservación: borra clientes inactivos y anonimiza pedidos antiguos
create or replace function public.limpiar_datos_personales(meses int default 12)
returns json language plpgsql security definer set search_path = public as $$
declare corte timestamptz := now() - make_interval(months => greatest(coalesce(meses,12), 1));
        n_c int; n_p int;
begin
  if not public.is_staff() then raise exception 'No autorizado'; end if;
  delete from public.clientes where updated_at < corte;
  get diagnostics n_c = row_count;
  update public.pedidos set data = public.anonimizar_pedido(data)
   where creado < (extract(epoch from corte) * 1000)::bigint
     and not coalesce((data->>'anonimizado')::boolean, false);
  get diagnostics n_p = row_count;
  return json_build_object('clientes', n_c, 'pedidos', n_p);
end $$;

revoke all on function public.borrar_cliente(text) from public, anon;
revoke all on function public.limpiar_datos_personales(int) from public, anon;
grant execute on function public.borrar_cliente(text) to authenticated;
grant execute on function public.limpiar_datos_personales(int) to authenticated;
