const data = $input.first().json;

// ---------------- Helpers ----------------
const asString = (v) => (v == null ? "" : String(v));

const fixMojibake = (s) => {
  s = asString(s);
  const looksBad =
    s.includes("Ã") || s.includes("â€™") || s.includes("â€œ") || s.includes("â€") || s.includes("Â");
  if (!looksBad) return s;
  return s
    .replace(/â€“/g, "–")
    .replace(/â€”/g, "—")
    .replace(/â€œ/g, "“")
    .replace(/â€/g, "”")
    .replace(/â€™/g, "’")
    .replace(/Â/g, "")
    .replace(/Ã¡/g, "á")
    .replace(/Ã©/g, "é")
    .replace(/Ã­/g, "í")
    .replace(/Ã³/g, "ó")
    .replace(/Ãº/g, "ú")
    .replace(/Ã±/g, "ñ")
    .replace(/Ã/g, "Á")
    .replace(/Ã‰/g, "É")
    .replace(/Ã/g, "Í")
    .replace(/Ã“/g, "Ó")
    .replace(/Ãš/g, "Ú")
    .replace(/Ã‘/g, "Ñ");
};

const clean = (s) =>
  fixMojibake(asString(s))
    .replace(/\u00a0/g, " ")
    .replace(/\s+/g, " ")
    .trim();

const toArray = (v) => (Array.isArray(v) ? v : (v ? [v] : []));

const slugFromUrl = (url) => {
  if (!url) return null;
  const parts = asString(url).split("?")[0].split("#")[0].split("/").filter(Boolean);
  return parts.length ? parts[parts.length - 1] : null;
};

const simpleHash = (str) => {
  str = String(str || "");
  let hash = 2166136261;
  for (let i = 0; i < str.length; i++) {
    hash ^= str.charCodeAt(i);
    hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
  }
  return ("00000000" + (hash >>> 0).toString(16)).slice(-8);
};

// ---------------- Inputs ----------------
const url = data.url || null;
const title = clean(data.title) || null;
const description = clean(data.description) || null;
const category_path = clean(data.category_path) || null;
const language = data.language || "es";
const page_type = data.page_type || "page";

// ---------------- Breadcrumbs (objects) ----------------
// data.breadcrumbs is array of {name,url,position}
const breadcrumbs = toArray(data.breadcrumbs).filter(Boolean);

// Names extracted (useful for search/classification)
const breadcrumb_names = breadcrumbs
  .map(b => (b && typeof b === "object" ? clean(b.name) : clean(b)))
  .filter(Boolean);

// ---------------- doc_id / slug ----------------
const slug = data.slug || slugFromUrl(url);
const doc_id = data.doc_id || simpleHash(data.canonical_url || url || `${title || ""}|${slug || ""}`);

// ---------------- Content kind classification (simple v1) ----------------
const haystack = clean(
  [
    page_type,
    url,
    title,
    description,
    category_path,
    breadcrumb_names.join(" "),
    data.text_body,
  ]
    .filter(Boolean)
    .join(" | ")
).toLowerCase();

const classifyContentKind = () => {
  // For page_chunk flow, page_type should NOT be product anyway,
  // but we keep this guard just in case.
  if (page_type === "product") return "product_page";

  if (haystack.includes("envío") || haystack.includes("envios") || haystack.includes("shipping") || haystack.includes("entrega"))
    return "shipping";
  if (haystack.includes("devol") || haystack.includes("returns") || haystack.includes("reembolso") || haystack.includes("cambio"))
    return "returns";
  if (haystack.includes("pedido") || haystack.includes("comprar") || haystack.includes("checkout") || haystack.includes("carrito") || haystack.includes("ordering"))
    return "ordering";
  if (haystack.includes("pago") || haystack.includes("payment") || haystack.includes("tarjeta") || haystack.includes("bizum") || haystack.includes("transferencia"))
    return "payments";
  if (haystack.includes("garant") || haystack.includes("warranty")) return "warranty";
  if (haystack.includes("contacto") || haystack.includes("email") || haystack.includes("tel") || haystack.includes("whatsapp") || haystack.includes("contact"))
    return "contact";
  if (haystack.includes("legal") || haystack.includes("privacidad") || haystack.includes("cookies") || haystack.includes("términos") || haystack.includes("terminos"))
    return "legal";
  if (haystack.includes("faq") || haystack.includes("preguntas frecuentes")) return "faq";
  if (haystack.includes("quiénes somos") || haystack.includes("quienes somos") || haystack.includes("about"))
    return "about";
  if (haystack.includes("graduación") || haystack.includes("graduacion") || haystack.includes("rx") || haystack.includes("prescripción") || haystack.includes("prescripcion"))
    return "rx_info";

  return "other";
};

const content_kind = data.content_kind || classifyContentKind();
const is_policy = ["shipping", "returns", "payments", "warranty", "legal"].includes(content_kind);

// ---------------- Section heading (best-effort) ----------------
const section_heading =
  clean(data.section_heading) ||
  (content_kind === "shipping"
    ? "Envíos"
    : content_kind === "returns"
    ? "Devoluciones"
    : content_kind === "ordering"
    ? "Pedidos y compra"
    : content_kind === "payments"
    ? "Pagos"
    : content_kind === "warranty"
    ? "Garantía"
    : content_kind === "contact"
    ? "Contacto"
    : content_kind === "legal"
    ? "Legal"
    : content_kind === "faq"
    ? "Preguntas frecuentes"
    : content_kind === "rx_info"
    ? "Graduación (RX)"
    : title) ||
  null;

const heading_path = toArray(data.heading_path).length
  ? toArray(data.heading_path).map(clean).filter(Boolean)
  : section_heading
  ? [section_heading]
  : [];

// ---------------- Build cleaned base text ----------------
const body = clean(data.text_body);
const intro = description ? description : "";
const mainText = clean([intro, body].filter(Boolean).join("\n\n"));

// canonical document text (pre-chunk)
const docText = clean(
  [
    title ? `Título: ${title}` : null,
    url ? `URL: ${url}` : null,
    section_heading ? `Sección: ${section_heading}` : null,
    category_path ? `Ruta: ${category_path}` : null,
    mainText ? `Contenido: ${mainText}` : null,
  ]
    .filter(Boolean)
    .join("\n")
);

// ---------------- Chunking ----------------
const chunkSize = 1800; // chars
const chunks = [];
for (let i = 0; i < docText.length; i += chunkSize) {
  chunks.push(docText.slice(i, i + chunkSize));
}

// ---------------- Output records ----------------
return chunks.map((chunkText, idx) => {
  const chunk_id = `${doc_id}#c${String(idx).padStart(3, "0")}`;

  const canonical_text = clean(
    [
      title ? `Título: ${title}` : null,
      section_heading ? `Sección: ${section_heading}` : null,
      url ? `URL: ${url}` : null,
      `Contenido: ${chunkText}`,
    ]
      .filter(Boolean)
      .join("\n")
  );

  return {
    json: {
      pageContent: canonical_text,
      metadata: {
        type: "page_chunk",
        source: "website",

        doc_id,
        chunk_id,
        chunk_index: idx,
        chunk_total: chunks.length,

        url,
        slug,
        title,
        language,

        category_path,
        breadcrumbs,         // keep objects as-is
        breadcrumb_names,    // add normalized names (string[])

        section_heading,
        heading_path,
        content_kind,
        is_policy,

        page_type,

        updated_at: data.updated_at || new Date().toISOString(),
      },
    },
  };
});
