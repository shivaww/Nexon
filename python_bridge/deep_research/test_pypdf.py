import io
import urllib.request
from pypdf import PdfReader

url = "https://arxiv.org/pdf/2403.00001.pdf"
print(f"Downloading {url}...")
headers = {"User-Agent": "Mozilla/5.0"}
req = urllib.request.Request(url, headers=headers)
with urllib.request.urlopen(req, timeout=30) as response:
    pdf_bytes = response.read()

print(f"Downloaded {len(pdf_bytes)} bytes. Extracting text using pypdf...")
reader = PdfReader(io.BytesIO(pdf_bytes))
text_parts = []
for page in reader.pages:
    t = page.extract_text()
    if t:
        text_parts.append(t)

full_text = "\n".join(text_parts)
print(f"Extracted text length: {len(full_text)}")
print("First 300 chars:")
print(full_text[:300])

assert len(full_text) > 1000
print("pypdf extraction test passed successfully!")
