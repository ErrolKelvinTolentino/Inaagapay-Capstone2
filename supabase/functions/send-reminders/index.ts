// send-reminders — Supabase Edge Function
//
// The day-before reminder for both things a mother has to show up for:
// her prenatal checkup, and a vaccination drive she was invited to.
//
// Run once a day by pg_cron. See
// `database/migrations/20260817_daily_reminder_job.sql`.
//
// WHY THIS IS NOT PL/pgSQL
// ------------------------
// The reminder needs to send SMS, which means an HTTP call with a provider key
// that must not sit in the database, and it needs to write the same message
// wording the app already uses. Doing it in SQL would put a third copy of
// mother-facing message text in a third language.
//
// It holds NO clinical logic. Who is due for a drive was decided when the
// drive was scheduled, by the rules in
// `lib/services/vaccination_drive_service.dart`, and stored in
// `drive_invitations`. This function re-sends to a stored list. Whether a
// checkup is scheduled was decided by `PrenatalScheduleEngine` and stored in
// `checkup_schedule`. Nothing here decides who needs care.
//
// DATES ARE MANILA DATES
// ----------------------
// The job runs at 22:00 UTC to land at 6 AM Manila. At that moment the UTC
// date is still the previous day, so `CURRENT_DATE + 1` in UTC is *today* in
// Manila, not tomorrow — reminders would go out a day early, every day,
// silently. Every date here is computed in Asia/Manila.

const SEMAPHORE_ENDPOINT = "https://api.semaphore.co/api/v4/messages";
const MANILA_TZ = "Asia/Manila";

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

/// Today's date in Manila, as YYYY-MM-DD. `en-CA` formats exactly that way.
function manilaDate(offsetDays = 0): string {
  const now = new Date();
  now.setUTCDate(now.getUTCDate() + offsetDays);
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: MANILA_TZ,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
}

/// "August 19, 2026" — the same shape the invitation SMS uses, so the reminder
/// reads like a follow-up rather than a different system writing.
function friendlyDate(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  const months = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
  ];
  return `${months[m - 1]} ${d}, ${y}`;
}

/// Semaphore wants +639XXXXXXXXX. Numbers are stored however they were typed.
/// Returns null when it cannot be made into a Philippine mobile number, which
/// is a reason to skip her rather than to fail the run.
function normalisePhone(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const digits = String(raw).replace(/[^\d+]/g, "");
  let n = digits;
  if (n.startsWith("+63")) n = n.slice(3);
  else if (n.startsWith("63")) n = n.slice(2);
  else if (n.startsWith("0")) n = n.slice(1);
  if (!/^9\d{9}$/.test(n)) return null;
  return `+63${n}`;
}

function firstName(full: string | null | undefined): string {
  const name = String(full ?? "").trim();
  if (!name) return "Nanay";
  return name.split(/\s+/)[0];
}

/// The `role` claim of the caller's token, or null if there isn't one.
///
/// The signature is not checked here and does not need to be: Supabase's
/// gateway rejects an unsigned or forged token before this function runs. This
/// only reads what the verified token says about who is calling.
function callerRole(authHeader: string): string | null {
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  const parts = token.split(".");
  if (parts.length !== 3) return null;

  try {
    const payload = JSON.parse(
      atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")),
    );
    return typeof payload.role === "string" ? payload.role : null;
  } catch {
    return null;
  }
}

interface Env {
  supabaseUrl: string;
  serviceKey: string;
  smsKey: string | null;
  senderName: string;
}

async function db(
  env: Env,
  path: string,
  init: RequestInit = {},
): Promise<any> {
  const res = await fetch(`${env.supabaseUrl}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: env.serviceKey,
      Authorization: `Bearer ${env.serviceKey}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
      ...(init.headers ?? {}),
    },
  });
  if (!res.ok) {
    throw new Error(`${path} -> ${res.status} ${await res.text()}`);
  }
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}

