import os
import json
import asyncio
import httpx
from fastapi import FastAPI, Request, HTTPException, Depends
from fastapi.responses import JSONResponse, StreamingResponse
from supabase import create_client, Client
from dotenv import load_dotenv
from fastapi.middleware.cors import CORSMiddleware

load_dotenv()

# --- INIT ---
app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")
supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY) if SUPABASE_URL and SUPABASE_SERVICE_KEY else None

# --- LOAD SHEDDER (Firewall & Compute Maximizer) ---
# Limits concurrent heavy requests to server capacity (e.g., 100 at a time)
MAX_CONCURRENT_REQUESTS = 100
semaphore = asyncio.Semaphore(MAX_CONCURRENT_REQUESTS)

# --- MODEL MULTIPLIERS ---
# In production, pull this from a DB table. For now, hardcoded from our math.
MODEL_MULTIPLIERS = {
    "deepseek-v4-flash": {"in": 1.0, "out": 2.0, "est_out": 2000},
    "llama-4-maverick": {"in": 1.93, "out": 6.07, "est_out": 2000},
    "glm-5.2": {"in": 10.0, "out": 31.43, "est_out": 8000}, # Higher estimate for reasoning models
}

# --- AUTH FIREWALL ---
async def verify_jwt(request: Request):
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid token")
    
    token = auth_header.split(" ")[1]
    try:
        # Verify token against Supabase
        user_response = supabase.auth.get_user(token)
        if not user_response.user:
            raise HTTPException(status_code=401, detail="Invalid token")
        return user_response.user.id
    except Exception:
        raise HTTPException(status_code=401, detail="Authentication failed")

# --- PROXY ENDPOINT ---
@app.post("/v1/chat/completions")
async def chat_completions(request: Request, user_id: str = Depends(verify_jwt)):
    if not supabase:
        raise HTTPException(status_code=500, detail="Supabase not configured in backend.")

    # 1. Check Server Capacity (Load Shedding)
    if semaphore.locked() and semaphore._value == 0:
        return JSONResponse(
            status_code=503,
            content={"error": {"message": "Server is at its highest work please try again later."}}
        )

    body = await request.json()
    model_id = body.get("model")
    
    # 2. Estimate Credits Needed (Pre-flight deduction)
    if model_id not in MODEL_MULTIPLIERS:
        # Fallback for unknown models (e.g. testing new kaggle models)
        mult = {"in": 1.0, "out": 2.0, "est_out": 2000}
    else:
        mult = MODEL_MULTIPLIERS[model_id]
        
    est_input_tokens = 15000 
    est_credits_needed = int((est_input_tokens * mult["in"]) + (mult["est_out"] * mult["out"]))

    try:
        # 3. Atomic Database Deduction
        deduct_response = supabase.rpc('deduct_user_credits', {
            'p_user_id': user_id,
            'p_credits_needed': est_credits_needed
        }).execute()
        
        if not deduct_response.data or deduct_response.data.get('status') != 'success':
            raise HTTPException(status_code=429, detail="Daily Circuit Breaker Reached or Insufficient Credits.")
            
    except Exception as e:
        # 429 means circuit breaker or insufficient credits natively raised by the db function
        if 'Daily Circuit Breaker Reached' in str(e):
             raise HTTPException(status_code=429, detail="[Nexon Circuit Breaker] Daily safety governor reached. Unused balance preserved for tomorrow.")
        if 'Insufficient credits' in str(e):
             raise HTTPException(status_code=402, detail="Insufficient credits. Please top up or upgrade.")
        raise HTTPException(status_code=500, detail=f"Credit deduction failed: {str(e)}")

    # 4. Acquire Semaphore & Proxy Request to Upstream
    async with semaphore:
        target_url = os.getenv("KAGGLE_URL", "https://api.together.xyz/v1/chat/completions")
        
        # Auto-fix URL if user forgot to add /chat/completions
        if not target_url.endswith("/chat/completions"):
            if target_url.endswith("/"):
                target_url += "v1/chat/completions" if "v1" not in target_url else "chat/completions"
            else:
                target_url += "/v1/chat/completions" if "v1" not in target_url else "/chat/completions"
                
        headers = {
            "Authorization": f"Bearer {os.getenv('MASTER_API_KEY', 'dummy_key')}",
            "Content-Type": "application/json"
        }
        
        print(f"NEXON PROXY: Forwarding request to -> {target_url}", flush=True)
        
        client = httpx.AsyncClient(timeout=120.0)
        req = client.build_request("POST", target_url, headers=headers, json=body)
        
        try:
            upstream_response = await client.send(req, stream=True)
        except httpx.RequestError:
            await client.aclose()
            raise HTTPException(status_code=503, detail="Upstream AI provider unreachable.")

        if upstream_response.status_code != 200:
            error_body = await upstream_response.aread()
            await upstream_response.aclose()
            await client.aclose()
            
            error_text = error_body.decode('utf-8', errors='ignore')
            print(f"NEXON PROXY ERROR: {upstream_response.status_code} - {error_text}", flush=True)
            try:
                err_json = json.loads(error_text)
            except:
                err_json = {"detail": f"Upstream returned {upstream_response.status_code}: {error_text[:200]}"}
            return JSONResponse(status_code=upstream_response.status_code, content=err_json)

        async def stream_generator():
            try:
                async for chunk in upstream_response.aiter_bytes():
                    yield chunk
            finally:
                await upstream_response.aclose()
                await client.aclose()
                
        return StreamingResponse(stream_generator(), media_type="text/event-stream")
