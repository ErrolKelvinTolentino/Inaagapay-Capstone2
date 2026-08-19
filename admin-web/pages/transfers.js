/* =====================================================
   InaAgapay Transfers — transfer workflow page
   ===================================================== */

(function () {
  "use strict";

  const SUPABASE_URL = "https://krooorixhjwygcsdoomg.supabase.co";
  const SUPABASE_ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtyb29vcml4aGp3eWdjc2Rvb21nIiwiaWF0IjoxNzg0NDYyOTQyLCJleHAiOjIxMDAwMzg5NDJ9.iVIxsgZhd_k0c-rDOjRK5J9xBiL0z-bH2l1LXH9IksU";
  const db = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON);
  window.db = db;

  const state = {
    session: readSession(),
    items: [],
    batches: [],
    facilities: [],
    transfers: [],
  };

  function readSession() {
    try {
      return JSON.parse(localStorage.getItem("inaagapay_admin_session")) || {};
    } catch (_) {
      return {};
    }
  }

  function esc(value) {
    const div = document.createElement("div");
    div.textContent = value ?? "";
    return div.innerHTML;
  }

  function localDateKey(date = new Date()) {
    const d = new Date(date);
    const offset = d.getTimezoneOffset();
    return new Date(d.getTime() - offset * 60 * 1000).toISOString().slice(0, 10);
  }

  function dateFromKey(value) {
    if (!value) return null;
    const [year, month, day] = String(value).split("-").map(Number);
    if (!year || !month || !day) return null;
    return new Date(year, month - 1, day);
  }

  function addDays(value, amount) {
    const date = dateFromKey(value) || new Date();
    date.setDate(date.getDate() + amount);
    return localDateKey(date);
  }

  function daysBetween(from, to) {
    const a = dateFromKey(from);
    const b = dateFromKey(to);
    if (!a || !b) return null;
    return Math.round((b - a) / 86400000);
  }

  function displayDate(value) {
    const date = dateFromKey(value) || (value ? new Date(value) : null);
    return date && !Number.isNaN(date.getTime())
      ? date.toLocaleDateString("en-PH", { month: "short", day: "numeric", year: "numeric" })
      : "—";
  }

  function displayDateTime(value) {
    if (!value) return "—";
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? "—" : date.toLocaleString("en-PH", { dateStyle: "medium", timeStyle: "short" });
  }

  function itemForBatch(batch) {
    return state.items.find((item) => String(item.item_id) === String(batch?.item_id));
  }

  function batchForTransfer(transfer) {
    return state.batches.find((batch) => String(batch.batch_id) === String(transfer?.source_batch_id));
  }

  function itemName(item) {
    return item?.name || item?.generic_name || "Inventory item";
  }

  function facilityName(id) {
    if (id === null || id === undefined || id === "" || id === "central" || Number(id) === 0) return "Central Storage";
    const facility = state.facilities.find((entry) => String(entry.facility_id ?? entry.bhc_id) === String(id));
    return facility?.name || facility?.bhc_name || `Health Center #${id}`;
  }

  function transferPlan(remarks) {
    const text = String(remarks || "");
    const dateMatch = text.match(/Expected delivery:\s*(\d{4}-\d{2}-\d{2})/i);
    const situationMatch = text.match(/Delivery situation:\s*([^.]+)/i);
    return {
      expectedDate: dateMatch?.[1] || "",
      situation: situationMatch?.[1]?.trim() || "on_schedule",
      note: text
        .replace(/Expected delivery:\s*\d{4}-\d{2}-\d{2}\.?\s*/i, "")
        .replace(/Delivery situation:\s*[^.]+\.?\s*/i, "")
        .trim(),
    };
  }

  function formatSituation(value) {
    return String(value || "on_schedule").replace(/_/g, " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
  }

  function showToast(message, type = "info") {
    if (typeof window.showToast === "function") {
      window.showToast(message, type);
      return;
    }
    window.alert(message);
  }

  function setError(id, message = "") {
    const element = document.getElementById(id);
    if (!element) return;
    element.textContent = message;
    element.classList.toggle("show", Boolean(message));
  }

  function openModal(id) {
    const modal = document.getElementById(id);
    if (!modal) return;
    modal.classList.add("show");
    modal.setAttribute("aria-hidden", "false");
    document.body.classList.add("modal-open");
    modal.querySelector("input:not([type=hidden]), select, textarea, button")?.focus();
  }

  function closeModal(id) {
    const modal = document.getElementById(id);
    if (!modal) return;
    modal.classList.remove("show");
    modal.setAttribute("aria-hidden", "true");
    if (!document.querySelector(".transfer-modal-overlay.show")) document.body.classList.remove("modal-open");
  }

  function setButtonLoading(button, loading, label) {
    if (!button) return;
    if (loading) {
      button.dataset.originalHtml = button.innerHTML;
      button.disabled = true;
      button.innerHTML = `<i class="fa-solid fa-spinner fa-spin"></i> ${label}`;
    } else {
      button.disabled = false;
      button.innerHTML = button.dataset.originalHtml || button.innerHTML;
    }
  }

  function statusMarkup(status) {
    if (status === "received") return '<span class="transfer-status received"><i class="fa-solid fa-circle-check"></i> Received</span>';
    if (status === "cancelled") return '<span class="transfer-status cancelled"><i class="fa-solid fa-ban"></i> Cancelled</span>';
    return '<span class="transfer-status in-transit"><i class="fa-solid fa-truck-fast"></i> In Transit</span>';
  }

  function renderStats() {
    const inTransit = state.transfers.filter((transfer) => transfer.status === "pending_receipt");
    const dueSoon = inTransit.filter((transfer) => {
      const plan = transferPlan(transfer.remarks);
      const days = daysBetween(localDateKey(), plan.expectedDate);
      return days !== null && days >= 0 && days <= 7;
    });
    const month = localDateKey().slice(0, 7);
    const receivedThisMonth = state.transfers.filter((transfer) => transfer.status === "received" && String(transfer.received_at || "").slice(0, 7) === month);
    const units = inTransit.reduce((sum, transfer) => sum + Number(transfer.quantity_issued || 0), 0);
    document.getElementById("kpi-in-transit").textContent = inTransit.length;
    document.getElementById("kpi-due-soon").textContent = dueSoon.length;
    document.getElementById("kpi-received-month").textContent = receivedThisMonth.length;
    document.getElementById("kpi-units-transit").textContent = units.toLocaleString();
  }

  function renderTransfers() {
    const tbody = document.getElementById("transfers-tbody");
    const query = document.getElementById("transfer-search").value.trim().toLowerCase();
    const status = document.getElementById("transfer-filter-status").value;
    const filtered = state.transfers.filter((transfer) => {
      if (status && transfer.status !== status) return false;
      const batch = batchForTransfer(transfer);
      const item = itemForBatch(batch);
      const plan = transferPlan(transfer.remarks);
      const searchable = [transfer.transfer_id, facilityName(transfer.destination_facility_id), itemName(item), batch?.batch_number, transfer.remarks, plan.expectedDate].join(" ").toLowerCase();
      return !query || searchable.includes(query);
    });

    if (!filtered.length) {
      tbody.innerHTML = '<tr><td colspan="8" class="transfer-empty"><i class="fa-solid fa-route"></i>No facility transfers match the current filters.</td></tr>';
      return;
    }

    tbody.innerHTML = filtered.map((transfer) => {
      const batch = batchForTransfer(transfer);
      const item = itemForBatch(batch);
      const plan = transferPlan(transfer.remarks);
      const days = daysBetween(localDateKey(), plan.expectedDate);
      const delivery = plan.expectedDate
        ? `<strong>${esc(displayDate(plan.expectedDate))}</strong><span class="transfer-cell-meta">${esc(formatSituation(plan.situation))}${days !== null ? ` · ${days < 0 ? `${Math.abs(days)} days overdue` : `${days} days away`}` : ""}</span>`
        : '<span class="transfer-cell-meta">No arrival date recorded</span>';
      const action = transfer.status === "pending_receipt"
        ? `<div class="transfer-row-actions"><button type="button" class="btn btn-secondary" data-update-transfer="${esc(transfer.transfer_id)}"><i class="fa-solid fa-calendar-days"></i> Update</button></div>`
        : '<span class="transfer-cell-meta">Closed</span>';
      return `<tr>
        <td><strong>#${esc(transfer.transfer_id)}</strong><span class="transfer-cell-meta">${esc(displayDateTime(transfer.issued_at))}</span></td>
        <td><strong>${esc(facilityName(transfer.destination_facility_id))}</strong></td>
        <td><span class="transfer-item-name">${esc(itemName(item))}</span><span class="transfer-cell-meta">Batch ${esc(batch?.batch_number || `#${transfer.source_batch_id}`)}</span></td>
        <td><strong>${Number(transfer.quantity_issued || 0).toLocaleString()}</strong><span class="transfer-cell-meta">${esc(item?.unit_of_measure || "units")}</span></td>
        <td>${esc(displayDateTime(transfer.issued_at))}</td>
        <td>${delivery}</td>
        <td>${statusMarkup(transfer.status)}</td>
        <td>${action}</td>
      </tr>`;
    }).join("");

    tbody.querySelectorAll("[data-update-transfer]").forEach((button) => {
      button.addEventListener("click", () => openTransferUpdate(Number(button.dataset.updateTransfer)));
    });
  }

  function populateSelects() {
    const itemSelect = document.getElementById("batch-item-id");
    itemSelect.innerHTML = '<option value="">— Select Item —</option>' + state.items.map((item) => `<option value="${esc(item.item_id)}">${esc(itemName(item))}</option>`).join("");

    const centralBatches = state.batches
      .filter((batch) => (batch.facility_id === null || batch.facility_id === undefined || Number(batch.facility_id) === 0 || batch.facility_id === "central") && batch.status !== "discarded" && Number(batch.quantity_remaining || 0) > 0)
      .sort((a, b) => String(a.expiration_date || "9999-12-31").localeCompare(String(b.expiration_date || "9999-12-31")));
    document.getElementById("issue-source-batch").innerHTML = '<option value="">— Select Central Batch —</option>' + centralBatches.map((batch, index) => {
      const item = itemForBatch(batch);
      const useFirst = index === 0 ? " · Use First" : "";
      return `<option value="${esc(batch.batch_id)}">${esc(itemName(item))} · ${esc(batch.batch_number)} · ${Number(batch.quantity_remaining || 0).toLocaleString()} available${useFirst}</option>`;
    }).join("");

    document.getElementById("issue-target-bhc").innerHTML = '<option value="">— Select Health Center —</option>' + state.facilities.map((facility) => `<option value="${esc(facility.facility_id ?? facility.bhc_id)}">${esc(facility.name || facility.bhc_name)}</option>`).join("");
  }

  function updateSendCheck() {
    const batch = state.batches.find((entry) => String(entry.batch_id) === String(document.getElementById("issue-source-batch").value));
    const target = document.getElementById("issue-target-bhc").value;
    const quantity = Number(document.getElementById("issue-qty").value);
    const expected = document.getElementById("issue-expected-date").value;
    const card = document.getElementById("issue-safety-check");
    const title = document.getElementById("issue-safety-title");
    const badge = document.getElementById("issue-safety-status");
    const message = document.getElementById("issue-safety-message");
    const arrival = document.getElementById("issue-expected-arrival");
    const duration = document.getElementById("issue-delivery-duration-copy");

    arrival.textContent = expected ? displayDate(expected) : "—";
    const transitDays = expected ? daysBetween(localDateKey(), expected) : null;
    duration.textContent = transitDays === null ? "Choose a date to calculate delivery duration." : `${Math.max(0, transitDays)} day(s) from issue date.`;

    card.className = "transfer-safety-card";
    badge.innerHTML = '<i class="fa-solid fa-list-check"></i> Waiting for details';
    title.textContent = "Delivery and expiry check";
    message.textContent = "Select a batch, destination, quantity, and delivery time to check whether the stock should arrive before expiry and before the health center runs out.";
    if (!batch || !target || !quantity || !expected) return;

    const shelfLife = daysBetween(expected, batch.expiration_date);
    const safeQuantity = quantity <= Number(batch.quantity_remaining || 0);
    if (!safeQuantity) {
      card.classList.add("is-critical");
      badge.innerHTML = '<i class="fa-solid fa-circle-xmark"></i> Quantity unavailable';
      title.textContent = "Not enough central stock";
      message.textContent = `This batch has only ${Number(batch.quantity_remaining || 0).toLocaleString()} units available, but the form requests ${quantity.toLocaleString()}.`;
      return;
    }
    if (shelfLife !== null && shelfLife <= 0) {
      card.classList.add("is-critical");
      badge.innerHTML = '<i class="fa-solid fa-triangle-exclamation"></i> Expiry risk';
      title.textContent = "Transfer batch expires before arrival";
      message.textContent = `The selected batch expires ${displayDate(batch.expiration_date)}. Choose an earlier arrival or another central batch.`;
      return;
    }
    if (shelfLife !== null && shelfLife <= 30) {
      card.classList.add("is-warning");
      badge.innerHTML = '<i class="fa-solid fa-triangle-exclamation"></i> Review shelf life';
      title.textContent = "Batch arrives close to expiry";
      message.textContent = `The batch is expected to arrive with about ${shelfLife} day(s) of shelf life remaining. Confirm the destination can use it promptly.`;
      return;
    }
    card.classList.add("is-safe");
    badge.innerHTML = '<i class="fa-solid fa-circle-check"></i> Expiry check passed';
    title.textContent = "Delivery plan is within shelf life";
    message.textContent = `${Math.max(0, transitDays || 0)} day(s) from issue · expected ${displayDate(expected)} · ${shelfLife ?? "—"} day(s) of shelf life at arrival.`;
  }

  function updatePlanCheck() {
    const transfer = state.transfers.find((entry) => String(entry.transfer_id) === String(document.getElementById("transfer-update-id").value));
    const expected = document.getElementById("transfer-update-date").value;
    const card = document.getElementById("transfer-update-check");
    const title = document.getElementById("transfer-update-check-title");
    const badge = document.getElementById("transfer-update-check-status");
    const message = document.getElementById("transfer-update-check-message");
    const batch = batchForTransfer(transfer);

    card.className = "transfer-safety-card";
    if (!expected || !batch) {
      title.textContent = "Choose an expected arrival date";
      badge.innerHTML = '<i class="fa-regular fa-calendar"></i> Waiting for date';
      message.textContent = "The system will compare the new arrival date with the batch expiration date.";
      return;
    }
    const shelfLife = daysBetween(expected, batch.expiration_date);
    if (shelfLife !== null && shelfLife <= 0) {
      card.classList.add("is-critical");
      title.textContent = "Batch expires before expected arrival";
      badge.innerHTML = '<i class="fa-solid fa-triangle-exclamation"></i> Expiry risk';
      message.textContent = `Expected arrival is ${displayDate(expected)}, but this batch expires ${displayDate(batch.expiration_date)}. Add a note explaining the exception.`;
      return;
    }
    if (shelfLife !== null && shelfLife <= 30) {
      card.classList.add("is-warning");
      title.textContent = "Updated plan needs review";
      badge.innerHTML = '<i class="fa-solid fa-triangle-exclamation"></i> Short shelf life';
      message.textContent = `The batch would arrive with ${shelfLife} day(s) of shelf life remaining.`;
      return;
    }
    card.classList.add("is-safe");
    title.textContent = "Updated delivery plan is within shelf life";
    badge.innerHTML = '<i class="fa-solid fa-circle-check"></i> Expiry check passed';
    message.textContent = `${daysBetween(localDateKey(), expected) ?? 0} days from issue · expected ${displayDate(expected)} · ${shelfLife ?? "—"} days of shelf life at arrival.`;
  }

  function resetReceiveForm() {
    document.getElementById("form-batch").reset();
    document.getElementById("batch-received-date").value = localDateKey();
    document.getElementById("batch-expiration-date").value = addDays(localDateKey(), 365);
    setError("batch-form-error");
    populateSelects();
  }

  function resetIssueForm() {
    document.getElementById("form-issue").reset();
    document.getElementById("issue-expected-date").value = addDays(localDateKey(), 2);
    setError("issue-form-error");
    document.getElementById("issue-safety-check").className = "transfer-safety-card";
    document.getElementById("issue-safety-status").innerHTML = '<i class="fa-solid fa-list-check"></i> Waiting for details';
    document.getElementById("issue-safety-title").textContent = "Delivery and expiry check";
    document.getElementById("issue-safety-message").textContent = "Select a batch, destination, quantity, and delivery time to check whether the stock should arrive before expiry and before the health center runs out.";
    populateSelects();
    updateSendCheck();
  }

  function openTransferUpdate(id) {
    const transfer = state.transfers.find((entry) => Number(entry.transfer_id) === Number(id));
    if (!transfer || transfer.status !== "pending_receipt") {
      showToast("Only transfers awaiting receipt can have their delivery plan updated.", "warning");
      return;
    }
    const batch = batchForTransfer(transfer);
    const item = itemForBatch(batch);
    const plan = transferPlan(transfer.remarks);
    document.getElementById("transfer-update-id").value = transfer.transfer_id;
    document.getElementById("transfer-update-date").value = plan.expectedDate || addDays(localDateKey(), 2);
    document.getElementById("transfer-update-situation").value = ["on_schedule", "delayed", "rescheduled", "transport_issue", "facility_coordination", "other"].includes(plan.situation) ? plan.situation : "other";
    document.getElementById("transfer-update-note").value = plan.note || "";
    document.getElementById("transfer-update-summary").innerHTML = `
      <div class="transfer-summary-field"><span>Transfer</span><strong>#${esc(transfer.transfer_id)}</strong></div>
      <div class="transfer-summary-field"><span>Destination</span><strong>${esc(facilityName(transfer.destination_facility_id))}</strong></div>
      <div class="transfer-summary-field"><span>Item / batch</span><strong>${esc(itemName(item))} · ${esc(batch?.batch_number || `#${transfer.source_batch_id}`)}</strong></div>
      <div class="transfer-summary-field"><span>Quantity / issued</span><strong>${Number(transfer.quantity_issued || 0).toLocaleString()} ${esc(item?.unit_of_measure || "units")} · ${esc(displayDate(transfer.issued_at))}</strong></div>`;
    setError("update-form-error");
    updatePlanCheck();
    openModal("modal-transfer-update");
  }

  async function loadFacilities() {
    const facilitiesResult = await db.from("health_facilities").select("facility_id, name").eq("facility_type", "BHC").order("name");
    if (!facilitiesResult.error && facilitiesResult.data?.length) {
      state.facilities = facilitiesResult.data;
      return;
    }
    const bhcResult = await db.from("bhc").select("bhc_id, bhc_name").order("bhc_name");
    state.facilities = bhcResult.data || [];
  }

  async function loadData() {
    const [itemsResult, batchesResult, transfersResult] = await Promise.all([
      db.from("inventory_items").select("*").order("name"),
      db.from("inventory_batches").select("*").order("expiration_date"),
      db.from("inventory_transfers").select("*").order("issued_at", { ascending: false }),
      loadFacilities(),
    ]);
    if (itemsResult.error) throw itemsResult.error;
    if (batchesResult.error) throw batchesResult.error;
    if (transfersResult.error) throw transfersResult.error;
    state.items = itemsResult.data || [];
    state.batches = batchesResult.data || [];
    state.transfers = transfersResult.data || [];
    populateSelects();
    renderStats();
    renderTransfers();
  }

  async function saveBatch() {
    const form = document.getElementById("form-batch");
    if (!form.reportValidity()) return;
    const receivedDate = document.getElementById("batch-received-date").value;
    const expirationDate = document.getElementById("batch-expiration-date").value;
    if (expirationDate < receivedDate) {
      setError("batch-form-error", "Expiration date cannot be earlier than the received date.");
      return;
    }
    const button = document.getElementById("save-batch-btn");
    setError("batch-form-error");
    setButtonLoading(button, true, "Saving…");
    try {
      const payload = {
        item_id: Number(document.getElementById("batch-item-id").value),
        facility_id: null,
        batch_number: document.getElementById("batch-number").value.trim(),
        quantity_received: Number(document.getElementById("batch-qty").value),
        quantity_remaining: Number(document.getElementById("batch-qty").value),
        received_date: receivedDate,
        expiration_date: expirationDate,
        manufacturer: document.getElementById("batch-manufacturer").value.trim() || null,
        status: "active",
      };
      const { data, error } = await db.from("inventory_batches").insert(payload).select().single();
      if (error) throw error;
      await db.from("inventory_transactions").insert({ batch_id: data.batch_id, facility_id: null, transaction_type: "receipt", quantity: payload.quantity_received, reference_type: `Stock received from ${payload.manufacturer || "stock source"}`, performed_by: state.session.account_id });
      showToast(`Batch #${payload.batch_number} recorded successfully.`, "success");
      closeModal("modal-batch");
      await loadData();
    } catch (error) {
      setError("batch-form-error", `Could not record stock received: ${error.message || error}`);
    } finally {
      setButtonLoading(button, false);
    }
  }

  async function saveIssue() {
    const form = document.getElementById("form-issue");
    if (!form.reportValidity()) return;
    const sourceBatch = state.batches.find((batch) => String(batch.batch_id) === String(document.getElementById("issue-source-batch").value));
    const quantity = Number(document.getElementById("issue-qty").value);
    if (!sourceBatch || quantity > Number(sourceBatch.quantity_remaining || 0)) {
      setError("issue-form-error", `The selected central batch has only ${Number(sourceBatch?.quantity_remaining || 0).toLocaleString()} units available.`);
      return;
    }
    const button = document.getElementById("save-issue-btn");
    setError("issue-form-error");
    setButtonLoading(button, true, "Sending…");
    try {
      const expected = document.getElementById("issue-expected-date").value;
      const remarks = [`Expected delivery: ${expected}`, document.getElementById("issue-reference").value.trim()].filter(Boolean).join(". ");
      const { data, error } = await db.rpc("issue_inventory_transfer", {
        p_source_batch_id: Number(sourceBatch.batch_id),
        p_destination_facility_id: Number(document.getElementById("issue-target-bhc").value),
        p_quantity: quantity,
        p_issued_by: state.session.account_id,
        p_request_id: null,
        p_remarks: remarks || null,
      });
      if (error) throw error;
      showToast(`Stock sent successfully; transfer #${data?.transfer_id || "created"} is awaiting receipt.`, "success");
      closeModal("modal-issue");
      await loadData();
    } catch (error) {
      setError("issue-form-error", `Could not send stock: ${error.message || error}`);
    } finally {
      setButtonLoading(button, false);
    }
  }

  async function saveTransferUpdate() {
    const transfer = state.transfers.find((entry) => String(entry.transfer_id) === String(document.getElementById("transfer-update-id").value));
    const form = document.getElementById("form-transfer-update");
    if (!transfer || !form.reportValidity()) return;
    const situation = document.getElementById("transfer-update-situation").value;
    const note = document.getElementById("transfer-update-note").value.trim();
    if (situation !== "on_schedule" && !note) {
      setError("update-form-error", "A situation note is required for a delay, reschedule, or transport issue.");
      return;
    }
    const button = document.getElementById("save-transfer-update-btn");
    setError("update-form-error");
    setButtonLoading(button, true, "Saving…");
    try {
      const plan = transferPlan(transfer.remarks);
      const oldRemarks = plan.note;
      const remarks = [`Expected delivery: ${document.getElementById("transfer-update-date").value}`, `Delivery situation: ${situation.replace(/_/g, " ")}`, note || oldRemarks].filter(Boolean).join(". ");
      const { error } = await db.from("inventory_transfers").update({ remarks }).eq("transfer_id", transfer.transfer_id).eq("status", "pending_receipt");
      if (error) throw error;
      showToast(`Delivery plan for transfer #${transfer.transfer_id} updated.`, "success");
      closeModal("modal-transfer-update");
      await loadData();
    } catch (error) {
      setError("update-form-error", `Could not update delivery plan: ${error.message || error}`);
    } finally {
      setButtonLoading(button, false);
    }
  }

  function init() {
    const name = [state.session.first_name, state.session.last_name].filter(Boolean).join(" ") || state.session.email_address || "Admin";
    document.getElementById("header-user-name").textContent = name;
    document.getElementById("header-avatar").textContent = name.split(/\s+/).map((part) => part[0]).join("").slice(0, 2).toUpperCase() || "A";
    document.getElementById("sidebar-toggle")?.addEventListener("click", () => document.querySelector(".app-sidebar")?.classList.toggle("open"));
    document.getElementById("logout-btn")?.addEventListener("click", () => {
      localStorage.removeItem("inaagapay_admin_session");
      window.location.href = "../index.html";
    });
    document.getElementById("open-batch-modal-btn").addEventListener("click", () => { resetReceiveForm(); openModal("modal-batch"); });
    document.getElementById("open-issue-modal-btn").addEventListener("click", () => { resetIssueForm(); openModal("modal-issue"); });
    document.getElementById("refresh-transfers-btn").addEventListener("click", loadData);
    document.getElementById("transfer-search").addEventListener("input", renderTransfers);
    document.getElementById("transfer-filter-status").addEventListener("change", renderTransfers);
    document.getElementById("save-batch-btn").addEventListener("click", saveBatch);
    document.getElementById("save-issue-btn").addEventListener("click", saveIssue);
    document.getElementById("save-transfer-update-btn").addEventListener("click", saveTransferUpdate);
    ["issue-source-batch", "issue-target-bhc", "issue-qty", "issue-expected-date"].forEach((id) => document.getElementById(id).addEventListener("input", updateSendCheck));
    ["issue-source-batch", "issue-target-bhc", "issue-qty", "issue-expected-date"].forEach((id) => document.getElementById(id).addEventListener("change", updateSendCheck));
    ["transfer-update-date", "transfer-update-situation"].forEach((id) => document.getElementById(id).addEventListener("input", updatePlanCheck));
    ["transfer-update-date", "transfer-update-situation"].forEach((id) => document.getElementById(id).addEventListener("change", updatePlanCheck));
    document.querySelectorAll("[data-close-modal]").forEach((button) => button.addEventListener("click", () => closeModal(button.dataset.closeModal)));
    document.querySelectorAll(".transfer-modal-overlay").forEach((modal) => modal.addEventListener("click", (event) => { if (event.target === modal) closeModal(modal.id); }));
    document.addEventListener("keydown", (event) => { if (event.key === "Escape") document.querySelectorAll(".transfer-modal-overlay.show").forEach((modal) => closeModal(modal.id)); });
    loadData().catch((error) => {
      document.getElementById("transfers-tbody").innerHTML = `<tr><td colspan="8" class="transfer-empty"><i class="fa-solid fa-triangle-exclamation"></i> Could not load transfer data. ${esc(error.message || error)}</td></tr>`;
      showToast("Could not load transfer data. Please refresh and try again.", "error");
    });
    window.AdminLiveRefresh?.start({
      db,
      canRefresh: () => !document.querySelector(".transfer-modal-overlay.show"),
      tables: ["inventory_items", "inventory_batches", "inventory_transfers", "health_facilities", "bhc"],
      refresh: loadData,
    });
  }

  init();
})();
