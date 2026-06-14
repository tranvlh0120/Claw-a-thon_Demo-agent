from fastapi import FastAPI, UploadFile, File
from fastapi.responses import HTMLResponse
import pandas as pd
import requests
import io
import os
from datetime import datetime

app = FastAPI()

API_KEY      = os.getenv("GREENNODE_API_KEY", "")
LLM_ENDPOINT = os.getenv("LLM_ENDPOINT", "https://maas-llm-aiplatform-hcm.api.vngcloud.vn/v1/chat/completions")
LLM_MODEL    = os.getenv("LLM_MODEL", "minimax/minimax-m2.5")

KEY_COLS = ["Action Type", "Action Source", "MKT Code", "User Segment", "Task Tag", "Task ID"]

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/generate-report", response_class=HTMLResponse)
async def generate_report(
    coin_file: UploadFile = File(...),
    user_file: UploadFile = File(...)
):
    coin_df = pd.read_csv(io.BytesIO(await coin_file.read()), sep="\t", encoding="utf-16")
    user_df = pd.read_csv(io.BytesIO(await user_file.read()), sep="\t", encoding="utf-16")

    months = [c for c in coin_df.columns if c not in KEY_COLS]
    latest = months[0]
    prev   = months[1] if len(months) > 1 else None

    merged = coin_df.merge(user_df, on=KEY_COLS, suffixes=("_coin", "_user"), how="left")

    summary_lines = [f"=== DU LIEU EARN XU ZALOPAY ===", f"Thang moi nhat: {latest} | Thang truoc: {prev}", ""]

    # Overview by source (Action Type != ALL, Source = ALL, segment filter)
    src_rows = merged[
        (merged["Action Type"] != "ALL") &
        (merged["Action Source"] == "ALL") &
        (merged["MKT Code"].fillna("") == "") &
        (merged["Task Tag"] == "ALL") &
        (merged["Task ID"] == "ALL")
    ]

    summary_lines.append("--- THEO EARN SOURCE ---")
    for _, r in src_rows.iterrows():
        def parse(v):
            try: return float(str(v).replace(",","").strip())
            except: return None
        coin_cur  = parse(r.get(f"{latest}_coin"))
        coin_prev = parse(r.get(f"{prev}_coin")) if prev else None
        user_cur  = parse(r.get(f"{latest}_user"))
        cpu       = round(coin_cur/user_cur, 1) if coin_cur and user_cur and user_cur > 0 else None
        mom       = round((coin_cur-coin_prev)/coin_prev*100,1) if coin_cur and coin_prev and coin_prev>0 else None
        line = f"Source={r['Action Type']} | Segment={r['User Segment']}"
        if coin_cur: line += f" | Coin={coin_cur:,.0f}"
        if mom is not None: line += f" | MoM={mom}%"
        if user_cur: line += f" | User={user_cur:,.0f}"
        if cpu: line += f" | Coin/User={cpu}"
        summary_lines.append(line)

    # Overview by segment (ALL source)
    seg_rows = merged[
        (merged["Action Type"] == "ALL") &
        (merged["Action Source"] == "ALL") &
        (merged["MKT Code"].fillna("") == "") &
        (merged["Task Tag"] == "ALL") &
        (merged["Task ID"] == "ALL")
    ]

    summary_lines.append("")
    summary_lines.append("--- THEO SEGMENT (ALL SOURCES) ---")
    for _, r in seg_rows.iterrows():
        def parse(v):
            try: return float(str(v).replace(",","").strip())
            except: return None
        coin_cur  = parse(r.get(f"{latest}_coin"))
        coin_prev = parse(r.get(f"{prev}_coin")) if prev else None
        user_cur  = parse(r.get(f"{latest}_user"))
        cpu       = round(coin_cur/user_cur,1) if coin_cur and user_cur and user_cur>0 else None
        mom       = round((coin_cur-coin_prev)/coin_prev*100,1) if coin_cur and coin_prev and coin_prev>0 else None
        line = f"Segment={r['User Segment']}"
        if coin_cur: line += f" | Coin={coin_cur:,.0f}"
        if mom is not None: line += f" | MoM={mom}%"
        if user_cur: line += f" | User={user_cur:,.0f}"
        if cpu: line += f" | Coin/User={cpu}"
        summary_lines.append(line)

    data_context = "\n".join(summary_lines)

    prompt = f"""Bạn là chuyên viên phân tích dữ liệu tại team Loyalty ZaloPay.
Dưới đây là dữ liệu thống kê xu earn của users theo từng source và segment.

{data_context}

Lưu ý: {latest} là tháng chưa đầy đủ data (mới có ~13 ngày), vui lòng đề cập điều này khi phân tích MoM.

Hãy viết một báo cáo tóm tắt bằng tiếng Việt theo cấu trúc sau:

## TỔNG QUAN THÁNG {latest}

### 1. Điểm nổi bật
(3-5 bullet points về những điểm đáng chú ý nhất)

### 2. Phân tích Segment NU (New User)
(Phân tích kỹ NU: coin, user, coin/user, MoM, breakdown theo source)

### 3. Phân tích các Segment còn lại
(CU, SU, SU30, SU60, NU30, NU60, UNDEFINED)

### 4. Phân tích theo Earn Source
(TRANSACTION, CHECK_IN, v.v. — MoM, segment đóng góp chính)

### 5. Điểm cần theo dõi
(2-3 điểm cần action, ưu tiên NU)

Viết súc tích, dùng số liệu cụ thể, đơn vị "xu", số lớn dùng "M xu" hoặc "B xu"."""

    narrative = ""
    if API_KEY:
        try:
            resp = requests.post(
                LLM_ENDPOINT,
                headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
                json={"model": LLM_MODEL, "max_tokens": 2000, "messages": [{"role":"user","content":prompt}]},
                timeout=60
            )
            narrative = resp.json()["choices"][0]["message"]["content"]
        except Exception as e:
            narrative = f"Lỗi khi gọi AI: {e}"
    else:
        narrative = "Thiếu API key. Set biến môi trường GREENNODE_API_KEY."

    def md_to_html(text):
        lines, out = text.split("\n"), []
        for line in lines:
            t = line.strip()
            if t.startswith("## "): out.append(f"<h2>{t[3:]}</h2>")
            elif t.startswith("### "): out.append(f"<h3>{t[4:]}</h3>")
            elif t.startswith("- ") or t.startswith("* "): out.append(f"<li>{t[2:]}</li>")
            elif t == "": out.append("<br>")
            else:
                t = t.replace("**", "<b>", 1).replace("**", "</b>", 1) if "**" in t else t
                out.append(f"<p>{t}</p>")
        return "\n".join(out)

    html = f"""<!DOCTYPE html>
<html><head><meta charset="UTF-8">
<title>Earn Report {latest}</title>
<style>
  body{{font-family:Arial,sans-serif;max-width:900px;margin:40px auto;padding:0 20px;color:#333}}
  h1{{color:white;margin:0;border:none}}
  h2{{color:#2E75B6;margin-top:28px}}
  h3{{color:#404040}}
  li{{margin:5px 0}}
  .header{{background:#1F4E79;padding:20px 24px;border-radius:8px;margin-bottom:28px}}
  .header p{{color:#ccc;margin:6px 0 0;font-size:13px}}
</style></head>
<body>
<div class="header">
  <h1>BÁO CÁO EARN XU — ZALOPAY LOYALTY</h1>
  <p>Tạo tự động bởi Earn Report Agent | {datetime.now().strftime('%d/%m/%Y %H:%M')}</p>
</div>
{md_to_html(narrative)}
</body></html>"""

    return HTMLResponse(content=html)
