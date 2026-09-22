# BubaManía · versión 1.4.0

App de pedidos (en local, para llevar y a domicilio), cuentas por persona, meseros, propinas, reparto, cocina, caja, menú con QR y tickets.

- `index.html`: app del personal (requiere usuario y contraseña).
- `aviso-privacidad.html`: aviso de privacidad público (se enlaza desde el menú, el ticket y WhatsApp).
- `logo.jpg`, `favicon.png`, `icon-192.png`, `icon-512.png`: logotipo e íconos.
- `menu.html`: menú público para clientes (el QR apunta aquí).
- `config.js`: aquí van la URL y la clave pública de Supabase.
- `supabase/schema.sql`: base de datos completa (instalación nueva).
- `supabase/migracion-1.1.sql` a `1.4`: solo para actualizar instalaciones anteriores.
- `supabase/functions/domicilio/index.ts`: función que calcula km, tiempo y busca direcciones.
- `supabase/functions/usuarios/index.ts`: función para crear usuarios y asignar contraseñas desde la app.
- `manual.html` y carpeta `manual/`: manual de uso con imágenes (se abre desde la app).
- `manual/manual.pdf`: el mismo manual para imprimir o mandar por WhatsApp.
- `manifest.webmanifest` e íconos: para instalarla en el celular como app.

## Paso 1. Supabase (base de datos)

1. Entra a https://supabase.com y crea un proyecto nuevo (región: la más cercana, por ejemplo `East US`).
2. Ve a **SQL Editor → New query**, pega todo `supabase/schema.sql` y presiona **Run**.
3. Ve a **Authentication → Users → Add user → Create new user**. Crea un usuario por dispositivo o por persona (por ejemplo `caja@bubamania.com`, `mesero@bubamania.com`, `cocina@bubamania.com`) y marca **Auto Confirm User**.
4. Regresa al **SQL Editor** y da de alta a cada usuario como personal. El nombre aparece como mesero sugerido y como autor de las mejoras:

   ```sql
   insert into public.staff (user_id, nombre)
   select id, 'Caja' from auth.users where email = 'caja@bubamania.com'
   on conflict (user_id) do nothing;
   ```
5. Recomendado: en **Authentication → Sign In / Providers**, desactiva **Allow new users to sign up**. Aunque alguien cree una cuenta, no verá pedidos si no está en la tabla `staff`.
6. Ve a **Project Settings → API Keys** y copia la **Project URL** y la clave pública (**anon** o **publishable**).

## Paso 1.5. Rutas y distancias (pedidos a domicilio)

Sin este paso la app funciona, pero los km se calculan en línea recta (aproximado) y no se pueden buscar direcciones escritas.

1. Crea una cuenta gratis en https://account.heigit.org (OpenRouteService) y copia tu **API key**. Es personal: no la pongas en `config.js` ni en GitHub.
2. En Supabase ve a **Edge Functions → Secrets** (o Project Settings → Edge Functions) y agrega un secreto llamado `ORS_API_KEY` con tu clave.
3. Ve a **Edge Functions → Deploy a new function → Via Editor**. Nómbrala exactamente `domicilio`, borra el código de ejemplo, pega todo `supabase/functions/domicilio/index.ts` y presiona **Deploy**. Deja activada la verificación JWT.
   Si tu panel no muestra la opción de editor, puedes publicarla desde una computadora con Node.js: `npx supabase login`, `npx supabase link --project-ref TU_REF` y `npx supabase functions deploy domicilio` dentro de esta carpeta; el secreto se agrega con `npx supabase secrets set ORS_API_KEY=tu_clave`.
4. En la app: **Ajustes → Reparto a domicilio → Usar mi ubicación actual** (estando en el local) y luego **Probar cálculo de rutas**.

## Paso 2. Configurar

Abre `config.js` y pega tus datos:

```js
window.BUBA_CONFIG = {
  url: "https://abcdefgh.supabase.co",
  anonKey: "tu-clave-publica"
};
```

