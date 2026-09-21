// BubaManía · Función "domicilio" (Supabase Edge Function)
// Calcula rutas y busca direcciones con OpenRouteService sin exponer la clave.
// Requiere el secreto ORS_API_KEY (Edge Functions > Secrets).
// Acciones: "ruta", "buscar", "expandir" (enlaces cortos de Google Maps).

const ORS = "https://api.openrouteservice.org";
const KEY = Deno.env.get("ORS_API_KEY") ?? "";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

type Punto = { lat: number; lng: number };
const valido = (p: Punto | undefined) =>
  !!p && typeof p.lat === "number" && typeof p.lng === "number" && Math.abs(p.lat) <= 90 && Math.abs(p.lng) <= 180;

const HOSTS_PERMITIDOS = /^https:\/\/(maps\.app\.goo\.gl|goo\.gl|maps\.google\.[a-z.]+|www\.google\.[a-z.]+|google\.[a-z.]+|maps\.apple\.com|maps\.apple)\//i;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { accion, desde, hasta, texto, cerca, url } = await req.json();

    if (accion === "ruta") {
      if (!KEY) return json({ error: "Falta configurar ORS_API_KEY" }, 500);
      if (!valido(desde) || !valido(hasta)) return json({ error: "Coordenadas inválidas" }, 400);
      // OpenRouteService espera longitud,latitud
      const u = `${ORS}/v2/directions/driving-car?start=${desde.lng},${desde.lat}&end=${hasta.lng},${hasta.lat}`;
      const r = await fetch(u, { headers: { Authorization: KEY } });
      if (!r.ok) return json({ error: `OpenRouteService respondió ${r.status}` }, 502);
      const d = await r.json();
      const s = d?.features?.[0]?.properties?.summary ?? {};
      return json({ km: (s.distance ?? 0) / 1000, min: Math.max(1, Math.round((s.duration ?? 0) / 60)) });
    }

    if (accion === "buscar") {
      if (!KEY) return json({ error: "Falta configurar ORS_API_KEY" }, 500);
      if (!texto || String(texto).length > 300) return json({ error: "Dirección inválida" }, 400);
      const q = new URLSearchParams({ text: String(texto), "boundary.country": "MX", size: "5" });
      if (valido(cerca)) { q.set("focus.point.lat", String(cerca.lat)); q.set("focus.point.lon", String(cerca.lng)); }
      const r = await fetch(`${ORS}/geocode/search?${q}`, { headers: { Authorization: KEY } });
      if (!r.ok) return json({ error: `OpenRouteService respondió ${r.status}` }, 502);
      const d = await r.json();
      const resultados = (d?.features ?? []).map((f: any) => ({
        lat: f.geometry.coordinates[1], lng: f.geometry.coordinates[0], label: f.properties?.label ?? "",
      }));
      return json({ resultados });
    }

    if (accion === "expandir") {
      if (!url || !HOSTS_PERMITIDOS.test(String(url))) return json({ error: "Enlace no permitido" }, 400);
      let actual = String(url);
      for (let i = 0; i < 6; i++) {
        const r = await fetch(actual, { redirect: "manual", headers: { "User-Agent": "Mozilla/5.0" } });
        const loc = r.headers.get("location");
        if (loc && r.status >= 300 && r.status < 400) { actual = new URL(loc, actual).toString(); continue; }
        const html = (await r.text()).slice(0, 30000);
        return json({ url: actual, html });
      }
      return json({ url: actual });
    }

    return json({ error: "Acción desconocida" }, 400);
  } catch (e) {
    return json({ error: String(e?.message ?? e) }, 500);
  }
});
