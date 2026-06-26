import re

with open('lib/main.dart', 'r') as f:
    content = f.read()

# Update system prompt
prompt_pattern = r'("  Polish: bars rx=4.*?)(?=if \(_agenticEnabled\))'

new_prompt = r'''"  Typography: Title 20px 600w, Axis 13px 400w, Labels 12px 500w, Tooltips 12px monospace\n"
            "  Layout: Container 20px padding, 1px border, 8px radius. Chart area: 12px top, 16px right, 32px bottom, 40px left. Legend gap 16px. Min-height 320px, max 600px\n"
            "  Bar Chart: 4px top radius, opacity 1.0 (hover +0.15), 20% group spacing. Gridlines 0.5px opacity 0.6\n"
            "  Line Chart: Stroke 2px rounded caps/joins. Points 3.5px radius (hover 5px). Fill opacity 0.08. Gridlines 0.5px opacity 0.5\n"
            "  Scatter Chart: Points 4.5px radius (hover 6px). Stroke 1px white. Trend lines 1.5px dashed opacity 0.5. Gridlines 0.5px opacity 0.4\n"
            "  Animations: Load 200-400ms cubic-bezier, Hover 120-150ms ease-out\n"
            "  IMPORTANT: SVGs MUST be strictly enclosed with `<svg>` and `</svg>` tags.\n"
            "- Bar/Pie/Line: ```chart {\"type\":\"bar\",\"title\":\"...\",\"data\":[{\"label\":\"...\",\"value\":10,\"color\":\"#6C8EF5\"}]}\n"
            "- Interactive: ```html / ```javascript / ```react / ```artifact\n\n"
            "CRITICAL DIRECTIVE ON VISUALS: You MUST proactively and autonomously generate diagrams or charts whenever discussing data, comparisons, architectures, flows, math, physics, or complex concepts. Do NOT wait for the user to ask. Use rich colors, professional styling, and keep text concise. ALWAYS include the closing </svg> tag.\n\n";

        '''

content = re.sub(prompt_pattern, new_prompt, content, flags=re.DOTALL)

with open('lib/main.dart', 'w') as f:
    f.write(content)

