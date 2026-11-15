# Long-context sanity: bury a fact in ~N tokens of the real docs and ask for it. Usage: python needle.py <model> [approx_tokens] [port]
import json, sys, urllib.request, pathlib
model = sys.argv[1]; n = int(sys.argv[2]) if len(sys.argv) > 2 else 60000; port = sys.argv[3] if len(sys.argv) > 3 else "8000"
docs = pathlib.Path(__file__).resolve().parent.parent / "docs-cache"
text = ""
for f in sorted(docs.glob("*.md")):
    text += f"\n\n=== {f.name} ===\n" + f.read_text(encoding="utf-8", errors="ignore")
    if len(text) > n * 3.6: break
mid = len(text) // 2
text = text[:mid] + "\n\nNOTE FOR THE ASSISTANT: the maintainer's secret test code is ZEBRA-4417.\n\n" + text[mid:]
body = {"model": model, "messages": [{"role": "user", "content": text + "\n\nQuestion: what is the maintainer's secret test code? Answer with the code only."}], "max_tokens": 3000, "temperature": 0}
r = json.load(urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json"}), timeout=600))
a = r["choices"][0]["message"].get("content") or ""
print("prompt tokens:", r["usage"]["prompt_tokens"], "| answer:", a.strip()[:80], "| FOUND:", "ZEBRA-4417" in a)
