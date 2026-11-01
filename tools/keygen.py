"""[v94] Ключи для загрузчика: python3 tools/keygen.py [ключ ...]
Без аргументов - создаёт случайный ключ. Добавляет FNV-1a 32 хэш ключа в keys.txt (сами ключи в репозиторий не попадают).
Раздай ключ; в экзекуторе: getgenv().Key = "<ключ>" перед loadstring. Пустой / отсутствующий keys.txt = без ключа."""
import sys, secrets, string
def fnv(s):
    h = 2166136261
    for b in s.encode():
        h ^= b
        h = (h * 16777619) % 2**32
    return '%08x' % h
keys = sys.argv[1:] or [''.join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(20))]
with open('keys.txt', 'a') as f:
    for k in keys:
        f.write(fnv(k) + '\n')
        print(k, '->', fnv(k))
