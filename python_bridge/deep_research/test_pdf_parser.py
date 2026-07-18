import zlib
import re
import io

pdf_content = b"""%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /Resources << >> /Contents 4 0 R >>
endobj
4 0 obj
<< /Length 44 >>
stream
BT
/F1 12 Tf
72 712 Td
(Hello World from PDF!) Tj
ET
endstream
endobj
xref
0 5
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
0000000193 00000 n 
trailer
<< /Size 5 /Root 1 0 R >>
startxref
287
%%EOF
"""

def extract_pdf_text(pdf_bytes):
    pypdf_text = ""
    pypdf_err = None
    try:
        from pypdf import PdfReader
        reader = PdfReader(io.BytesIO(pdf_bytes))
        text_parts = []
        for page in reader.pages:
            t = page.extract_text()
            if t:
                text_parts.append(t)
        pypdf_text = "\n".join(text_parts).strip()
    except Exception as pe:
        pypdf_err = pe

    if len(pypdf_text) >= 10:
        return pypdf_text
    
    stream_pattern = re.compile(rb"stream[\r\n]+([\s\S]*?)[\r\n]+endstream")
    custom_parts = []
    for match in stream_pattern.finditer(pdf_bytes):
        stream_content = match.group(1)
        decompressed = None
        try:
            decompressed = zlib.decompress(stream_content)
        except Exception:
            decompressed = stream_content
        if decompressed:
            for bt_match in re.finditer(rb"BT([\s\S]*?)ET", decompressed):
                bt_data = bt_match.group(1)
                for text_match in re.finditer(rb"\((.*?)\)", bt_data):
                    try:
                        val = text_match.group(1).decode("utf-8", errors="ignore")
                        val = re.sub(r"\\\d{3}", "", val)
                        val = val.replace("\\(", "(").replace("\\)", ")").replace("\\\\", "\\")
                        custom_parts.append(val)
                    except Exception:
                        pass
    custom_text = " ".join(custom_parts)
    custom_text = re.sub(rb"\s+", b" ", custom_text.encode("utf-8")).decode("utf-8").strip()
    
    if len(custom_text) >= 10:
        return custom_text
    elif pypdf_err is not None:
        raise pypdf_err
    else:
        raise ValueError("No text layer found (possibly scanned/image PDF)")

extracted = extract_pdf_text(pdf_content)
print(f"Extracted: '{extracted}'")
assert extracted == "Hello World from PDF!"
print("PDF parser test passed successfully!")
