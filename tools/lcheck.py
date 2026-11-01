# Проверка лимита Luau: не больше 200 одновременно живых локальных в одной функции
import json, subprocess, sys
src = sys.argv[1]
limit = int(sys.argv[2]) if len(sys.argv) > 2 else 200
ast = json.loads(subprocess.run([__import__('os').environ.get('LUAU_DIR', 'luau') + '/luau-ast', src], capture_output=True, text=True).stdout)
funcs = []
def func(fn, loc):
    base = len(fn.get('args', [])) + (1 if fn.get('vararg') else 0)
    m = block(fn['body'], base)
    funcs.append((m, loc))
def scan(node, count):
    m = count
    if isinstance(node, dict):
        t = node.get('type')
        if t == 'AstExprFunction':
            func(node, node.get('location')); return count
        if t == 'AstStatBlock':
            return block(node, count)
        for k, v in node.items():
            if k in ('location',): continue
            m = max(m, scan(v, count))
    elif isinstance(node, list):
        for v in node: m = max(m, scan(v, count))
    return m
def block(b, base):
    count = base; m = base
    for st in b.get('body', []):
        t = st.get('type')
        if t == 'AstStatLocal':
            for v in st.get('values', []): m = max(m, scan(v, count))
            count += len(st['vars'])
        elif t == 'AstStatLocalFunction':
            count += 1; func(st['func'], st['func'].get('location'))
        elif t == 'AstStatFor':
            for k in ('from', 'to', 'step'):
                if st.get(k): m = max(m, scan(st[k], count))
            m = max(m, block(st['body'], count + 1))
        elif t == 'AstStatForIn':
            for v in st.get('values', []): m = max(m, scan(v, count))
            m = max(m, block(st['body'], count + len(st['vars'])))
        else:
            m = max(m, scan(st, count))
        m = max(m, count)
    return m
top = block(ast['root'], 0)
funcs.append((top, 'main chunk'))
funcs.sort(key=lambda x: -x[0])
for c, loc in funcs[:4]: print(f'{c:4d} locals  {loc}')
bad = [f for f in funcs if f[0] > limit]
print('OK' if not bad else f'OVER LIMIT {limit}: {len(bad)}')
sys.exit(1 if bad else 0)
