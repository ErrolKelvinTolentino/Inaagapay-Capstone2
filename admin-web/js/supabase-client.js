/* =====================================================
   Supabase Client — InaAgapay Admin Portal
   ===================================================== */
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const SUPABASE_URL  = 'https://krooorixhjwygcsdoomg.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtyb29vcml4aGp3eWdjc2Rvb21nIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ0NjI5NDIsImV4cCI6MjEwMDAzODk0Mn0.iVIxsgZhd_k0c-rDOjRK5J9xBiL0z-bH2l1LXH9IksU';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON);
