-- 1. User Wallets Table
CREATE TABLE user_wallets (
    user_id UUID REFERENCES auth.users(id) PRIMARY KEY,
    subscription_credits BIGINT DEFAULT 0,
    topup_credits BIGINT DEFAULT 0,
    plan_tier TEXT DEFAULT 'go',
    monthly_cap BIGINT DEFAULT 16500000,
    daily_base_cap BIGINT DEFAULT 550000,
    billing_cycle_end TIMESTAMPTZ DEFAULT (now() + interval '1 month'),
    current_daily_pool BIGINT DEFAULT 550000,
    last_daily_reset TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable Row Level Security (RLS)
ALTER TABLE user_wallets ENABLE ROW LEVEL SECURITY;

-- Users can only read their own wallet
CREATE POLICY "Users can read own wallet" ON user_wallets
    FOR SELECT USING (auth.uid() = user_id);

-- 2. Transaction Ledger
CREATE TABLE credit_transactions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id),
    model_used TEXT,
    input_tokens INT,
    output_tokens INT,
    credits_deducted BIGINT,
    wallet_source TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE credit_transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read own transactions" ON credit_transactions
    FOR SELECT USING (auth.uid() = user_id);

-- 3. Atomic Deduction Function (Database-level security)
-- This ensures if two requests hit at the same time, they are processed sequentially safely.
CREATE OR REPLACE FUNCTION deduct_user_credits(
    p_user_id UUID,
    p_credits_needed BIGINT
) RETURNS JSON AS $$ DECLARE
    wallet_record user_wallets%ROWTYPE;
    source TEXT;
    missing_credits BIGINT;
BEGIN
    -- Lock the wallet row for the duration of this transaction
    SELECT * INTO wallet_record FROM user_wallets WHERE user_id = p_user_id FOR UPDATE;

    -- 1. Refresh Daily Pool if 24h passed
    IF now() - wallet_record.last_daily_reset >= interval '24 hours' THEN
        DECLARE
            leftover BIGINT;
            new_pool BIGINT;
        BEGIN
            leftover := GREATEST(0, wallet_record.current_daily_pool);
            -- Capped at total available balance (subscription + topup) instead of subscription_credits only,
            -- preventing top-up users from being blocked when subscription reaches 0.
            new_pool := LEAST(wallet_record.daily_base_cap + leftover, wallet_record.subscription_credits + wallet_record.topup_credits);
            
            UPDATE user_wallets SET 
                current_daily_pool = new_pool,
                last_daily_reset = now()
            WHERE user_id = p_user_id;
            
            wallet_record.current_daily_pool := new_pool;
        END;
    END IF;

    -- 2. Circuit Breaker Check (Only check when deducting credits, not during refunds)
    IF p_credits_needed > 0 AND wallet_record.current_daily_pool < p_credits_needed THEN
        RAISE EXCEPTION 'Daily Circuit Breaker Reached. Unused balance preserved for tomorrow.';
    END IF;

    IF p_credits_needed < 0 THEN
        -- Handle Refund
        DECLARE
            refund_amount BIGINT := -p_credits_needed;
            space_in_sub BIGINT := wallet_record.monthly_cap - wallet_record.subscription_credits;
            to_sub BIGINT;
            to_topup BIGINT;
        BEGIN
            -- Add to subscription up to monthly cap, rest to topup
            to_sub := LEAST(refund_amount, space_in_sub);
            to_topup := refund_amount - to_sub;
            
            UPDATE user_wallets SET 
                subscription_credits = subscription_credits + to_sub,
                topup_credits = topup_credits + to_topup,
                current_daily_pool = current_daily_pool + refund_amount
            WHERE user_id = p_user_id;
            source := 'refund';
        END;
    ELSE
        -- 3. Deduct from Monthly Pool
        IF wallet_record.subscription_credits >= p_credits_needed THEN
            UPDATE user_wallets SET 
                subscription_credits = subscription_credits - p_credits_needed,
                current_daily_pool = current_daily_pool - p_credits_needed
            WHERE user_id = p_user_id;
            source := 'subscription';
        ELSE
            -- 4. Dip into Top-Up Wallet
            missing_credits := p_credits_needed - wallet_record.subscription_credits;
            IF wallet_record.topup_credits >= missing_credits THEN
                UPDATE user_wallets SET 
                    subscription_credits = 0,
                    topup_credits = topup_credits - missing_credits,
                    current_daily_pool = current_daily_pool - p_credits_needed
                WHERE user_id = p_user_id;
                source := 'topup';
            ELSE
                RAISE EXCEPTION 'Insufficient credits. Please top up or upgrade.';
            END IF;
        END IF;
    END IF;

    RETURN json_build_object('status', 'success', 'source', source);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