La clave pública puede estar visible en GitHub; la seguridad la dan las reglas del paso 1. **Nunca** uses la clave `service_role` o `secret`.

## Paso 3. GitHub Pages (hosting gratis)

1. En GitHub crea un repositorio **público** llamado `bubamania`.
2. **Add file → Upload files** y arrastra todos los archivos de esta carpeta (incluida la carpeta `supabase`). Presiona **Commit changes**.
3. Ve a **Settings → Pages**. En **Source** elige **Deploy from a branch**, rama `main`, carpeta `/ (root)` y **Save**.
4. En 1 a 2 minutos tu app estará en `https://TU-USUARIO.github.io/bubamania/` y el menú en `https://TU-USUARIO.github.io/bubamania/menu.html`.

## Paso 4. Instalar en los celulares

- **iPhone (Safari):** abre la app → botón Compartir → **Agregar a inicio**.
- **Android (Chrome):** abre la app → menú ⋮ → **Instalar app** o **Agregar a pantalla principal**.

## Paso 5. QR e impresora

- En **Ajustes** el QR ya apunta a `menu.html`. Toca **Imprimir QR** para ponerlo en las mesas.
- Configura el ancho de papel (58 u 80 mm) y prueba con **Imprimir ticket de prueba**.
- La impresora debe aparecer en el diálogo de impresión del celular (AirPrint en iPhone; servicio de impresión en Android).

## Actualizar a la versión 1.4 (roles)

1. **Usuarios base.** En Supabase → **Authentication → Users**, confirma que existan `osirv92@gmail.com` (administrador) y `wakoshill21@gmail.com` (gerente). Si falta alguno: **Add user → Create new user**, con **Auto Confirm User**.
2. **Migraciones.** En **SQL Editor** ejecuta, en orden, las que te falten: `migracion-1.3.sql` (si no la corriste) y luego `migracion-1.4.sql`. Al final verás una tabla con el personal y su rol. Todo usuario que ya existía queda como **Mesero**; ajústalo después desde la app.
3. **Función `usuarios`.** En **Edge Functions → Deploy a new function → Via Editor**, nómbrala exactamente `usuarios`, pega `supabase/functions/usuarios/index.ts` y presiona **Deploy** (deja activada la verificación JWT). No necesita secretos.
4. **GitHub.** Sube y reemplaza todos los archivos de esta carpeta.
5. **Probar.** Entra con tu correo: arriba debe decir **Administrador** y abajo **Versión 1.4.0**. En **Ajustes → Usuarios y roles** da de alta a meseros, cocineros y repartidores.

## ¿Ya tenías la versión 1.2?

1. En Supabase ejecuta `supabase/migracion-1.3.sql` (borrado de datos de clientes y conservación).
2. En GitHub sube y reemplaza todos los archivos de la carpeta, incluidos `aviso-privacidad.html`, `logo.jpg`, `favicon.png`, los íconos y la carpeta `manual/`.
3. En la app, ve a Ajustes → Privacidad de clientes e imprime el letrero de la cámara.

## ¿Ya tenías la versión 1.1?

1. En Supabase ejecuta `supabase/migracion-1.2.sql` (tabla de clientes frecuentes).
2. Haz el **Paso 1.5** (función de rutas).
3. En GitHub reemplaza `index.html`, `manual.html` y `README.md`, y sube la carpeta `manual/` completa y `supabase/functions/`.
4. En Ajustes configura la ubicación del local, la regla de envío, repartidores y plataformas.

## ¿Ya tenías la versión 1.0?

1. En Supabase ejecuta `supabase/migracion-1.1.sql` (agrega la tabla de mejoras). No borra nada.
2. En GitHub sube y reemplaza `index.html`, `manual.html`, `README.md` y la carpeta `manual/` completa (incluye `manual.pdf` si quieres).
3. En **Ajustes** de la app agrega a tus meseros y elige cómo se reparten las propinas.
4. En los celulares, cierra y vuelve a abrir la app. Si sigue mostrando la versión anterior, recarga la página.

