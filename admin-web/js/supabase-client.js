/* =====================================================
   InaAgapay Admin Web — Central Supabase Client & Config
   Single Source of Truth for Database Connection & Key Rotation
   ===================================================== */
(function (root) {
  "use strict";

  const SUPABASE_URL = "https://ctpyzeauiwgccsopbjpz.supabase.co";
  const SUPABASE_ANON = "sb_publishable_NzKIr8xr6JwYemrrTIEQag_RDCVi3S_";

  root.SUPABASE_URL = SUPABASE_URL;
  root.SUPABASE_ANON = SUPABASE_ANON;

  let clientInstance = null;
  function getClient() {
    if (!clientInstance && typeof root.supabase !== "undefined" && typeof root.supabase.createClient === "function") {
      clientInstance = root.supabase.createClient(SUPABASE_URL, SUPABASE_ANON);
    }
    return clientInstance;
  }

  // Eagerly initialize if supabase UMD is already loaded
  if (typeof root.supabase !== "undefined" && typeof root.supabase.createClient === "function") {
    root.db = getClient();
  }

  root.InaSupabase = {
    url: SUPABASE_URL,
    anonKey: SUPABASE_ANON,
    get client() { return getClient(); },
    get db() { return getClient(); },
    createClient() {
      if (typeof root.supabase !== "undefined" && typeof root.supabase.createClient === "function") {
        return root.supabase.createClient(SUPABASE_URL, SUPABASE_ANON);
      }
      return null;
    }
  };
})(typeof window !== "undefined" ? window : globalThis);
