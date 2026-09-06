/* =====================================================
   InaAgapay Admin Web — Central Supabase Client & Config
   Single Source of Truth for Database Connection & Key Rotation
   ===================================================== */
(function (root) {
  "use strict";

  const SUPABASE_URL = "https://krooorixhjwygcsdoomg.supabase.co";
  const SUPABASE_ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtyb29vcml4aGp3eWdjc2Rvb21nIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ0NjI5NDIsImV4cCI6MjEwMDAzODk0Mn0.iVIxsgZhd_k0c-rDOjRK5J9xBiL0z-bH2l1LXH9IksU";

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
