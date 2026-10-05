// ملف Excel حقيقي (xlsx) بدون مكتبات: كل جدول بورقة، والورقة من اليمين لليسار.
// الـ xlsx هو ملف zip فيه ملفات XML؛ منخزّنها بلا ضغط (أبسط، والحجم صغير للتقارير).

export type Cell = string | number | null | undefined;
export type Sheet = { name: string; rows: Cell[][] };

const encoder = new TextEncoder();

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(data: Uint8Array) {
  let crc = 0xffffffff;
  for (const byte of data) crc = CRC_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function zip(files: { name: string; data: Uint8Array }[]) {
  const chunks: Uint8Array[] = [];
  const central: Uint8Array[] = [];
  let offset = 0;

  for (const file of files) {
    const name = encoder.encode(file.name);
    const crc = crc32(file.data);
    const size = file.data.length;

    const local = new DataView(new ArrayBuffer(30));
    local.setUint32(0, 0x04034b50, true);
    local.setUint16(4, 20, true);
    local.setUint16(6, 0x0800, true); // أسماء UTF-8
    local.setUint16(8, 0, true); // بلا ضغط
    local.setUint32(14, crc, true);
    local.setUint32(18, size, true);
    local.setUint32(22, size, true);
    local.setUint16(26, name.length, true);
    chunks.push(new Uint8Array(local.buffer), name, file.data);

    const entry = new DataView(new ArrayBuffer(46));
    entry.setUint32(0, 0x02014b50, true);
    entry.setUint16(4, 20, true);
    entry.setUint16(6, 20, true);
    entry.setUint16(8, 0x0800, true);
    entry.setUint32(16, crc, true);
    entry.setUint32(20, size, true);
    entry.setUint32(24, size, true);
    entry.setUint16(28, name.length, true);
    entry.setUint32(42, offset, true);
    central.push(new Uint8Array(entry.buffer), name);

    offset += 30 + name.length + size;
  }

  const centralSize = central.reduce((sum, part) => sum + part.length, 0);
  const end = new DataView(new ArrayBuffer(22));
  end.setUint32(0, 0x06054b50, true);
  end.setUint16(8, files.length, true);
  end.setUint16(10, files.length, true);
  end.setUint32(12, centralSize, true);
  end.setUint32(16, offset, true);

  return new Blob([...chunks, ...central, new Uint8Array(end.buffer)] as BlobPart[], {
    type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  });
}

const escapeXml = (text: string) =>
  text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    // حروف تحكّم ممنوعة بـ XML
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, "");

function columnName(index: number) {
  let name = "";
  for (let n = index + 1; n > 0; n = Math.floor((n - 1) / 26)) {
    name = String.fromCharCode(65 + ((n - 1) % 26)) + name;
  }
  return name;
}

function sheetXml(rows: Cell[][]) {
  const body = rows
    .map((row, r) => {
      const cells = row
        .map((value, c) => {
          if (value == null || value === "") return "";
          const ref = `${columnName(c)}${r + 1}`;
          // السطر الأول عناوين (عريض).
          const style = r === 0 ? ' s="1"' : "";
          if (typeof value === "number" && Number.isFinite(value)) {
            // أرقام بفواصل الآلاف: صحيح #,##0 وكسور #,##0.00.
            const numberStyle = r === 0 ? style : Number.isInteger(value) ? ' s="2"' : ' s="3"';
            return `<c r="${ref}"${numberStyle}><v>${value}</v></c>`;
          }
          return `<c r="${ref}" t="inlineStr"${style}><is><t xml:space="preserve">${escapeXml(String(value))}</t></is></c>`;
        })
        .join("");
      return `<row r="${r + 1}">${cells}</row>`;
    })
    .join("");
  const width = Math.max(1, ...rows.map((row) => row.length));
  const cols = Array.from(
    { length: width },
    (_, i) => `<col min="${i + 1}" max="${i + 1}" width="20" customWidth="1"/>`,
  ).join("");
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView rightToLeft="1" workbookViewId="0"/></sheetViews><cols>${cols}</cols><sheetData>${body}</sheetData></worksheet>`;
}

export function buildXlsx(sheets: Sheet[]) {
  const list = sheets.length ? sheets : [{ name: "Sheet1", rows: [] }];
  const used = new Set<string>();
  const names = list.map((sheet, index) => {
    // اسم الورقة: 31 حرف كحد أقصى، بلا رموز ممنوعة، وما بيتكرر.
    let name =
      sheet.name
        .replace(/[\\/?*[\]:]/g, " ")
        .trim()
        .slice(0, 28) || `ورقة ${index + 1}`;
    while (used.has(name)) name = `${name.slice(0, 26)} ${index + 1}`;
    used.add(name);
    return name;
  });

  const files = [
    {
      name: "[Content_Types].xml",
      text: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>${list
        .map(
          (_, i) =>
            `<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`,
        )
        .join("")}</Types>`,
    },
    {
      name: "_rels/.rels",
      text: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`,
    },
    {
      name: "xl/workbook.xml",
      text: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${names
        .map(
          (name, i) => `<sheet name="${escapeXml(name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`,
        )
        .join("")}</sheets></workbook>`,
    },
    {
      name: "xl/_rels/workbook.xml.rels",
      text: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${list
        .map(
          (_, i) =>
            `<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`,
        )
        .join(
          "",
        )}<Relationship Id="rId${list.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`,
    },
    {
      name: "xl/styles.xml",
      text: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Arial"/></font><font><b/><sz val="11"/><name val="Arial"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>`,
    },
    ...list.map((sheet, i) => ({
      name: `xl/worksheets/sheet${i + 1}.xml`,
      text: sheetXml(sheet.rows),
    })),
  ];

  return zip(files.map((file) => ({ name: file.name, data: encoder.encode(file.text) })));
}

/** "1,234.50 USD" أو "12.5%" ← رقم، وإلا النص متل ما هو. */
export function cellValue(text: string): Cell {
  const clean = text.trim();
  const match = clean.match(/^(-?[\d,]+(?:\.\d+)?)\s*(?:[A-Z]{3}|%)?$/);
  if (match) {
    const value = Number(match[1].replace(/,/g, ""));
    if (Number.isFinite(value)) return value;
  }
  return clean;
}

/** كل جداول الصفحة (أو جزء منها) ← أوراق Excel. اسم الورقة من أقرب عنوان فوق الجدول. */
export function tablesToSheets(root: HTMLElement, fallbackName = "جدول"): Sheet[] {
  return Array.from(root.querySelectorAll("table")).map((table, index) => {
    const section = table.closest("section, .panel");
    const title = section?.querySelector("h2, h3")?.textContent?.trim() || (index ? `${fallbackName} ${index + 1}` : fallbackName);
    const rows = Array.from(table.querySelectorAll("tr")).map((tr) =>
      Array.from(tr.querySelectorAll("th, td")).map((cell) =>
        cellValue((cell as HTMLElement).innerText ?? ""),
      ),
    );
    return {
      name: title,
      rows: rows.filter((row) => row.some((cell) => cell !== "" && cell != null)),
    };
  });
}

export function downloadBlob(blob: Blob, fileName: string) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = fileName;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
