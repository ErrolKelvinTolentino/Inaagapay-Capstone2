/* ==========================================================================
   export-kit.js — PDF and Excel exports shared by every portal page.

   A page describes WHAT goes in a report — a heading, some sentences, a table,
   a chart — and this file decides how it looks, so every PDF the portal hands
   to the Municipal Health Office has the same title block, the same table
   style, page numbers and a signature line, and every workbook opens in Excel
   as a real .xlsx rather than an HTML page renamed to .xls (which Excel opens
   with a "format and extension don't match" warning).

   Libraries load on first use, from the CDNs the site's CSP already allows,
   so pages that never export never pay for them.

     const report = await ExportKit.pdf({ title, scope, period, landscape });
     report.heading("Vaccination drives");
     report.paragraph("12 drives, 340 doses.");
     report.table(ExportKit.tableData(document.querySelector("#my-table")));
     report.chart(canvasEl, "Turnout by drive");
     report.save("vaccination-drives.pdf");

     await ExportKit.xlsx("vaccination-drives.xlsx", [
       { name: "Drives", title, scope, period, blocks: [{ title, columns, rows }] },
     ]);
   ========================================================================== */
(function () {
  "use strict";

  const CDN = {
    jspdf: "https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js",
    autotable: "https://cdnjs.cloudflare.com/ajax/libs/jspdf-autotable/3.6.0/jspdf.plugin.autotable.min.js",
    xlsx: "https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js",
  };

  const BRAND = [199, 53, 120];
  const BRAND_SOFT = [252, 231, 241];
  const INK = [31, 31, 31];
  const MUTED = [107, 107, 107];
  const RULE = [221, 221, 221];
  const ZEBRA = [247, 247, 247];

  const pending = {};
  function loadScript(src) {
    if (pending[src]) return pending[src];
    pending[src] = new Promise((resolve, reject) => {
      const existing = document.querySelector(`script[src="${src}"]`);
      if (existing && existing.dataset.loaded === "true") return resolve();
      const s = existing || document.createElement("script");
      s.src = src;
      s.addEventListener("load", () => { s.dataset.loaded = "true"; resolve(); });
      s.addEventListener("error", () => {
        delete pending[src];
        reject(new Error("Could not load the export library. Check the connection and try again."));
      });
      if (!existing) document.head.appendChild(s);
    });
    return pending[src];
  }

  async function ensurePdf() {
    if (!window.jspdf) await loadScript(CDN.jspdf);
    if (!window.jspdf.jsPDF.API.autoTable) await loadScript(CDN.autotable);
    return window.jspdf.jsPDF;
  }

  async function ensureXlsx() {
    if (!window.XLSX) await loadScript(CDN.xlsx);
    return window.XLSX;
  }

  function preparedBy() {
    try {
      const s = JSON.parse(localStorage.getItem("inaagapay_admin_session") || "{}");
      const name = [s.first_name, s.last_name].filter(Boolean).join(" ").trim();
      return name || "Administrator";
    } catch (e) {
      return "Administrator";
    }
  }

  function scopeLabel() {
    const ps = window.PortalScope;
    if (ps && ps.isMho) return "Municipal Health Office (all health centers)";
    return (ps && ps.facilityName) || "Health facility";
  }

  function stamp(date) {
    const d = date || new Date();
    return d.toLocaleString("en-PH", {
      year: "numeric", month: "short", day: "numeric",
      hour: "numeric", minute: "2-digit",
    });
  }

  function today() {
    const d = new Date();
    const pad = (n) => String(n).padStart(2, "0");
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  }

  function slug(text) {
    return String(text || "report").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  }

  /** "vaccination-drives_2026-09-24.pdf" */
  function fileName(title, ext) {
    return `${slug(title)}_${today()}.${ext}`;
  }

  // ------------------------------------------------------------------------
  // Reading a rendered table
  // ------------------------------------------------------------------------

  /**
   * The visible contents of a <table>: header labels and one array of cell
   * text per visible body row. Placeholder rows ("No records", a spinner) —
   * a single cell spanning the table — are left out, so an empty table exports
   * as empty rather than as a row saying "Loading…".
   */
  function tableData(table, opts) {
    const options = opts || {};
    if (!table) return { columns: [], rows: [] };
    const skip = new Set(options.skipColumns || []);
    const clean = (el) => (el.innerText || el.textContent || "").replace(/\s+/g, " ").trim();

    const headRow = table.querySelector("thead tr:last-child") || table.querySelector("tr");
    const columns = [];
    const keep = [];
    if (headRow) {
      Array.from(headRow.children).forEach((th, i) => {
        if (skip.has(i) || getComputedStyle(th).display === "none") return;
        keep.push(i);
        columns.push(clean(th));
      });
    }

    const rows = [];
    table.querySelectorAll("tbody tr").forEach((tr) => {
      if (getComputedStyle(tr).display === "none") return;
      const cells = Array.from(tr.children);
      if (cells.length === 1 && Number(cells[0].getAttribute("colspan") || 1) > 1) return;
      rows.push(keep.map((i) => (cells[i] ? clean(cells[i]) : "")));
    });
    return { columns, rows };
  }

  // ------------------------------------------------------------------------
  // PDF
  // ------------------------------------------------------------------------

  // jsPDF's built-in fonts cover Latin-1: "Peñaflor" prints, but an en dash,
  // a curly quote or an arrow prints as a stray symbol. Swap those for their
  // plain equivalents rather than embed a 300 KB font in every report.
  function pdfSafe(value) {
    return String(value === null || value === undefined ? "" : value)
      .replace(/[\u2010-\u2015\u2212]/g, "-")
      .replace(/[\u2018\u2019\u201A\u2032]/g, "'")
      .replace(/[\u201C\u201D\u201E\u2033]/g, '"')
      .replace(/\u2026/g, "...")
      .replace(/[\u2192\u27A1]/g, "->")
      .replace(/\u2190/g, "<-")
      .replace(/[\u2022\u25CF]/g, "-")
      .replace(/[\u00A0\u2009\u202F]/g, " ")
      .replace(/[^\u0000-\u00FF]/g, "");
  }

  class PdfReport {
    constructor(JsPDF, opts) {
      this.opts = Object.assign({ scope: scopeLabel(), period: "", preparedBy: preparedBy() }, opts);
      ["title", "scope", "period", "preparedBy"].forEach((k) => { this.opts[k] = pdfSafe(this.opts[k]); });
      this.doc = new JsPDF({ orientation: this.opts.landscape ? "l" : "p", unit: "mm", format: "a4", compress: true });
      this.margin = 14;
      this.width = this.doc.internal.pageSize.getWidth();
      this.height = this.doc.internal.pageSize.getHeight();
      this.content = this.width - this.margin * 2;
      this.generated = new Date();
      this._titleBlock();
    }

    _titleBlock() {
      const d = this.doc, m = this.margin;
      d.setFont("helvetica", "bold");
      d.setFontSize(7);
      d.setTextColor(...MUTED);
      d.text("INAAGAPAY MATERNAL AND CHILD HEALTH INFORMATION SYSTEM", m, 14);
      d.setFontSize(16);
      d.setTextColor(...INK);
      const titleLines = d.splitTextToSize(this.opts.title, this.content);
      d.text(titleLines, m, 22, { lineHeightFactor: 1.2 });
      let y = 22 + titleLines.length * 6.8;
      d.setFontSize(9.5);
      d.setTextColor(...BRAND);
      const scopeLines = d.splitTextToSize(this.opts.scope, this.content);
      d.text(scopeLines, m, y, { lineHeightFactor: 1.2 });
      y += scopeLines.length * 4.5 + 3;
      // Metadata occupies its own rows; long facility names and preparation
      // names can no longer collide in the same header column.
      d.setFont("helvetica", "normal");
      d.setFontSize(7.5);
      d.setTextColor(...MUTED);
      for (const [label, value] of [["Period", this.opts.period || "All records"],
        ["Prepared by", this.opts.preparedBy], ["Generated", stamp(this.generated)]]) {
        const lines = d.splitTextToSize(`${label}: ${value}`, this.content);
        d.text(lines, m, y, { lineHeightFactor: 1.2 });
        y += lines.length * 3.5;
      }
      this.y = y + 3;
      d.setDrawColor(...BRAND);
      d.setLineWidth(0.5);
      d.line(m, this.y, this.width - m, this.y);
      this.y += 6;
    }

    /** Start a new page when fewer than [needed] mm remain. */
    ensureSpace(needed) {
      if (this.y + needed > this.height - 16) {
        this.doc.addPage();
        this.y = 20;
      }
    }

    heading(text) {
      const d = this.doc;
      d.setFont("helvetica", "bold");
      d.setFontSize(10.5);
      const lines = d.splitTextToSize(pdfSafe(text), this.content - 7);
      const h = Math.max(7.5, lines.length * 4.5 + 3);
      this.ensureSpace(h + 8);
      d.setFillColor(...BRAND_SOFT);
      d.rect(this.margin, this.y, this.content, h, "F");
      d.setFillColor(...BRAND);
      d.rect(this.margin, this.y, 1.2, h, "F");
      d.setTextColor(...INK);
      d.text(lines, this.margin + 3.5, this.y + 5.1, { lineHeightFactor: 1.2 });
      this.y += h + 3.5;
    }

    paragraph(text, style) {
      if (!text) return;
      const s = Object.assign({ size: 9, color: INK, italic: false, bold: false }, style);
      const d = this.doc;
      d.setFont("helvetica", s.bold ? "bold" : (s.italic ? "italic" : "normal"));
      d.setFontSize(s.size);
      d.setTextColor(...s.color);
      const lines = d.splitTextToSize(pdfSafe(text), this.content);
      const lineHeight = s.size * 0.45;
      lines.forEach((line) => {
        this.ensureSpace(lineHeight + 1);
        d.text(line, this.margin, this.y + lineHeight * 0.8);
        this.y += lineHeight;
      });
      this.y += 2;
    }

    bullets(items) {
      (items || []).forEach((item) => this.paragraph(`-  ${item}`));
    }

    note(text) {
      this.paragraph(text, { size: 7.5, color: MUTED, italic: true });
    }

    /** A row of labelled figures, like the KPI tiles on screen. */
    figures(pairs) {
      if (!pairs || !pairs.length) return;
      const d = this.doc;
      const perRow = Math.min(pairs.length, this.opts.landscape ? 6 : 4);
      const gap = 3;
      const w = (this.content - gap * (perRow - 1)) / perRow;
      for (let i = 0; i < pairs.length; i += perRow) {
        const row = pairs.slice(i, i + perRow).map(([label, value]) => {
          d.setFont("helvetica", "bold");
          d.setFontSize(12);
          const values = d.splitTextToSize(pdfSafe(value), w - 6);
          d.setFontSize(6.5);
          const labels = d.splitTextToSize(pdfSafe(label).toUpperCase(), w - 6);
          return { values, labels };
        });
        const h = Math.max(...row.map(r => 6 + r.values.length * 5 + r.labels.length * 3));
        this.ensureSpace(h + 3);
        row.forEach((r, j) => {
          const x = this.margin + j * (w + gap);
          d.setDrawColor(...RULE); d.setFillColor(250, 250, 250);
          d.roundedRect(x, this.y, w, h, 1.5, 1.5, "FD");
          d.setFont("helvetica", "bold"); d.setFontSize(12); d.setTextColor(...BRAND);
          d.text(r.values, x + w / 2, this.y + 6, { align: "center", lineHeightFactor: 1.15 });
          d.setFontSize(6.5); d.setTextColor(...MUTED);
          d.text(r.labels, x + w / 2, this.y + 6 + r.values.length * 5,
            { align: "center", lineHeightFactor: 1.2 });
        });
        this.y += h + 3;
      }
    }

    table(data, opts) {
      const o = opts || {};
      if (!data || !data.rows || !data.rows.length) {
        this.note(o.emptyText || "No records for the current filters.");
        return;
      }
      this.doc.autoTable({
        startY: this.y,
        head: [data.columns.map(pdfSafe)],
        body: data.rows.map((r) => r.map(pdfSafe)),
        theme: "grid",
        margin: { left: this.margin, right: this.margin, top: 20, bottom: 18 },
        styles: { font: "helvetica", fontSize: o.fontSize || 7.5, cellPadding: 1.6, textColor: INK, lineColor: RULE, lineWidth: 0.1, overflow: "linebreak" },
        headStyles: { fillColor: BRAND, textColor: 255, fontStyle: "bold" },
        alternateRowStyles: { fillColor: ZEBRA },
        columnStyles: o.columnStyles || {},
        rowPageBreak: "avoid",
      });
      this.y = this.doc.lastAutoTable.finalY + 3;
      this.note(`${data.rows.length} ${data.rows.length === 1 ? "row" : "rows"}`);
      this.y += 2;
    }

    /** A Chart.js canvas as an image, keeping its proportions. */
    chart(canvas, title, widthMm) {
      if (!canvas || !canvas.width || !canvas.height) return;
      const w = Math.min(widthMm || this.content, this.content);
      const h = w * (canvas.height / canvas.width);
      this.ensureSpace(h + 8);
      if (title) this.paragraph(title, { bold: true, size: 8.5 });
      const img = this._canvasImage(canvas);
      this.doc.addImage(img, "JPEG", this.margin, this.y, w, h);
      this.y += h + 4;
    }

    /** Several charts side by side, [perRow] to a row. */
    charts(items, perRow) {
      const list = (items || []).filter((it) => it.canvas && it.canvas.width);
      const n = perRow || 2;
      const gap = 6;
      const w = (this.content - gap * (n - 1)) / n;
      for (let i = 0; i < list.length; i += n) {
        const d = this.doc;
        d.setFont("helvetica", "bold"); d.setFontSize(8);
        const row = list.slice(i, i + n).map(it => ({ ...it, lines: d.splitTextToSize(pdfSafe(it.title), w) }));
        const titleHeight = Math.max(...row.map(it => it.lines.length * 3.8)) + 2;
        const maxImageHeight = this.height - 42 - titleHeight;
        const h = Math.min(maxImageHeight, Math.max(...row.map(it => w * it.canvas.height / it.canvas.width)));
        this.ensureSpace(h + titleHeight + 5);
        row.forEach((it, j) => {
          const x = this.margin + j * (w + gap);
          d.setTextColor(...INK);
          d.text(it.lines, x, this.y + 3, { lineHeightFactor: 1.2 });
          const ih = Math.min(h, w * it.canvas.height / it.canvas.width);
          const iw = ih * it.canvas.width / it.canvas.height;
          d.addImage(this._canvasImage(it.canvas), "JPEG", x, this.y + titleHeight, iw, ih);
        });
        this.y += h + titleHeight + 5;
      }
    }

    // Charts draw on a transparent canvas; flatten onto white so the PDF does
    // not show them on black in some viewers. JPEG, because a PNG of a
    // high-DPI chart is several hundred kilobytes and a report carries six.
    _canvasImage(canvas) {
      const c = document.createElement("canvas");
      c.width = canvas.width;
      c.height = canvas.height;
      const ctx = c.getContext("2d");
      ctx.fillStyle = "#ffffff";
      ctx.fillRect(0, 0, c.width, c.height);
      ctx.drawImage(canvas, 0, 0);
      return c.toDataURL("image/jpeg", 0.9);
    }

    signatures(notedBy) {
      const d = this.doc;
      this.ensureSpace(30);
      this.y += 6;
      const w = (this.content - 12) / 2;
      [
        ["Prepared and certified correct by:", this.opts.preparedBy, this.opts.scope],
        ["Noted by:", "", notedBy || "Municipal Health Officer"],
      ].forEach(([caption, name, role], i) => {
        const x = this.margin + i * (w + 12);
        d.setFont("helvetica", "normal");
        d.setFontSize(8);
        d.setTextColor(...MUTED);
        d.text(caption, x, this.y);
        d.setDrawColor(...INK);
        d.setLineWidth(0.25);
        d.line(x, this.y + 13, x + Math.min(w, 80), this.y + 13);
        d.setFont("helvetica", "bold");
        d.setFontSize(9);
        d.setTextColor(...INK);
        if (name) d.text(name, x, this.y + 12);
        d.setFont("helvetica", "normal");
        d.setFontSize(7.5);
        d.setTextColor(...MUTED);
        d.text(d.splitTextToSize(role, w), x, this.y + 17);
      });
      this.y += 24;
    }

    _footers() {
      const d = this.doc;
      const total = d.getNumberOfPages();
      for (let p = 1; p <= total; p++) {
        d.setPage(p);
        d.setFont("helvetica", "normal");
        d.setFontSize(7);
        d.setTextColor(...MUTED);
        d.text("Confidential patient information. Handle under the Data Privacy Act of 2012 (RA 10173).",
          this.margin, this.height - 8);
        d.text(`Page ${p} of ${total}`, this.width - this.margin, this.height - 8, { align: "right" });
        if (p > 1) {
          d.setFont("helvetica", "bold");
          d.setTextColor(...INK);
          const title = d.splitTextToSize(this.opts.title, this.content * 0.48)[0] || "";
          d.text(title, this.margin, 11);
          d.setFont("helvetica", "normal");
          d.setTextColor(...MUTED);
          const scope = d.splitTextToSize(`${this.opts.scope}${this.opts.period ? "  |  " + this.opts.period : ""}`, this.content * 0.48)[0] || "";
          d.text(scope,
            this.width - this.margin, 11, { align: "right" });
          d.setDrawColor(...RULE);
          d.setLineWidth(0.2);
          d.line(this.margin, 13, this.width - this.margin, 13);
        }
      }
    }

    save(name) {
      this._footers();
      this.doc.save(name || fileName(this.opts.title, "pdf"));
    }
  }

  async function pdf(opts) {
    const JsPDF = await ensurePdf();
    return new PdfReport(JsPDF, opts);
  }

  // ------------------------------------------------------------------------
  // XLSX
  // ------------------------------------------------------------------------

  const NUMBER = /^-?\d{1,15}(\.\d+)?$/;
  function asCell(value) {
    if (value === null || value === undefined) return "";
    if (typeof value === "number") return value;
    const s = String(value).trim();
    return NUMBER.test(s.replace(/,/g, "")) && !/^0\d/.test(s) ? Number(s.replace(/,/g, "")) : s;
  }

  /**
   * One workbook, one sheet per entry. Each sheet opens with the same title
   * block as the PDF, then each block's title, lead lines, header row and
   * data rows, so a sheet printed on its own still says what it is.
   */
  async function xlsx(name, sheets) {
    const XLSX = await ensureXlsx();
    const wb = XLSX.utils.book_new();
    const used = new Set();

    (sheets || []).forEach((sheet) => {
      const aoa = [
        [sheet.title || sheet.name],
        ["Facility / scope", sheet.scope || scopeLabel()],
        ["Period", sheet.period || "All records"],
        ["Prepared by", sheet.preparedBy || preparedBy()],
        ["Generated", stamp()],
      ];
      const widths = [];
      const measure = (row) => row.forEach((c, i) => {
        const len = String(c === null || c === undefined ? "" : c).length;
        widths[i] = Math.min(Math.max(widths[i] || 10, len + 2), 60);
      });

      (sheet.blocks || []).forEach((block) => {
        aoa.push([]);
        if (block.title) aoa.push([block.title]);
        (block.lead || []).forEach((line) => aoa.push([line]));
        const columns = block.columns || [];
        aoa.push(columns);
        measure(columns);
        const rows = block.rows || [];
        if (!rows.length) aoa.push([block.emptyText || "No records."]);
        rows.forEach((r) => {
          const row = r.map(asCell);
          aoa.push(row);
          measure(row);
        });
        (block.notes || []).forEach((line) => aoa.push([line]));
      });

      const ws = XLSX.utils.aoa_to_sheet(aoa);
      ws["!cols"] = widths.map((w) => ({ wch: w }));

      let sheetName = String(sheet.name || "Sheet").replace(/[\[\]:*?\/\\]/g, " ").slice(0, 31).trim() || "Sheet";
      let n = 2;
      while (used.has(sheetName)) sheetName = `${sheetName.slice(0, 28)} ${n++}`;
      used.add(sheetName);
      XLSX.utils.book_append_sheet(wb, ws, sheetName);
    });

    XLSX.writeFile(wb, name);
  }

  window.ExportKit = { pdf, xlsx, tableData, fileName, stamp, scopeLabel, preparedBy, pdfSafe, ensurePdf, ensureXlsx };
})();