/// One SMS. Returns false rather than throwing: one unreachable mother must
/// not stop the rest of the run.
async function sendSms(
  env: Env,
  to: string,
  message: string,
  dryRun: boolean,
): Promise<boolean> {
  if (dryRun) return true;
  if (!env.smsKey) return false;

  try {
    const res = await fetch(SEMAPHORE_ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      },
      body: new URLSearchParams({
        apikey: env.smsKey,
        number: to,
        message,
        sendername: env.senderName,
      }).toString(),
    });
    if (!res.ok) {
      console.error("Semaphore rejected", res.status, await res.text());
      return false;
    }
    const data = await res.json();
    const first = Array.isArray(data) ? data[0] : null;
    return Boolean(
      first &&
        (first.status === "Pending" || first.status === "Sent" ||
          first.message_id != null),
    );
  } catch (err) {
    console.error("SMS dispatch failed:", err);
    return false;
  }
}

/// The in-app copy, so a reminder survives a deleted text.
async function notifyInApp(
  env: Env,
  accountId: number | null,
  title: string,
  message: string,
  type: string,
  dryRun: boolean,
): Promise<void> {
  if (dryRun || accountId == null) return;
  try {
    await db(env, "notifications", {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        account_id: accountId,
        title,
        message,
        type,
      }),
    });
  } catch (err) {
    console.error("In-app notification failed:", err);
  }
}

/// Queued, not sent. Nothing in this project consumes `email_queue` yet — see
/// the note in the deployment checklist. Queuing keeps the reminder consistent
/// with what the rest of the app does, and starts working the day a queue
/// processor exists, without this function needing to change.
async function queueEmail(
  env: Env,
  recipient: string | null,
  subject: string,
  html: string,
  dryRun: boolean,
): Promise<boolean> {
  if (dryRun || !recipient) return false;
  try {
    await db(env, "email_queue", {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        recipient,
        subject,
        html_content: html,
      }),
    });
    return true;
  } catch (err) {
    console.error("Email queue failed:", err);
    return false;
  }
}

// ── Prenatal checkups ───────────────────────────────────────────────────────

async function remindCheckups(
  env: Env,
  onDate: string,
  dryRun: boolean,
): Promise<Record<string, number>> {
  const rows = await db(
    env,
    "checkup_schedule?select=schedule_id,scheduled_date,mother_id," +
      "mothers(account_id,accounts(first_name,last_name,phone_number,email_address))" +
      `&scheduled_date=eq.${onDate}&status=eq.scheduled`,
  ) ?? [];

  let smsSent = 0, smsFailed = 0, skipped = 0, emailsQueued = 0;

  // Already reminded in this run's window? The notification row is the record,
  // matching what the existing SQL reminder used, so a retry after a partial
  // failure does not text anybody twice.
  const accountIds = rows
    .map((r: any) => r.mothers?.account_id)
    .filter((id: unknown) => id != null);

  let alreadyDone = new Set<number>();
  if (accountIds.length) {
    const since = new Date(Date.now() - 20 * 60 * 60 * 1000).toISOString();
    const existing = await db(
      env,
      `notifications?select=account_id&type=eq.checkup_reminder` +
        `&title=eq.Checkup%20Tomorrow&created_at=gt.${since}` +
        `&account_id=in.(${accountIds.join(",")})`,
    ) ?? [];
    alreadyDone = new Set(existing.map((n: any) => n.account_id));
  }

  for (const row of rows) {
    const account = row.mothers?.accounts;
    const accountId = row.mothers?.account_id ?? null;
    if (accountId != null && alreadyDone.has(accountId)) {
      skipped++;
      continue;
    }

    const name = firstName(account?.first_name);
    const when = friendlyDate(row.scheduled_date);

    // Under 160 characters: Semaphore bills per segment, and a reminder that
    // spills to 161 doubles the cost of every reminder the clinic ever sends.
    const message =
      `Kumusta ${name}! Paalala po: may prenatal checkup kayo bukas, ` +
      `${when}. Salamat po. - AGAPAY`;

    const phone = normalisePhone(account?.phone_number);
    if (phone) {
      const ok = await sendSms(env, phone, message, dryRun);
      ok ? smsSent++ : smsFailed++;
    } else {
      skipped++;
    }

    if (
      await queueEmail(
        env,
        account?.email_address ?? null,
        "Prenatal checkup tomorrow",
        `<p>Kumusta ${name},</p><p>Paalala po: may prenatal checkup kayo bukas, ` +
          `<strong>${when}</strong>.</p><p>Salamat po,<br/>InaAgapay</p>`,
        dryRun,
      )
    ) {
      emailsQueued++;
    }

    await notifyInApp(
      env,
      accountId,
      "Checkup Tomorrow",
      `Paalala po: may prenatal checkup kayo bukas, ${when}.`,
      "checkup_reminder",
      dryRun,
    );
  }

  return {
    due: rows.length,
    sms_sent: smsSent,
    sms_failed: smsFailed,
    emails_queued: emailsQueued,
    skipped,
  };
}

