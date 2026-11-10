# -*- coding: utf-8 -*-
"""
Genera informe_u4.docx a partir de informe_u4_base.md
Solo lectura del markdown; no se conecta a ninguna base de datos.
"""
import re
import sys
from docx import Document
from docx.shared import Pt, Inches, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT

MD_PATH = "entrega_u4/entrega_final/informe_u4_base.md"
DOCX_PATH = "entrega_u4/entrega_final/informe_u4.docx"

def md_to_docx(md_path, docx_path):
    with open(md_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    doc = Document()

    # Estilo base
    style = doc.styles["Normal"]
    style.font.name = "Calibri"
    style.font.size = Pt(11)

    i = 0
    while i < len(lines):
        line = lines[i].rstrip("\n")

        # Cabecera H1
        if line.startswith("# "):
            h = doc.add_heading(line[2:], level=1)
            i += 1
            continue

        # Cabecera H2
        if line.startswith("## "):
            h = doc.add_heading(line[3:], level=2)
            i += 1
            continue

        # Cabecera H3
        if line.startswith("### "):
            h = doc.add_heading(line[4:], level=3)
            i += 1
            continue

        # Tabla markdown (detectar fila con |)
        if line.strip().startswith("|"):
            # Recolectar todas las filas de la tabla contigua
            table_rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                # Saltar la fila separadora (---)
                if all(set(c) <= set("-: ") for c in cells):
                    i += 1
                    continue
                table_rows.append(cells)
                i += 1
            if table_rows:
                tbl = doc.add_table(rows=len(table_rows), cols=len(table_rows[0]))
                tbl.style = "Light Grid Accent 1"
                tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
                for r_idx, row in enumerate(table_rows):
                    for c_idx, cell_text in enumerate(row):
                        cell = tbl.cell(r_idx, c_idx)
                        cell.text = cell_text
                        for p in cell.paragraphs:
                            for run in p.runs:
                                run.font.size = Pt(9)
            continue

        # Línea en blanco
        if not line.strip():
            i += 1
            continue

        # Línea de separador ---
        if line.strip() == "---":
            i += 1
            continue

        # Párrafo normal (puede contener código en backticks)
        p = doc.add_paragraph()
        # Dividir por backticks para aplicar negrita a código inline
        parts = line.split("`")
        for j, part in enumerate(parts):
            if j % 2 == 0:
                if part:
                    p.add_run(part)
            else:
                run = p.add_run(part)
                run.bold = True
                run.font.color.rgb = RGBColor(0x1F, 0x3B, 0x5C)
        i += 1

    doc.save(docx_path)
    print(f"DOCX generado: {docx_path}")

if __name__ == "__main__":
    md_to_docx(MD_PATH, DOCX_PATH)
