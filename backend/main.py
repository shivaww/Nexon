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
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")
supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY) if SUPABASE_URL and SUPABASE_SERVICE_KEY else None

# --- LOAD SHEDDER (Firewall & Compute Maximizer) ---
# Limits concurrent heavy requests to Kaggle's capacity (default 100 for parallel batching)
MAX_CONCURRENT_REQUESTS = int(os.getenv("MAX_CONCURRENT_REQUESTS", "100"))
semaphore = asyncio.Semaphore(MAX_CONCURRENT_REQUESTS)

# --- PER-USER RATE LIMIT ---
from collections import defaultdict
user_semaphores = defaultdict(lambda: asyncio.Semaphore(5)) # Max 5 concurrent streams per user

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
        user_response = await asyncio.to_thread(supabase.auth.get_user, token)
        if not user_response.user:
            raise HTTPException(status_code=401, detail="Invalid token")
        return user_response.user.id
    except Exception:
        raise HTTPException(status_code=401, detail="Authentication failed")

async def _get_user_wallet(user_id: str) -> dict:
    try:
        def fetch():
            return supabase.table("user_wallets").select("current_daily_pool, subscription_credits, topup_credits").eq("user_id", user_id).maybe_single().execute()
        response = await asyncio.to_thread(fetch)
        return response.data or {}
    except Exception as e:
        print(f"Failed to fetch user wallet: {e}")
        return {}

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

    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    if not isinstance(body, dict):
        raise HTTPException(status_code=400, detail="Request body must be a JSON object")

    model_id = body.get("model")
    is_stream = body.get("stream", False)
    
    # Payload Size Check
    content_length = request.headers.get("content-length")
    if content_length and int(content_length) > 10 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Payload too large (Max 10MB)")
        
    messages = body.get("messages", [])
    if not isinstance(messages, list):
        raise HTTPException(status_code=400, detail="'messages' must be a list")
    total_len = 0
    image_count = 0
    for m in messages:
        if not isinstance(m, dict):
            continue
        content = m.get("content")
        if isinstance(content, str):
            total_len += len(content)
        elif isinstance(content, list):
            for part in content:
                if not isinstance(part, dict):
                    continue
                if part.get("type") == "text":
                    total_len += len(part.get("text", ""))
                elif part.get("type") == "image_url":
                    image_count += 1
    actual_input_tokens = max(10, (total_len // 4) + (image_count * 1000))
    
    if model_id not in MODEL_MULTIPLIERS:
        # Fallback for unknown models
        mult = {"in": 1.0, "out": 2.0, "est_out": 2000}
    else:
        mult = MODEL_MULTIPLIERS[model_id]
        
    est_credits_needed = int((actual_input_tokens * mult["in"]) + (mult["est_out"] * mult["out"]))

    try:
        # 3. Atomic Database Deduction (Pre-flight)
        def deduct_preflight():
            return supabase.rpc('deduct_user_credits', {
                'p_user_id': user_id,
                'p_credits_needed': est_credits_needed
            }).execute()
        deduct_response = await asyncio.to_thread(deduct_preflight)
        
        if not deduct_response.data or deduct_response.data.get('status') != 'success':
            raise HTTPException(status_code=429, detail="Daily Circuit Breaker Reached or Insufficient Credits.")
            
    except Exception as e:
        if 'Daily Circuit Breaker Reached' in str(e):
             raise HTTPException(status_code=429, detail="[Nexon Circuit Breaker] Daily safety governor reached. Unused balance preserved for tomorrow.")
        if 'Insufficient credits' in str(e):
             raise HTTPException(status_code=402, detail="Insufficient credits. Please top up or upgrade.")
        raise HTTPException(status_code=500, detail=f"Credit deduction failed: {str(e)}")

    # 4. Acquire Semaphore & Proxy Request to Upstream
    async def proxy_request():
        user_sem = user_semaphores[user_id]
        if user_sem.locked():
            return JSONResponse(status_code=429, content={"error": {"message": "Too many concurrent requests. Please wait for your previous tasks to finish."}})
            
        async with user_sem:
            async with semaphore:
                target_url = os.getenv("KAGGLE_URL", "https://api.together.xyz/v1/chat/completions")
            if not target_url.endswith("/chat/completions"):
                if target_url.endswith("/"):
                    target_url += "v1/chat/completions" if "v1" not in target_url else "chat/completions"
                else:
                    target_url += "/v1/chat/completions" if "v1" not in target_url else "/chat/completions"
                    
            headers = {
                "Authorization": f"Bearer {os.getenv('MASTER_API_KEY', 'dummy_key')}",
                "Content-Type": "application/json"
            }
            
            client = httpx.AsyncClient(timeout=120.0)
            
            if is_stream:
                req = client.build_request("POST", target_url, headers=headers, json=body)
                try:
                    upstream_response = await client.send(req, stream=True)
                except httpx.RequestError:
                    await client.aclose()
                    # Refund everything if the server is unreachable
                    def refund_unreachable():
                        supabase.rpc('deduct_user_credits', {'p_user_id': user_id, 'p_credits_needed': -est_credits_needed}).execute()
                    await asyncio.to_thread(refund_unreachable)
                    raise HTTPException(status_code=503, detail="Upstream AI provider unreachable.")

                if upstream_response.status_code != 200:
                    error_body = await upstream_response.aread()
                    await upstream_response.aclose()
                    await client.aclose()
                    
                    # Refund everything if upstream failed
                    def refund_upstream_failed():
                        supabase.rpc('deduct_user_credits', {'p_user_id': user_id, 'p_credits_needed': -est_credits_needed}).execute()
                    await asyncio.to_thread(refund_upstream_failed)
                    
                    error_text = error_body.decode('utf-8', errors='ignore')
                    try:
                        err_json = json.loads(error_text)
                    except:
                        err_json = {"detail": f"Upstream returned {upstream_response.status_code}: {error_text[:200]}"}
                    return JSONResponse(status_code=upstream_response.status_code, content=err_json)

                async def stream_generator():
                    output_chars = 0
                    actual_output_tokens = None
                    buffer = ""
                    try:
                        async for chunk in upstream_response.aiter_bytes():
                            yield chunk
                            buffer += chunk.decode('utf-8', errors='ignore')
                            while "\n" in buffer:
                                line, buffer = buffer.split("\n", 1)
                                line = line.strip()
                                if line.startswith("data: "):
                                    data_str = line[6:].strip()
                                    if data_str == "[DONE]":
                                        continue
                                    try:
                                        data_json = json.loads(data_str)
                                        choices = data_json.get("choices", [])
                                        if choices:
                                            delta = choices[0].get("delta", {})
                                            content = delta.get("content", "")
                                            if content:
                                                output_chars += len(content)
                                        usage = data_json.get("usage")
                                        if usage and "completion_tokens" in usage:
                                            actual_output_tokens = usage["completion_tokens"]
                                    except Exception:
                                        pass
                    finally:
                        await upstream_response.aclose()
                        await client.aclose()
                        
                        # Post-flight Refund Calculation
                        if actual_output_tokens is None:
                            actual_output_tokens = output_chars // 4
                        
                        credits_used = int((actual_input_tokens * mult["in"]) + (actual_output_tokens * mult["out"]))
                        refund_amount = est_credits_needed - credits_used
                        if refund_amount != 0:
                            def refund_postflight():
                                supabase.rpc('deduct_user_credits', {
                                    'p_user_id': user_id,
                                    'p_credits_needed': -refund_amount
                                }).execute()
                            try:
                                await asyncio.to_thread(refund_postflight)
                            except Exception as e:
                                print(f"Failed to issue refund: {e}")

                        # Send realtime credit status
                        wallet = await _get_user_wallet(user_id)
                        if wallet:
                            credits_status = {
                                "daily": wallet.get("current_daily_pool", 0),
                                "subscription": wallet.get("subscription_credits", 0),
                                "topup": wallet.get("topup_credits", 0),
                            }
                            yield f"data: {json.dumps({'credits_status': credits_status})}\n\n".encode("utf-8")
                        
                return StreamingResponse(stream_generator(), media_type="text/event-stream")
            else:
                # Non-streaming path
                try:
                    upstream_response = await client.post(target_url, headers=headers, json=body)
                except httpx.RequestError:
                    await client.aclose()
                    def refund_unreachable_nonstream():
                        supabase.rpc('deduct_user_credits', {'p_user_id': user_id, 'p_credits_needed': -est_credits_needed}).execute()
                    await asyncio.to_thread(refund_unreachable_nonstream)
                    raise HTTPException(status_code=503, detail="Upstream AI provider unreachable.")

                if upstream_response.status_code != 200:
                    error_text = upstream_response.text
                    await client.aclose()
                    def refund_upstream_failed_nonstream():
                        supabase.rpc('deduct_user_credits', {'p_user_id': user_id, 'p_credits_needed': -est_credits_needed}).execute()
                    await asyncio.to_thread(refund_upstream_failed_nonstream)
                    try:
                        err_json = json.loads(error_text)
                    except:
                        err_json = {"detail": f"Upstream returned {upstream_response.status_code}: {error_text[:200]}"}
                    return JSONResponse(status_code=upstream_response.status_code, content=err_json)

                resp_json = upstream_response.json()
                await client.aclose()

                usage = resp_json.get("usage", {})
                actual_input = usage.get("prompt_tokens", actual_input_tokens)
                actual_output = usage.get("completion_tokens", 0)

                if not actual_output:
                    choices = resp_json.get("choices", [])
                    if choices:
                        message = choices[0].get("message", {})
                        content = message.get("content", "")
                        actual_output = len(content) // 4

                credits_used = int((actual_input * mult["in"]) + (actual_output * mult["out"]))
                refund_amount = est_credits_needed - credits_used
                if refund_amount != 0:
                    def refund_postflight_nonstream():
                        supabase.rpc('deduct_user_credits', {
                            'p_user_id': user_id,
                            'p_credits_needed': -refund_amount
                        }).execute()
                    try:
                        await asyncio.to_thread(refund_postflight_nonstream)
                    except Exception as e:
                        print(f"Failed to issue refund: {e}")

                wallet = await _get_user_wallet(user_id)
                if wallet:
                    resp_json["credits_status"] = {
                        "daily": wallet.get("current_daily_pool", 0),
                        "subscription": wallet.get("subscription_credits", 0),
                        "topup": wallet.get("topup_credits", 0),
                    }
                return JSONResponse(status_code=200, content=resp_json)

    return await proxy_request()
