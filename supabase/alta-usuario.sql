-- =====================================================================
-- BubaManía · Alta manual de una persona del personal
--
-- Úsalo cuando la función "usuarios" no esté publicada en Supabase
-- (la app te ofrece este mismo SQL ya rellenado al fallar el alta).
--
-- PASO 1. Crea la cuenta en Supabase:
--   Authentication > Users > Add user > Create new user
--   - Correo: el de la persona
--   - Password: mínimo 8 caracteres
--   - Marca "Auto Confirm User"
--
-- PASO 2. Cambia las TRES comillas de abajo y ejecuta este archivo en
--   SQL Editor > New query > Run.
--
-- Roles válidos: admin · gerente · mesero · cocinero · repartidor
-- El nombre no se puede repetir: es el que aparece en pedidos y tickets.
-- =====================================================================

insert into public.staff (user_id, nombre, rol, email, activo)
select id,
       'Nombre de la persona',        -- <<< nombre visible en la app
       'cocinero',                    -- <<< rol
       email, true
  from auth.users
 where lower(email) = 'correo@ejemplo.com'   -- <<< correo, en minúsculas
on conflict (user_id) do update
   set nombre = excluded.nombre,
       rol    = excluded.rol,
       email  = excluded.email,
       activo = true;

-- Revisa cómo quedó el personal
select nombre, rol, email, activo
  from public.staff
 order by rol, nombre;

-- Si no aparece la persona, es que el PASO 1 no se completó:
-- vuelve a Authentication > Users y confirma que el correo exista.