// ── Vaccination drives ──────────────────────────────────────────────────────

async function remindDrives(
  env: Env,
  onDate: string,
  dryRun: boolean,
): Promise<Record<string, number>> {
  const drives = await db(
    env,
    "immunization_schedule?select=immunization_schedule_id,schedule_date," +
      `vaccines(vaccine_name)&schedule_date=eq.${onDate}`,
  ) ?? [];

  let smsSent = 0, smsFailed = 0, skipped = 0, emailsQueued = 0, invited = 0;

  for (const drive of drives) {
    const scheduleId = drive.immunization_schedule_id;
    const vaccineName = drive.vaccines?.vaccine_name ?? "vaccination";
    const when = friendlyDate(drive.schedule_date);

    // Only those not yet reminded. `reminded_at` is the guard: a second run on
    // the same day finds nothing left to send.
    const invitations = await db(
      env,
      "drive_invitations?select=invitation_id,child_name,phone_number," +
        "email_address,mother_id," +
        "mothers(account_id,accounts(first_name,phone_number,email_address))" +
        `&immunization_schedule_id=eq.${scheduleId}&reminded_at=is.null`,
    ) ?? [];

    invited += invitations.length;

    for (const inv of invitations) {
      const account = inv.mothers?.accounts;
      const accountId = inv.mothers?.account_id ?? null;
      const name = firstName(account?.first_name);

      // The live number first, the one the invitation went to as a fallback.
      // If she changed her number since the drive was scheduled, the reminder
      // should follow her.
      const phone = normalisePhone(account?.phone_number) ??
        normalisePhone(inv.phone_number);

      const child = inv.child_name;
      const message = child
        ? `Kumusta ${name}! Paalala: may ${vaccineName} drive bukas, ${when}. ` +
          `Isama po si ${child}. - AGAPAY`
        : `Kumusta ${name}! Paalala: may ${vaccineName} drive bukas, ${when}. ` +
          `Inaasahan po namin kayo. - AGAPAY`;

      if (phone) {
        const ok = await sendSms(env, phone, message, dryRun);
        ok ? smsSent++ : smsFailed++;
      } else {
        skipped++;
      }

      if (
        await queueEmail(
          env,
          account?.email_address ?? inv.email_address ?? null,
          `${vaccineName} drive tomorrow`,
          `<p>Kumusta ${name},</p><p>Paalala po: may <strong>${vaccineName}</strong> ` +
            `drive bukas, <strong>${when}</strong>.` +
            (child ? ` Isama po si ${child}.` : "") +
            `</p><p>Salamat po,<br/>InaAgapay</p>`,
          dryRun,
        )
      ) {
        emailsQueued++;
      }

      await notifyInApp(
        env,
        accountId,
        `${vaccineName} drive tomorrow`,
        child
          ? `Paalala po: may ${vaccineName} drive bukas, ${when}. Isama po si ${child}.`
          : `Paalala po: may ${vaccineName} drive bukas, ${when}.`,
        "vaccine_reminder",
        dryRun,
      );

      // Marked whatever the outcome. A number that failed today will fail
      // again in an hour, and retrying it on the next run would text everyone
      // who succeeded a second time.
      if (!dryRun) {
        try {
          await db(
            env,
            `drive_invitations?invitation_id=eq.${inv.invitation_id}`,
            {
              method: "PATCH",
              headers: { Prefer: "return=minimal" },
              body: JSON.stringify({ reminded_at: new Date().toISOString() }),
            },
          );
        } catch (err) {
          console.error("Could not mark invitation reminded:", err);
        }
      }
    }
  }

  return {
    drives: drives.length,
    invited,
    sms_sent: smsSent,
    sms_failed: smsFailed,
    emails_queued: emailsQueued,
    skipped,
  };
}

