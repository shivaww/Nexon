# Get a Free API Key (Self-Hosted, via Kaggle)

No API key yet? You can run a free model yourself on Kaggle's free GPUs and
point this app at it. Takes about 10 minutes to set up.

## 1. Create a Kaggle account

- Sign up free at kaggle.com
- Verify your phone number when prompted — Kaggle requires this before it
  will let you use GPUs, even on the free tier.

## 2. Create a notebook and turn on GPUs

- Kaggle.com → **Create** → **New Notebook**
- Open the settings panel on the right → **Accelerator** → select **GPU T4 x2**

## 3. Add the scripts

- Download [scripts.zip] and unzip it.
- For each `.py` file (`01_...`, `02_...`, `03_...`, `04_...`), paste its
  contents into its own new code cell in the notebook, in that order.

## 4. Run it

- Run cells 1, 2, and 3 one at a time (each takes a few minutes — they're
  downloading files).
- Run cell 4 last. It loads the model onto both GPUs and connects a public
  tunnel. When it finishes you'll see:
  ```
  Base URL : https://xxxx-xxxx-xxxx.trycloudflare.com/v1
  API key  : a1b2c3...
  ```
- Copy both of those into this app's provider settings.

## 5. Keep it running without babysitting your phone

This is the important part. Don't just leave the notebook running in your
browser tab and lock your phone — Kaggle's interactive session (what you get
from clicking the individual "Run" arrows) disconnects after a period of
inactivity, and Android will often kill a backgrounded browser tab anyway.

Instead, once you've confirmed the cells work:

- Click **Save Version** (top right) → choose **Save & Run All (Commit)**.
- Double check GPU T4 x2 is still selected in Settings first.
- This runs your notebook as a background job on Kaggle's own servers. It
  keeps going even if you fully close the browser, lock your phone, or switch
  apps — there's no inactivity timeout on a committed run.
- You can check on it anytime from the notebook's **Output**/version log tab
  — the Base URL and API key will be printed there, viewable without needing
  the tab open.

## 6. Limits to know about

- Kaggle's free GPU quota is about 30 hours/week, and each run (session or
  committed version) is capped around 9–12 hours before it's stopped
  automatically.
- **The Base URL and API key are different every time you start a new run** —
  the tunnel address and the key are freshly generated each time. You'll need
  to come back and update this app's settings after each restart.

## Optional: watching it run live instead of using Commit

If you want to babysit the first run interactively rather than jumping
straight to Commit:

- On phones with a floating/pop-up window feature (e.g. Samsung: long-press
  the browser in Recent Apps → **Open in pop-up view**; similar features
  exist on other Android skins under names like "Floating window"), or by
  using split-screen, you can keep the tab visibly active while using other
  apps — Android is much less likely to kill something that's still on
  screen.
- Also worth doing: Android Settings → Apps → your browser → Battery →
  set to **Unrestricted**. This affects background-kill behavior more than
  window mode does on its own.
- None of this is necessary if you just use **Save & Run All (Commit)** from
  step 5 — that keeps running on Kaggle's servers regardless of what your
  phone does.
