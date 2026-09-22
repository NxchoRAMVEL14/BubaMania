// BubaManía · Función "usuarios" (Supabase Edge Function)
// Permite al administrador y al gerente crear usuarios del personal
// y restablecer contraseñas desde la app, sin entrar a Supabase.
// Usa las variables que Supabase ya incluye: SUPABASE_URL, SUPABASE_ANON_KEY
// y SUPABASE_SERVICE_ROLE_KEY. No necesitas agregar secretos.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const ROLES = ["admin", "gerente", "mesero", "cocinero", "repartidor"];
const URL_ = Deno.env.get("SUPABASE_URL") ?? "";
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const auth = req.headers.get("Authorization") ?? "";
    const comoUsuario = createClient(URL_, ANON, { global: { headers: { Authorization: auth } } });
    const { data: { user } } = await comoUsuario.auth.getUser();
    if (!user) return json({ error: "Inicia sesión de nuevo" }, 401);

    const admin = createClient(URL_, SERVICE, { auth: { persistSession: false } });
    const { data: yo } = await admin.from("staff").select("rol, activo").eq("user_id", user.id).maybeSingle();
    if (!yo || !yo.activo || !["admin", "gerente"].includes(yo.rol)) {
      return json({ error: "Solo administrador o gerente pueden administrar usuarios" }, 403);
    }

    const body = await req.json();

    if (body.accion === "crear") {
      const email = String(body.email ?? "").trim().toLowerCase();
      const nombre = String(body.nombre ?? "").trim();
      const rol = String(body.rol ?? "");
      const password = String(body.password ?? "");
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "Correo no válido" }, 400);
      if (!nombre) return json({ error: "El nombre es obligatorio" }, 400);
      if (!ROLES.includes(rol)) return json({ error: "Rol no válido" }, 400);
      if (rol === "admin" && yo.rol !== "admin") return json({ error: "Solo el administrador puede crear administradores" }, 403);
      if (password.length < 8) return json({ error: "La contraseña debe tener al menos 8 caracteres" }, 400);

      const { data: dup } = await admin.from("staff").select("user_id").eq("nombre", nombre).maybeSingle();
      if (dup) return json({ error: "Ya existe alguien del personal con ese nombre. Usa uno distinto (por ejemplo, con apellido)." }, 400);

      const { data: creado, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
      if (error) {
        const msg = /already|registered|exists/i.test(error.message) ? "Ese correo ya tiene una cuenta" : error.message;
        return json({ error: msg }, 400);
      }
      const { error: e2 } = await admin.from("staff").insert({ user_id: creado.user.id, nombre, rol, email, activo: true });
      if (e2) {
        await admin.auth.admin.deleteUser(creado.user.id);
        return json({ error: "No se pudo registrar en el personal: " + e2.message }, 500);
      }
      return json({ ok: true, user_id: creado.user.id });
    }

    if (body.accion === "contrasena") {
      const uid = String(body.user_id ?? "");
      const password = String(body.password ?? "");
      if (password.length < 8) return json({ error: "La contraseña debe tener al menos 8 caracteres" }, 400);
      const { data: objetivo } = await admin.from("staff").select("rol").eq("user_id", uid).maybeSingle();
      if (!objetivo) return json({ error: "Ese usuario no existe" }, 404);
      if (objetivo.rol === "admin" && yo.rol !== "admin") return json({ error: "Solo el administrador puede cambiar la contraseña de un administrador" }, 403);
      const { error } = await admin.auth.admin.updateUserById(uid, { password });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    return json({ error: "Acción desconocida" }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
