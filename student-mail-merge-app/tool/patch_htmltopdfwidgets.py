import glob
import os
import pathlib

pub_cache = os.environ.get("PUB_CACHE")
if not pub_cache:
    home = pathlib.Path.home()
    candidates = [
        home / ".pub-cache",
        pathlib.Path(os.environ.get("LOCALAPPDATA", "")) / "Pub" / "Cache",
    ]
    pub_cache = next((str(p) for p in candidates if p.exists()), str(candidates[0]))

pattern = os.path.join(
    pub_cache, "hosted", "pub.dev", "htmltopdfwidgets-2.1.1",
    "lib", "src", "browser", "pdf_builder.dart"
)
matches = glob.glob(pattern)
if not matches:
    raise SystemExit(f"htmltopdfwidgets source not found: {pattern}")

path = pathlib.Path(matches[0])
text = path.read_text(encoding="utf-8")
original = text

text = text.replace(
    "final cellContent = _buildCellRichText(allCellSpans[i], isHeader);",
    "final cellContent = _buildCellRichText(\\n"
    "            allCellSpans[i], isHeader, child.style.textDirection);",
)

text = text.replace(
    "final cellContent = _buildCellRichText(chunks[chunkIdx], isHeader);",
    "final cellContent = _buildCellRichText(\n"
    "              chunks[chunkIdx], isHeader, child.style.textDirection);",
)
text = text.replace(
    "pw.Widget _buildCellRichText(List<pw.InlineSpan> spans, bool isHeader) {",
    "pw.Widget _buildCellRichText(\n"
    "      List<pw.InlineSpan> spans, bool isHeader, pw.TextDirection? textDirection) {",
)
text = text.replace(
    """        textAlign: pw.TextAlign.center,
      );""",
    """        textAlign: pw.TextAlign.center,
        textDirection: textDirection,
      );""",
    1,
)
text = text.replace(
    """    return pw.RichText(
      overflow: pw.TextOverflow.span,
      text: pw.TextSpan(children: spans),
    );""",
    """    return pw.RichText(
      overflow: pw.TextOverflow.span,
      text: pw.TextSpan(children: spans),
      textAlign: textDirection == pw.TextDirection.rtl
          ? pw.TextAlign.right
          : pw.TextAlign.left,
      textDirection: textDirection,
    );""",
)
text = text.replace(
    "font: style.fontFamily != null ? null : null,",
    "font: fontFallback.isNotEmpty ? fontFallback.first : null,",
)

if text == original:
    raise SystemExit("Patch did not modify htmltopdfwidgets; source layout changed.")

required = [
    "child.style.textDirection",
    "pw.TextDirection? textDirection",
    "textDirection: textDirection",
    "font: fontFallback.isNotEmpty ? fontFallback.first : null",
]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit(f"Patch incomplete, missing: {missing}")

path.write_text(text, encoding="utf-8")
print(f"Patched Arabic RTL PDF table renderer: {path}")