// ── Entry point ─────────────────────────────────────────────────────────────

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return json({ ok: false, error: "Function is not configured" }, 503);
  }

  // This endpoint spends SMS credits, so it is not open to anonymous callers.
  //
  // Supabase's gateway has already verified the JWT's signature before the
  // request reaches here, so the claims inside it can be trusted. What is
  // checked is the role: `service_role` for the scheduled job, `postgres` for
  // a run from the dashboard's Test panel. `anon` — the key shipped inside the
  // mobile app, readable by anyone who unpacks it — is refused.
  //
  // The first version of this compared the whole token against
  // SUPABASE_SERVICE_ROLE_KEY. That looked stricter and was merely brittle:
  // it rejected the dashboard, and it assumes the platform injects that
  // variable in exactly the form the caller presents, which stopped being
  // reliable once Supabase introduced its second style of API key.
  const auth = req.headers.get("Authorization") ?? "";
  const role = callerRole(auth);
  const allowed = role === "service_role" ||
    role === "postgres" ||
    auth === `Bearer ${serviceKey}`;

  if (!allowed) {
    return json({
      ok: false,
      error: "Not authorised",
      caller_role: role ?? "unreadable token",
    }, 401);
  }

  const env: Env = {
    supabaseUrl,
    serviceKey,
    smsKey: Deno.env.get("SEMAPHORE_API_KEY") ?? null,
    senderName: Deno.env.get("SEMAPHORE_SENDER_NAME") ?? "AGAPAY",
  };

  let body: { for_date?: string; dry_run?: boolean } = {};
  try {
    body = await req.json();
  } catch {
    // No body is the normal case for a scheduled run.
  }

  // `for_date` lets a specific day be rehearsed without waiting for it, and
  // `dry_run` reports who would be texted without spending a credit. Both
  // exist so this can be demonstrated rather than described.
  const target = body.for_date ?? manilaDate(1);
  const dryRun = body.dry_run === true;

  if (!/^\d{4}-\d{2}-\d{2}$/.test(target)) {
    return json({ ok: false, error: "for_date must be YYYY-MM-DD" }, 400);
  }

  // The two halves run independently on purpose. They share nothing but the
  // date, and a fault in one must not silence the other: this project's
  // database was found without `checkup_schedule` at all, and with both halves
  // under one try the missing table would have taken the drive reminders down
  // with it — nobody reminded, and a 500 as the only clue.
  let checkups: Record<string, unknown>;
  try {
    checkups = await remindCheckups(env, target, dryRun);
  } catch (err) {
    console.error("Checkup reminders failed:", err);
    checkups = { error: String(err) };
  }

  let drives: Record<string, unknown>;
  try {
    drives = await remindDrives(env, target, dryRun);
  } catch (err) {
    console.error("Drive reminders failed:", err);
    drives = { error: String(err) };
  }

  const summary = {
    ok: !("error" in checkups) && !("error" in drives),
    dry_run: dryRun,
    manila_today: manilaDate(0),
    reminding_for: target,
    checkups,
    drives,
  };

  console.log("send-reminders", JSON.stringify(summary));

  // 207: some of it worked. A run that reminded every mother due for a drive
  // and failed on checkups is neither a success nor a failure, and reporting
  // it as either loses the half that matters.
  return json(summary, summary.ok ? 200 : 207);
});
