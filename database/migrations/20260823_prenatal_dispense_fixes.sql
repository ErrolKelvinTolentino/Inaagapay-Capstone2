  -- ==============================================================================
  -- MIGRATION: 20260823_prenatal_dispense_fixes.sql
  --
  -- Repairs deduct_prenatal_encounter_inventory, the RPC the midwife app calls
  -- when a prenatal checkup dispenses supplements or gives a maternal Td dose.
  --
  --  (1) A SUPPLEMENT DISPENSE ONLY EVER DREW FROM ONE BATCH
  --      The loop picked the earliest-expiring batch that could cover the whole
  --      request. If none could, it fell back to draining a single batch and
  --      reported "Partial dispense (20 of 30 available)" — while a second batch
  --      on the same shelf still held fifty. given_medications.quantity kept
  --      saying 30, so the record said thirty tablets were handed over and stock
  --      only ever lost twenty. It now walks the batches in FEFO order until the
  --      request is met or the shelf is genuinely empty.
  --
  --  (2) AN EXPIRED OPEN Td VIAL ABORTED THE WHOLE DEDUCTION
  --      The write-off used transaction_type 'unusable', which
  --      inventory_transactions_transaction_type_check has never allowed —
  --      20260821 settled the list at receipt / dispense / adjustment /
  --      expiry_disposal / discard / transfer. So the one case the branch existed
  --      to handle, a vial past its 28-day limit, raised 23514 and rolled back
  --      the supplements with it. It now writes 'expiry_disposal', the same type
  --      the child-immunisation path uses for exactly this.
  --
  --  (3) performed_by RECEIVED WHATEVER THE CALLER HELD
  --      p_performed_by went straight into a column that REFERENCES
  --      accounts(account_id). The Flutter caller passes `_accountId ?? _midwifeId`,
  --      so on any account where the first is null a midwife_id hit the FK and the
  --      whole deduction raised. 20260821 fixed this for the other RPCs with
  --      resolve_actor_account_id; this one was left behind.
  --
  -- Also sets dose_quantity explicitly on every row it writes, since a Td dose
  -- drawn from an already-open vial moves 0 units and would otherwise be derived
  -- as 0 doses.
  --
  -- Requires 20260821_inventory_and_td_fixes.sql (resolve_actor_account_id) and
  -- 20260822_dose_accounting.sql (dose_quantity).
  --
  -- Safe to run more than once.
  -- ==============================================================================

  CREATE OR REPLACE FUNCTION public.deduct_prenatal_encounter_inventory(
    p_encounter_id BIGINT,
    p_facility_id  BIGINT DEFAULT NULL,
    p_performed_by BIGINT DEFAULT NULL,
    p_deduct_td    BOOLEAN DEFAULT TRUE
  )
  RETURNS JSONB
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
  AS $fn$
  DECLARE
    v_enc          RECORD;
    v_pc           RECORD;
    v_med          RECORD;
    v_batch        RECORD;
    v_facility_id  BIGINT;
    v_item_id      BIGINT;
    v_qty_needed   INTEGER;
    v_outstanding  INTEGER;
    v_take         INTEGER;
    v_batches_used INTEGER;
    v_td_item_id   BIGINT;
    v_td_dpu       INTEGER := 10;
    v_shelf_hours  INTEGER := 672;   -- 28 days, DOH standard for an opened Td vial
    v_hours_open   NUMERIC;
    v_doses_left   INTEGER;
    v_actor        BIGINT;
    v_results      JSONB := '[]'::jsonb;
    v_warnings     JSONB := '[]'::jsonb;
  BEGIN
    v_actor := public.resolve_actor_account_id(p_performed_by);

    -- 1. Encounter and mother context
    SELECT ce.*, m.assigned_bhc_id
      INTO v_enc
      FROM public.clinical_encounters ce
      JOIN public.mothers m ON m.mother_id = ce.mother_id
    WHERE ce.encounter_id = p_encounter_id;

    IF NOT FOUND THEN
      SELECT pc.*, m.assigned_bhc_id
        INTO v_pc
        FROM public.prenatal_checkups pc
        JOIN public.mothers m ON m.mother_id = pc.mother_id
      WHERE pc.encounter_id = p_encounter_id;

      IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false,
          'error', 'Prenatal encounter #' || p_encounter_id || ' not found');
      END IF;
      v_facility_id := COALESCE(p_facility_id, v_pc.assigned_bhc_id, 1);
    ELSE
      SELECT * INTO v_pc
        FROM public.prenatal_checkups
      WHERE encounter_id = p_encounter_id;
      v_facility_id := COALESCE(p_facility_id, v_enc.assigned_bhc_id, 1);
    END IF;

    -- 2. Supplements, FEFO across as many batches as the request needs
    FOR v_med IN
      SELECT gm.*
        FROM public.given_medications gm
      WHERE gm.encounter_id = p_encounter_id
          OR (v_enc.mother_id IS NOT NULL AND gm.mother_id = v_enc.mother_id
              AND gm.date_given = COALESCE(v_enc.encounter_date::date, CURRENT_DATE))
          OR (v_pc.mother_id IS NOT NULL AND gm.mother_id = v_pc.mother_id
              AND gm.date_given = CURRENT_DATE)
    LOOP
      v_qty_needed := COALESCE(v_med.quantity, 0);
      CONTINUE WHEN v_qty_needed <= 0;

      SELECT item_id INTO v_item_id
        FROM public.inventory_items
      WHERE is_archived = false
        AND (
          (v_med.given_medication_name ILIKE '%ferrous%' AND (name ILIKE '%ferrous%' OR generic_name ILIKE '%iron%'))
          OR (v_med.given_medication_name ILIKE '%calcium%' AND (name ILIKE '%calcium%' OR generic_name ILIKE '%calcium%'))
          OR (name ILIKE '%' || v_med.given_medication_name || '%')
          OR (generic_name ILIKE '%' || v_med.given_medication_name || '%')
        )
      ORDER BY CASE
                  WHEN name ILIKE '%' || v_med.given_medication_name || '%' THEN 1
                  WHEN generic_name ILIKE '%' || v_med.given_medication_name || '%' THEN 2
                  ELSE 3
                END
      LIMIT 1;

      IF v_item_id IS NULL THEN
        v_warnings := v_warnings || to_jsonb(
          (v_med.given_medication_name || ' is not in the inventory catalogue, so nothing was deducted')::text);
        CONTINUE;
      END IF;

      v_outstanding  := v_qty_needed;
      v_batches_used := 0;

      FOR v_batch IN
        SELECT *
          FROM public.inventory_batches
        WHERE item_id     = v_item_id
          AND facility_id = v_facility_id
          AND status      = 'active'
          AND quantity_remaining > 0
          AND expiration_date >= CURRENT_DATE
        ORDER BY expiration_date ASC, batch_id ASC
          FOR UPDATE
      LOOP
        EXIT WHEN v_outstanding <= 0;

        v_take := LEAST(v_batch.quantity_remaining, v_outstanding);

        UPDATE public.inventory_batches
          SET quantity_remaining = quantity_remaining - v_take,
              status = CASE WHEN (quantity_remaining - v_take) <= 0
                            THEN 'depleted' ELSE status END
        WHERE batch_id = v_batch.batch_id;

        -- The medication row points at the first batch it drew from; a dispense
        -- spanning several batches is reconstructed from the ledger.
        IF v_batches_used = 0 THEN
          UPDATE public.given_medications
            SET inventory_batch_id = v_batch.batch_id,
                facility_id        = v_facility_id
          WHERE given_medication_id = v_med.given_medication_id;
        END IF;

        INSERT INTO public.inventory_transactions (
          batch_id, facility_id, transaction_type, quantity, dose_quantity,
          reference_type, reference_id, notes, performed_by,
          resulting_quantity_remaining, logged_at
        ) VALUES (
          v_batch.batch_id, v_facility_id, 'dispense', -v_take, -v_take,
          'Prenatal Encounter', p_encounter_id,
          'Dispensed ' || v_take || ' of ' || v_qty_needed || ' '
            || v_med.given_medication_name || ' (Batch #' || v_batch.batch_number
            || ') for Prenatal Encounter #' || p_encounter_id,
          v_actor, v_batch.quantity_remaining - v_take, NOW()
        );

        v_outstanding  := v_outstanding - v_take;
        v_batches_used := v_batches_used + 1;
      END LOOP;

      IF v_outstanding = v_qty_needed THEN
        v_warnings := v_warnings || to_jsonb(
          ('No ' || v_med.given_medication_name || ' in stock at this health center ('
            || v_qty_needed || ' requested)')::text);
      ELSE
        v_results := v_results || jsonb_build_object(
          'item_type',   'supplement',
          'medication',  v_med.given_medication_name,
          'quantity',    v_qty_needed - v_outstanding,
          'requested',   v_qty_needed,
          'batches_used', v_batches_used,
          'note', CASE WHEN v_outstanding > 0
                      THEN 'Only ' || (v_qty_needed - v_outstanding) || ' of '
                            || v_qty_needed || ' were in stock'
                      ELSE NULL END
        );

        IF v_outstanding > 0 THEN
          v_warnings := v_warnings || to_jsonb(
            (v_med.given_medication_name || ': ' || v_outstanding
              || ' of ' || v_qty_needed || ' could not be deducted — stock ran out')::text);
        END IF;
      END IF;
    END LOOP;

    -- 3. Maternal Td, open vial before sealed
    IF p_deduct_td
      AND v_pc.td_vaccine_dose IS NOT NULL
      AND v_pc.td_vaccine_dose NOT IN ('', '-', 'none')
    THEN
      SELECT item_id, COALESCE(doses_per_unit, 10), COALESCE(open_vial_shelf_hours, 672)
        INTO v_td_item_id, v_td_dpu, v_shelf_hours
        FROM public.inventory_items
      WHERE (name ILIKE '%td%' OR name ILIKE '%tetanus%' OR generic_name ILIKE '%tetanus%')
        AND is_archived = false
      ORDER BY CASE WHEN name ILIKE 'td%' THEN 1 ELSE 2 END
      LIMIT 1;

      IF v_td_item_id IS NOT NULL THEN
        DECLARE
          v_td_found BOOLEAN := false;
        BEGIN
          -- 3A. An already-open vial, earliest expiry first.
          FOR v_batch IN
            SELECT *
              FROM public.inventory_batches
            WHERE item_id     = v_td_item_id
              AND facility_id = v_facility_id
              AND status      = 'active'
              AND expiration_date >= CURRENT_DATE
              AND COALESCE(doses_remaining_in_open_vial, 0) > 0
            ORDER BY expiration_date ASC, batch_id ASC
              FOR UPDATE
          LOOP
            IF v_batch.vial_opened_at IS NOT NULL AND v_shelf_hours > 0 THEN
              v_hours_open := EXTRACT(EPOCH FROM (NOW() - v_batch.vial_opened_at)) / 3600;

              IF v_hours_open > v_shelf_hours THEN
                UPDATE public.inventory_batches
                  SET doses_remaining_in_open_vial = 0,
                      open_vials_count = GREATEST(0, COALESCE(open_vials_count, 1) - 1),
                      vial_opened_at   = NULL,
                      status = CASE WHEN quantity_remaining <= 0 THEN 'depleted' ELSE status END
                WHERE batch_id = v_batch.batch_id;

                -- 'unusable' was never an accepted transaction_type, so this
                -- write-off used to abort the entire call.
                INSERT INTO public.inventory_transactions (
                  batch_id, facility_id, transaction_type, quantity, dose_quantity,
                  reference_type, reference_id, notes, performed_by, logged_at
                ) VALUES (
                  v_batch.batch_id, v_facility_id, 'expiry_disposal', 0,
                  -v_batch.doses_remaining_in_open_vial,
                  'Open Vial Expiry', v_batch.batch_id,
                  'Auto-discarded ' || v_batch.doses_remaining_in_open_vial
                    || ' dose(s) left in an open Td vial (Batch #' || v_batch.batch_number
                    || ') past the ' || v_shelf_hours || 'h limit',
                  v_actor, NOW()
                );

                CONTINUE;
              END IF;
            END IF;

            v_doses_left := v_batch.doses_remaining_in_open_vial - 1;

            UPDATE public.inventory_batches
              SET doses_remaining_in_open_vial = v_doses_left,
                  open_vials_count = CASE WHEN v_doses_left <= 0
                                          THEN GREATEST(0, COALESCE(open_vials_count, 1) - 1)
                                          ELSE COALESCE(open_vials_count, 1) END,
                  vial_opened_at   = CASE WHEN v_doses_left <= 0 THEN NULL
                                          ELSE COALESCE(v_batch.vial_opened_at, NOW()) END,
                  status = CASE WHEN v_doses_left <= 0 AND quantity_remaining <= 0
                                THEN 'depleted' ELSE status END
            WHERE batch_id = v_batch.batch_id;

            INSERT INTO public.inventory_transactions (
              batch_id, facility_id, transaction_type, quantity, dose_quantity,
              reference_type, reference_id, notes, performed_by,
              resulting_quantity_remaining, logged_at
            ) VALUES (
              v_batch.batch_id, v_facility_id, 'dispense', 0, -1,
              'Maternal Td Immunization', p_encounter_id,
              '1 dose of ' || v_pc.td_vaccine_dose || ' from an open vial (Batch #'
                || v_batch.batch_number || ', ' || v_doses_left || ' dose(s) left)',
              v_actor, v_batch.quantity_remaining, NOW()
            );

            v_results := v_results || jsonb_build_object(
              'item_type',               'vaccine',
              'vaccine',                 'Td Vaccine',
              'dose',                    v_pc.td_vaccine_dose,
              'mode',                    'open_vial_dose',
              'batch_number',            v_batch.batch_number,
              'doses_remaining_in_vial', v_doses_left
            );

            v_td_found := true;
            EXIT;
          END LOOP;

          -- 3B. Nothing open and usable: break a fresh seal, FEFO.
          IF NOT v_td_found THEN
            SELECT * INTO v_batch
              FROM public.inventory_batches
            WHERE item_id     = v_td_item_id
              AND facility_id = v_facility_id
              AND status      = 'active'
              AND expiration_date >= CURRENT_DATE
              AND quantity_remaining > 0
            ORDER BY expiration_date ASC, batch_id ASC
            LIMIT 1
              FOR UPDATE;

            IF FOUND THEN
              v_doses_left := v_td_dpu - 1;

              UPDATE public.inventory_batches
                SET quantity_remaining           = quantity_remaining - 1,
                    open_vials_count             = COALESCE(open_vials_count, 0) + 1,
                    doses_remaining_in_open_vial = COALESCE(doses_remaining_in_open_vial, 0) + v_doses_left,
                    vial_opened_at               = NOW(),
                    status = CASE WHEN (quantity_remaining - 1) <= 0 AND v_doses_left <= 0
                                  THEN 'depleted' ELSE status END
              WHERE batch_id = v_batch.batch_id;

              INSERT INTO public.inventory_transactions (
                batch_id, facility_id, transaction_type, quantity, dose_quantity,
                reference_type, reference_id, notes, performed_by,
                resulting_quantity_remaining, logged_at
              ) VALUES (
                v_batch.batch_id, v_facility_id, 'dispense', -1, -1,
                'Maternal Td Immunization', p_encounter_id,
                'Opened a ' || v_td_dpu || '-dose Td vial (Batch #' || v_batch.batch_number
                  || ') for ' || v_pc.td_vaccine_dose || '; 1 dose given, '
                  || v_doses_left || ' left open',
                v_actor, v_batch.quantity_remaining - 1, NOW()
              );

              v_results := v_results || jsonb_build_object(
                'item_type',               'vaccine',
                'vaccine',                 'Td Vaccine',
                'dose',                    v_pc.td_vaccine_dose,
                'mode',                    'new_vial_opened',
                'batch_number',            v_batch.batch_number,
                'sealed_vials_left',       v_batch.quantity_remaining - 1,
                'doses_remaining_in_vial', v_doses_left
              );
            ELSE
              v_warnings := v_warnings || to_jsonb(
                ('No Td vaccine in stock at this health center for '
                  || v_pc.td_vaccine_dose)::text);
            END IF;
          END IF;
        END;
      ELSE
        v_warnings := v_warnings || to_jsonb(
          'No Td vaccine item is configured in the inventory catalogue'::text);
      END IF;
    END IF;

    RETURN jsonb_build_object(
      'success',    true,
      'deductions', v_results,
      'warnings',   v_warnings
    );
  END
  $fn$;

  GRANT EXECUTE ON FUNCTION public.deduct_prenatal_encounter_inventory(BIGINT, BIGINT, BIGINT, BOOLEAN)
    TO anon, authenticated, service_role;

  COMMENT ON FUNCTION public.deduct_prenatal_encounter_inventory(BIGINT, BIGINT, BIGINT, BOOLEAN) IS
    'Deducts a prenatal visit''s supplements (FEFO across batches) and maternal Td '
    'dose (open vial before sealed) from the facility''s stock.';
