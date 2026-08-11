// send-sms — Supabase Edge Function
//
// Keeps the SMS provider API key server-side. The admin portal is a static site,
// so any key embedded in its JavaScript is readable by anyone who opens
// view-source. This function is the only place the key should be used.
//
// The portal calls this function first and falls back to its old direct call if
// the function is not deployed, so deploying is safe at any time. Once you have
// confirmed a real SMS arrives through this function, remove the fallback block
// in admin-web/pages/account-create.html (search for LEGACY SMS FALLBACK).
//
// DEPLOY — see the checklist in the task notes for exact commands.

const SEMAPHORE_ENDPOINT = "https://api.semaphore.co/api/v4/messages";
const PH_MOBILE = /^\+639\d{9}$/;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ sent: false, error: "Method not allowed" }, 405);
  }

  const apiKey = Deno.env.get("SEMAPHORE_API_KEY");
  if (!apiKey) {
    console.error("SEMAPHORE_API_KEY is not configured");
    return json({ sent: false, error: "SMS provider is not configured" }, 503);
  }

  let payload: { number?: string; message?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ sent: false, error: "Invalid JSON body" }, 400);
  }

  const number = String(payload.number ?? "").trim();
  const message = String(payload.message ?? "").trim();

  if (!PH_MOBILE.test(number)) {
    return json({ sent: false, error: "Invalid Philippine mobile number" }, 400);
  }
  if (!message || message.length > 1000) {
    return json({ sent: false, error: "Message must be 1-1000 characters" }, 400);
  }

  const params = new URLSearchParams({
    apikey: apiKey,
    number,
    message,
    sendername: Deno.env.get("SEMAPHORE_SENDER_NAME") ?? "AGAPAY",
  });

  try {
    const res = await fetch(SEMAPHORE_ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      },
      body: params.toString(),
    });

    if (!res.ok) {
      console.error("Semaphore responded", res.status, await res.text());
      return json({ sent: false, error: "SMS provider rejected the request" }, 502);
    }

    const data = await res.json();
    const first = Array.isArray(data) ? data[0] : null;
    const sent = Boolean(
      first && (first.status === "Pending" || first.status === "Sent" || first.message_id != null),
    );

    // Never echo the message body back — it contains a temporary password.
    return json({ sent });
  } catch (err) {
    console.error("SMS dispatch failed:", err);
    return json({ sent: false, error: "SMS dispatch failed" }, 502);
  }
});
