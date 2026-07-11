import re

with open('/data/data/com.termux/files/home/projects/termux_forge/lib/main.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Define the start and end of the block we want to replace
start_marker = '        String systemPromptText =\n            "Date: $currentDateStr. Use current-year data unless asked otherwise.\\n\\n"'
end_marker = '            "CRITICAL DIRECTIVE ON VISUALS: You MUST proactively generate ```chart blocks whenever discussing data, comparisons, metrics, statistics, or trends. Use ```svg ONLY for non-graph diagrams (flowcharts, mind maps, architecture, illustrations). NEVER use SVG for charts. ALWAYS include the closing </svg> tag for SVGs.\\n";'

if start_marker in content and end_marker in content:
    start_idx = content.find(start_marker)
    end_idx = content.find(end_marker) + len(end_marker)
    
    # We will replace the entire block with dynamic dart string building
    new_block = """        String systemPromptText =
            "Date: $currentDateStr. Use current-year data unless asked otherwise.\\n\\n"
            "Render via markdown code blocks:\\n"
            "- LaTeX: \\\\[ ... \\\\] or \\\\( ... \\\\)\\n";

        if (_svgVisualsEnabled) {
          systemPromptText +=
              "- SVG (ONLY for non-graph diagrams like flowcharts, architecture, illustrations): ```svg\\n"
              "  Root: width=\\"100%\\" viewBox=\\"0 0 800 450\\" preserveAspectRatio=\\"xMidYMid meet\\"\\n"
              "  IMPORTANT: SVGs MUST be strictly enclosed with `<svg>` and `</svg>` tags.\\n"
              "  NEVER use SVG for charts, graphs, or mind maps. Use ```chart instead.\\n\\n";
        }

        systemPromptText +=
            "- CHARTS (bar, line, pie, scatter, area, radar, histogram, heatmap, bubble, gantt, gauge, donut, stacked, cartesian, mindmap): ```chart\\n"
            "  Simple line-based format. LLM passes only values. Examples:\\n\\n"
            "  BAR/GROUPED BAR:\\n"
            "  type: bar\\n"
            "  title: Revenue by Quarter\\n"
            "  range: 0-100\\n"
            "  labels: Q1, Q2, Q3, Q4\\n"
            "  series: Revenue = 45, 67, 89, 52\\n"
            "  series: Costs = 30, 45, 60, 40\\n\\n"
            "  STACKED BAR:\\n"
            "  type: stacked\\n"
            "  title: Stack Example\\n"
            "  labels: Q1, Q2, Q3\\n"
            "  series: A = 30, 40, 50\\n"
            "  series: B = 20, 30, 10\\n\\n"
            "  LINE/CURVE (single or multi-series):\\n"
            "  type: line\\n"
            "  title: Growth Trend\\n"
            "  labels: Jan, Feb, Mar, Apr\\n"
            "  series: Users = 100, 250, 400, 800\\n\\n"
            "  AREA CHART:\\n"
            "  type: area\\n"
            "  title: Traffic\\n"
            "  labels: Mon, Tue, Wed\\n"
            "  series: Visits = 500, 800, 650\\n\\n"
            "  PIE/DONUT (shorthand — just label: value):\\n"
            "  type: pie\\n"
            "  title: Market Share\\n"
            "  Android: 45\\n"
            "  iOS: 30\\n"
            "  Web: 25\\n\\n"
            "  SCATTER:\\n"
            "  type: scatter\\n"
            "  title: Distribution\\n"
            "  labels: A, B, C, D, E\\n"
            "  series: Points = 10, 25, 15, 40, 30\\n\\n"
            "  RADAR/SPIDER:\\n"
            "  type: radar\\n"
            "  title: Skills\\n"
            "  labels: Speed, Power, Defense, Agility, Stamina\\n"
            "  series: Player A = 80, 65, 90, 70, 85\\n"
            "  series: Player B = 60, 80, 70, 90, 75\\n\\n"
            "  HISTOGRAM:\\n"
            "  type: histogram\\n"
            "  title: Score Distribution\\n"
            "  labels: 0-20, 21-40, 41-60, 61-80, 81-100\\n"
            "  series: Frequency = 5, 12, 25, 18, 8\\n\\n"
            "  HEATMAP:\\n"
            "  type: heatmap\\n"
            "  title: Activity\\n"
            "  xlabels: Mon, Tue, Wed\\n"
            "  ylabels: Morning, Afternoon, Evening\\n"
            "  row: 3, 7, 5\\n"
            "  row: 8, 4, 9\\n"
            "  row: 2, 6, 1\\n\\n"
            "  BUBBLE:\\n"
            "  type: bubble\\n"
            "  title: Market Size\\n"
            "  labels: Tech, Health, Finance\\n"
            "  series: Size = 80, 45, 120\\n\\n"
            "  GANTT/TIMELINE:\\n"
            "  type: gantt\\n"
            "  title: Project Plan\\n"
            "  task: Design = 0, 3\\n"
            "  task: Develop = 2, 7\\n"
            "  task: Test = 6, 9\\n"
            "  task: Deploy = 8, 10\\n\\n"
            "  GAUGE/PROGRESS:\\n"
            "  type: gauge\\n"
            "  title: CPU Usage\\n"
            "  value: 73\\n"
            "  max: 100\\n"
            "  label: percent\\n\\n"
            "  CARTESIAN/GEOMETRY (for drawing shapes, polygons, points on a coordinate plane):\\n"
            "  type: cartesian\\n"
            "  title: Triangle ABC\\n"
            "  range: -10-10\\n"
            "  series: Triangle = 2,3, 6,7, 4,1, 2,3\\n"
            "  series: Point A = 2,3\\n\\n"
            "  MINDMAP/TREE:\\n"
            "  type: mindmap\\n"
            "  title: Project Plan\\n"
            "  node: 1 = Root\\n"
            "  node: 2 = Branch A\\n"
            "  node: 3 = Branch B\\n"
            "  edge: 1 -> 2\\n"
            "  edge: 1 -> 3\\n\\n"
            "  RULES: Use ```chart for ALL graphs/charts. Use simple format above. range: min-max is optional. Keep it simple. Never write full code for charts.\\n";

        if (_artifactsEnabled) {
          systemPromptText +=
              "- Artifacts for complete/long outputs: use fenced blocks so the app renders them as files.\\n"
              "  Use ```html for complete HTML pages, ```markdown for essays/guides/reports, ```docx for Word-style documents, and language fences like ```python/```dart/```js for complete scripts or files.\\n"
              "  If the answer is long, a complete file, an essay, a guide, a report, or a full runnable script, put it in one artifact block instead of inline chat text. Use inline code only for small snippets.\\n"
              "- Interactive: ```html / ```javascript / ```react / ```artifact\\n"
              "- Microsoft Word Document: ```docx\\n"
              "  title: Document Title\\n"
              "  subtitle: Optional Subtitle\\n"
              "  # Content in clean markdown\\n"
              "  ## Section Heading\\n"
              "  This is a paragraph.\\n"
              "  - Bullet item\\n"
              "  > Callout block\\n"
              "  | Table Header | Col |\\n"
              "  |---|---|\\n"
              "  | Cell | Cell |\\n"
              "  ```\\n\\n";
        }

        if (_svgVisualsEnabled) {
          systemPromptText +=
              "CRITICAL DIRECTIVE ON VISUALS: You MUST proactively generate ```chart blocks whenever discussing data, comparisons, metrics, statistics, or trends. Use ```svg ONLY for non-graph diagrams (flowcharts, mind maps, architecture, illustrations). NEVER use SVG for charts. ALWAYS include the closing </svg> tag for SVGs.\\n";
        } else {
          systemPromptText +=
              "CRITICAL DIRECTIVE ON VISUALS: You MUST proactively generate ```chart blocks whenever discussing data, comparisons, metrics, statistics, or trends. NEVER use SVG for charts.\\n";
        }"""
    
    new_content = content[:start_idx] + new_block + content[end_idx:]
    with open('/data/data/com.termux/files/home/projects/termux_forge/lib/main.dart', 'w', encoding='utf-8') as f:
        f.write(new_content)
    print("Patched successfully")
else:
    print("Could not find markers")
