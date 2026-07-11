import re
import os

with open('/data/data/com.termux/files/home/projects/termux_forge/backend/main.py', 'r') as f:
    code = f.read()

# 1. Update verify_jwt to use asyncio.to_thread
code = code.replace(
    'user_response = supabase.auth.get_user(token)',
    'user_response = await asyncio.to_thread(supabase.auth.get_user, token)'
)

# 2. Make _get_user_wallet async and use to_thread
code = code.replace(
    'def _get_user_wallet(user_id: str) -> dict:',
    'async def _get_user_wallet(user_id: str) -> dict:'
)
code = code.replace(
    'response = supabase.table("user_wallets").select("current_daily_pool, subscription_credits, topup_credits").eq("user_id", user_id).maybe_single().execute()',
    'def fetch():\n            return supabase.table("user_wallets").select("current_daily_pool, subscription_credits, topup_credits").eq("user_id", user_id).maybe_single().execute()\n        response = await asyncio.to_thread(fetch)'
)

# 3. Update all _get_user_wallet calls to await _get_user_wallet
code = code.replace('wallet = _get_user_wallet(user_id)', 'wallet = await _get_user_wallet(user_id)')

# 4. Fix actual_input_tokens calculation to handle images
old_token_calc = '''    # 2. Calculate Exact Input Tokens (Approximation: 1 token = 4 chars)
    messages_str = str(body.get("messages", []))
    actual_input_tokens = max(10, len(messages_str) // 4)'''

new_token_calc = '''    # 2. Calculate Exact Input Tokens (Approximation: 1 token = 4 chars, images ~1000)
    messages = body.get("messages", [])
    total_len = 0
    image_count = 0
    for m in messages:
        content = m.get("content")
        if isinstance(content, str):
            total_len += len(content)
        elif isinstance(content, list):
            for part in content:
                if part.get("type") == "text":
                    total_len += len(part.get("text", ""))
                elif part.get("type") == "image_url":
                    image_count += 1
    actual_input_tokens = max(10, (total_len // 4) + (image_count * 1000))'''
code = code.replace(old_token_calc, new_token_calc)

# 5. Fix deduct_user_credits to use to_thread (pre-flight)
old_deduct = '''        # 3. Atomic Database Deduction (Pre-flight)
        deduct_response = supabase.rpc('deduct_user_credits', {
            'p_user_id': user_id,
            'p_credits_needed': est_credits_needed
        }).execute()'''
new_deduct = '''        # 3. Atomic Database Deduction (Pre-flight)
        def deduct_preflight():
            return supabase.rpc('deduct_user_credits', {
                'p_user_id': user_id,
                'p_credits_needed': est_credits_needed
            }).execute()
        deduct_response = await asyncio.to_thread(deduct_preflight)'''
code = code.replace(old_deduct, new_deduct)

# 6. Fix deduct_user_credits refund 1 (unreachable)
old_refund1 = '''                    # Refund everything if the server is unreachable
                    supabase.rpc('deduct_user_credits', {'p_user_id': user_id, 'p_credits_needed': -est_credits_needed}).execute()'''
new_refund1 = '''                    # Refund everything if the server is unreachable
                    def refund_unreachable():
                        supabase.rpc('deduct_user_credits', {'p_user_id': user_id, 'p_credits_needed': -est_credits_needed}).execute()
                    await asyncio.to_thread(refund_unreachable)'''
code = code.replace(old_refund1, new_refund1)

# 7. Fix deduct_user_credits refund 2 (upstream failed stream)
old_refund2 = '''                    # Refund everything if upstream failed
                    supabase.rpc('deduct_user_credits', {'p_user_id': user_id, 'p_credits_needed': -est_credits_needed}).execute()'''
new_refund2 = '''                    # Refund everything if upstream failed
                    def refund_upstream_failed():
                        supabase.rpc('deduct_user_credits', {'p_user_id': user_id, 'p_credits_needed': -est_credits_needed}).execute()
                    await asyncio.to_thread(refund_upstream_failed)'''
code = code.replace(old_refund2, new_refund2)

# 8. Fix deduct_user_credits refund 3 (post-flight stream)
old_refund3 = '''                        if refund_amount != 0:
                            try:
                                supabase.rpc('deduct_user_credits', {
                                    'p_user_id': user_id,
                                    'p_credits_needed': -refund_amount
                                }).execute()
                            except Exception as e:
                                print(f"Failed to issue refund: {e}")'''
new_refund3 = '''                        if refund_amount != 0:
                            def refund_postflight():
                                supabase.rpc('deduct_user_credits', {
                                    'p_user_id': user_id,
                                    'p_credits_needed': -refund_amount
                                }).execute()
                            try:
                                await asyncio.to_thread(refund_postflight)
                            except Exception as e:
                                print(f"Failed to issue refund: {e}")'''
code = code.replace(old_refund3, new_refund3)

# 9. Fix deduct_user_credits refund 4 (non-stream unreachable)
old_refund4 = '''                except httpx.RequestError:
                    await client.aclose()
                    supabase.rpc('deduct_user_credits', {'p_user_id': user_id, 'p_credits_needed': -est_credits_needed}).execute()
                    raise HTTPException(status_code=503, detail="Upstream AI provider unreachable.")'''
new_refund4 = '''                except httpx.RequestError:
                    await client.aclose()
                    def refund_unreachable_nonstream():
                        supabase.rpc('deduct_user_credits', {'p_user_id': user_id, 'p_credits_needed': -est_credits_needed}).execute()
                    await asyncio.to_thread(refund_unreachable_nonstream)
                    raise HTTPException(status_code=503, detail="Upstream AI provider unreachable.")'''
code = code.replace(old_refund4, new_refund4)

# 10. Fix deduct_user_credits refund 5 (non-stream upstream failed)
old_refund5 = '''                if upstream_response.status_code != 200:
                    error_text = upstream_response.text
                    await client.aclose()
                    supabase.rpc('deduct_user_credits', {'p_user_id': user_id, 'p_credits_needed': -est_credits_needed}).execute()'''
new_refund5 = '''                if upstream_response.status_code != 200:
                    error_text = upstream_response.text
                    await client.aclose()
                    def refund_upstream_failed_nonstream():
                        supabase.rpc('deduct_user_credits', {'p_user_id': user_id, 'p_credits_needed': -est_credits_needed}).execute()
                    await asyncio.to_thread(refund_upstream_failed_nonstream)'''
code = code.replace(old_refund5, new_refund5)

# 11. Fix deduct_user_credits refund 6 (non-stream post-flight)
old_refund6 = '''                if refund_amount != 0:
                    try:
                        supabase.rpc('deduct_user_credits', {
                            'p_user_id': user_id,
                            'p_credits_needed': -refund_amount
                        }).execute()
                    except Exception as e:
                        print(f"Failed to issue refund: {e}")'''
new_refund6 = '''                if refund_amount != 0:
                    def refund_postflight_nonstream():
                        supabase.rpc('deduct_user_credits', {
                            'p_user_id': user_id,
                            'p_credits_needed': -refund_amount
                        }).execute()
                    try:
                        await asyncio.to_thread(refund_postflight_nonstream)
                    except Exception as e:
                        print(f"Failed to issue refund: {e}")'''
code = code.replace(old_refund6, new_refund6)

with open('/data/data/com.termux/files/home/projects/termux_forge/backend/main.py', 'w') as f:
    f.write(code)

print("Backend bugs patched!")
