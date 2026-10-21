// Page format of the capstone paper, as a template for the documents split out of it (chapter3.typ).
// Copied from capstone-documentation.typ (A4, 4 cm binding margin, Times New Roman 12 pt, double-spaced,
// school header with the red frame); keep the two in sync if the paper's layout changes.
// Use: #import "capstone-documentation/capstone-style.typ": capstone-style, subhead   (from docs/)
//      #show: capstone-style                     // CHAPTER I headings, sections 1.1, figures 1.1
//      #show: capstone-style.with(chapters: false) // plain 1 / 1.1 headings for a standalone document

// Word "double" spacing for Times New Roman 12 pt is a 27.6 pt line pitch: 0.66 em of glyph box + 1.64 em leading.
#let double = 1.64em

// Bold run-in label above a block of text (Level 1, Level 2, ...).
#let subhead(body) = block(above: double, below: double, sticky: true, strong(body))

#let capstone-style(chapters: true, body) = {
  set page(
    paper: "a4",
    margin: (top: 1.25in, bottom: 1in, left: 4cm, right: 1in),
    numbering: "1",
    header: none,
    footer: [],
  )

  // ---------- Text ----------

  set text(font: "Times New Roman", size: 12pt, lang: "en", hyphenate: false)
  set par(justify: true, leading: double, spacing: double, first-line-indent: (amount: 0.5in, all: true))
  set list(indent: 0.25in, body-indent: 0.5em, spacing: double)
  set enum(indent: 0.25in, body-indent: 0.5em, spacing: double)

  // ---------- Headings: CHAPTER I / title (or 1 / title), then 1.1 ----------

  set heading(numbering: (..n) => {
    let n = n.pos()
    if n.len() == 1 and chapters { "CHAPTER " + numbering("I", n.first()) } else { numbering("1.1", ..n) }
  })
  show heading: set text(12pt, weight: "bold")
  show heading: set block(above: double, below: double)
  show heading.where(level: 1): it => {
    pagebreak(weak: true)
    counter(figure.where(kind: image)).update(0)
    counter(figure.where(kind: table)).update(0)
    set par(leading: 0.65em, first-line-indent: 0pt)
    block(width: 100%, below: 2 * double, align(center)[#counter(heading).display() \ #it.body])
  }

  // ---------- Figures and tables: numbered per chapter, table captions on top ----------

  set figure(numbering: n => numbering("1.1", counter(heading).get().first(), n))
  set figure.caption(separator: [. ])
  show figure.caption: set text(style: "italic")
  show figure.caption: set par(leading: 0.65em)
  show figure.where(kind: table): set figure.caption(position: top)
  show figure: set block(breakable: true, above: double, below: double)
  // Diagrams keep the font, but not the body's double spacing, justification or indent.
  show figure.where(kind: image): set par(justify: false, leading: 0.65em, spacing: 1.2em, first-line-indent: 0pt)

  set table(stroke: 0.5pt, inset: 5pt, fill: (_, y) => if y == 0 { rgb("#D9EAF7") })
  show table.cell.where(y: 0): set align(center + horizon)
  show table.cell.where(y: 0): strong
  show table: set par(justify: false, leading: 0.65em)
  show figure.where(kind: table): set text(10pt)

  body
}
