import json, urllib.request
url='https://huggingface.co/api/datasets/phreshphish/phreshphish/tree/main/benchmark?recursive=false&expand=false'
with urllib.request.urlopen(url, timeout=30) as r:
    data=json.loads(r.read().decode())
for x in data:
    print(x.get('type'), x.get('path'), x.get('size'))
