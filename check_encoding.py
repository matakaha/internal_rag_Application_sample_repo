import chardet

# CSVファイルのエンコーディングを検出
with open('data/raw/redList2012_honyurui.csv', 'rb') as f:
    raw_data = f.read()
    result = chardet.detect(raw_data)
    print(f"検出されたエンコーディング: {result['encoding']}")
    print(f"信頼度: {result['confidence']}")

# 検出されたエンコーディングで読み込んでみる
print("\n最初の5行:")
with open('data/raw/redList2012_honyurui.csv', 'r', encoding=result['encoding']) as f:
    for i, line in enumerate(f):
        if i >= 5:
            break
        print(line.rstrip())