## Para actualizar la app

Edita o vuelve a subir `index.html` o `menu.html` en GitHub. Los productos, precios y pedidos viven en Supabase, así que no se pierden al actualizar.

## Límites conocidos

- Si dos personas editan **el mismo pedido al mismo tiempo**, gana el último cambio guardado.
- Necesita internet; no funciona sin conexión.
- La app no lee WhatsApp automáticamente: el enlace de ubicación se copia y pega.
- OpenRouteService no considera el tráfico en tiempo real; el tiempo es estimado.
- El aviso de privacidad es una base redactada conforme a la ley; conviene que lo revise un abogado antes de publicarlo.
- El plazo de conservación (12 meses) está escrito en el aviso: si lo cambias en la app, actualiza también el aviso.
- En el plan gratuito de Supabase, los proyectos sin actividad por un tiempo pueden pausarse. Revisa las condiciones vigentes en supabase.com/pricing.

## Historial de versiones

**1.4.0**
- Roles: Administrador, Gerente, Mesero, Cocinero y Repartidor, con permisos validados en la base de datos (políticas RLS y validación por campo).
- Mesero: ve solo sus pedidos, cobra y no cambia precios, productos libres, envío ni cancela.
- Cocinero: solo Cocina. Repartidor: solo sus entregas y las no asignadas.
- Ajustes → Usuarios y roles: alta de usuarios, cambio de rol, desactivar y asignar contraseña desde la app (función `usuarios`).
- Ajustes → Mi cuenta: cambiar contraseña y cerrar sesión.
- Mensajes claros cuando un rol intenta algo no permitido.

**1.3.0**
- Aviso de privacidad integral (`aviso-privacidad.html`) conforme a la LFPDPPP de 2025, con resumen al inicio.
- Aviso enlazado en menú público, pantalla de entrada, ticket y mensaje de confirmación por WhatsApp.
- Consentimiento de promociones por WhatsApp por cliente, guion para llamadas y lista de teléfonos que aceptan.
- Ajustes → Privacidad: buscar, enviar, corregir o borrar los datos de un cliente (derechos ARCO).
- Borrado automático diario: clientes sin pedidos en 12 meses y anonimización de pedidos antiguos.
- Letrero de videovigilancia imprimible con QR al aviso.
- Logotipo de BubaManía en la app, el menú, el manual e íconos.

**1.2.0**
- Nuevo pedido con tipo (En local, Para llevar, Domicilio) y origen (Presencial, Llamada, WhatsApp, Plataforma).
- Domicilio: teléfono con clientes frecuentes, ubicación desde enlace o dirección, mapa para ajustar, km y minutos con OpenRouteService y botón de ruta en Google Maps.
- Envío gratis hasta cierta distancia y cargo configurable al excederla.
- Pantalla de Reparto: salí a entregar, entregado y cobro, llamada y mensajes de WhatsApp.
- Modo del celular: completo, solo cocina o solo reparto.
- Caja: envíos cobrados, ventas por canal y entregas por repartidor. Ticket con datos de entrega y cambio a llevar.

**1.1.0**
- Número de versión visible en la entrada y en Ajustes.
- Meseros: alta en Ajustes, mesero por pedido, filtro por mesero y “Te atendió” en el ticket.
- Propinas: reparto individual o fondo común, con propina a entregar por mesero en Caja y en el corte impreso.
- Mejoras para la app: lista compartida de errores, mejoras e ideas, con botón para copiarla y pegarla en Claude.
- Manual de uso con imágenes (`manual.html` y `manual.pdf`).
- Lo que escribes ya no se borra cuando llegan cambios de otros celulares.

**1.0.0**
- Pedidos con cuentas por persona, precios editables, cocina, cobro, tickets 58/80 mm, menú con fotos y PDF, QR y corte de caja.
