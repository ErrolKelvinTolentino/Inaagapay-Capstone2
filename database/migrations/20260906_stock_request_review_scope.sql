-- ==============================================================================
-- MIGRATION: 20260906_stock_request_review_scope.sql
--
-- An office may only decide stock requests raised inside the branch it
-- administers.
--
-- WHAT WAS OPEN
--
--   approve_inventory_stock_request, its _with_quantity successor and
--   reject_inventory_stock_request check only that the actor is an active
--   administrator:
--
--       PERFORM public.inventory_assert_actor(p_admin_id, 'admin');
--
--   Nothing ties the actor to the request. Any active portal account could
--   approve, reject and then issue against a request raised by a health centre
--   under a different RHU, or by another RHU entirely. 20260904 closed the
--   narrow case of an office deciding its OWN request; this closes the rest.
--
--   The portal never offered it -- it renders only requests inside PortalScope,
--   and portal-scope.js now denies outright when an account resolves to no
--   facility instead of falling open. But the anon key ships in the page, so
--   the RPC is reachable directly and client-side scoping is presentation, not
--   protection.
--
-- WHERE THE CHECK LIVES
--
--   Extended onto the trigger 20260904 already put on inventory_stock_requests,
--   rather than restated inside three function bodies that would then have to
--   be kept in step. Every one of them stamps reviewed_by and moves status off
--   'pending', so one BEFORE UPDATE catches all three and anything written
--   later.
--
-- WHAT IT DELIBERATELY DOES NOT BLOCK
--
--   Two escapes, both matching guards already in the codebase:
--
--     * The requesting facility has no parent_facility_id. The hierarchy is not
--       populated for it, so there is no branch to judge against and refusing
--       every approval would strand the workflow. inventory_assert_may_transfer
--       takes the same view of an unresolvable actor.
--
--     * The actor resolves to no facility. That is the seeded demo logins,
--       which predate facility_assignments; 20260829 leaves them alone for the
--       same reason and blocking here would lock them out of approvals.
--
--   Both are why this cannot be the only control. It removes the casual case,
--   not a determined one -- for that the tables need RLS, which is a larger
--   piece of work and would change what every screen can read.
--
-- Requires 20260821_mho_tier.sql (facility_subtree_ids,
-- inventory_actor_facility_id) and 20260904_rhu_stock_requests_to_mho.sql.
--
-- Safe to run more than once.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.inventory_stock_request_block_self_review()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_actor_facility BIGINT;
  v_req_parent     BIGINT;
  v_req_name       TEXT;
  v_actor_name     TEXT;
BEGIN
  -- Only the moment a decision is recorded.
  IF OLD.status IS DISTINCT FROM 'pending'
     OR NEW.status IS NOT DISTINCT FROM OLD.status
     OR NEW.reviewed_by IS NULL THEN
    RETURN NEW;
  END IF;

  v_actor_facility := public.inventory_actor_facility_id(NEW.reviewed_by);

  -- Unresolvable actor: a seeded login with no facility assignment. Left alone
  -- rather than blocked, as inventory_assert_may_transfer does.
  IF v_actor_facility IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT name, parent_facility_id
    INTO v_req_name, v_req_parent
    FROM public.health_facilities
   WHERE facility_id = NEW.facility_id;

  -- 1. Nobody decides their own request. Kept ahead of the branch test because
  --    a facility is inside its own subtree and would otherwise pass it.
  IF v_actor_facility = NEW.facility_id THEN
    RAISE EXCEPTION
      'Request #% was raised by % and cannot be decided there. It is for the office above to approve or reject.',
      NEW.request_id, COALESCE(v_req_name, 'this office')
      USING ERRCODE = '42501';
  END IF;

  -- 2. The hierarchy has to be populated for this facility before the branch
  --    can mean anything. Unlinked facility: allow, as before this migration.
  IF v_req_parent IS NULL THEN
    RETURN NEW;
  END IF;

  -- 3. The request must sit inside the branch this office administers.
  IF NOT EXISTS (
    SELECT 1 FROM public.facility_subtree_ids(v_actor_facility) s
     WHERE s.facility_id = NEW.facility_id
  ) THEN
    SELECT name INTO v_actor_name
      FROM public.health_facilities WHERE facility_id = v_actor_facility;

    RAISE EXCEPTION
      '% is not under %, so this account cannot decide request #%.',
      COALESCE(v_req_name, 'That facility'),
      COALESCE(v_actor_name, 'this office'),
      NEW.request_id
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_stock_request_block_self_review
  ON public.inventory_stock_requests;

CREATE TRIGGER trg_stock_request_block_self_review
  BEFORE UPDATE ON public.inventory_stock_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.inventory_stock_request_block_self_review();

COMMENT ON FUNCTION public.inventory_stock_request_block_self_review() IS
  'Refuses a stock request decision unless the reviewer administers the branch '
  'the request came from, and never for the reviewer''s own facility. Skipped '
  'where the hierarchy cannot answer: an unlinked requesting facility, or an '
  'actor with no facility assignment.';


-- ---------------------------------------------------------------------------
-- Who could decide what, as things stand. Read-only; run it to see whether the
-- hierarchy is populated enough for the check above to bite.
-- ---------------------------------------------------------------------------
SELECT f.facility_id,
       f.name,
       f.facility_type,
       parent.name AS reports_to,
       CASE
         WHEN f.parent_facility_id IS NULL
           THEN 'unlinked - requests from here are not scope-checked'
         ELSE 'checked against ' || parent.name
       END AS review_scope
  FROM public.health_facilities f
  LEFT JOIN public.health_facilities parent
         ON parent.facility_id = f.parent_facility_id
 ORDER BY f.facility_type, f.name;
