# Turns 7.2's MISSIONS (exported from the running game with their functions as source text) into plain data
# for the Godot mission engine: godot/assets/missions/missions.json.
# usage: python3 convert_missions.py missions_src.json mdata.json out.json
import json, re, sys, html

src, mdata, out = sys.argv[1:4]
d = json.load(open(src)); md = json.load(open(mdata))

def bb(s):
    if not isinstance(s, str): return s
    s = re.sub(r'<br\s*/?>', '\n', s); s = re.sub(r'<i>', '[i]', s).replace('</i>', '[/i]')
    s = re.sub(r'<b[^>]*>', '[b]', s).replace('</b>', '[/b]')
    s = re.sub(r'<[^>]+>', '', s); return html.unescape(s)

def fn(v): return v['__fn'] if isinstance(v, dict) and '__fn' in v else (v if isinstance(v, str) else '')

NUM = r'(-?[\d.]+)'
def coord(expr):
    """'595+rnd(-8,8)' -> [595, -8, 8]; 'rnd(-6,6)' -> [0,-6,6]; '60' -> [60,0,0]"""
    expr = expr.replace(' ', '')
    m = re.fullmatch(NUM + r'?\+?rnd\(' + NUM + ',' + NUM + r'\)', expr)
    if m: return [float(m.group(1) or 0), float(m.group(2)), float(m.group(3))]
    m = re.fullmatch(NUM, expr)
    if m: return [float(m.group(1)), 0, 0]
    return [0, 0, 0]

def split_args(s):
    out, depth, cur = [], 0, ''
    for ch in s:
        if ch == ',' and depth == 0: out.append(cur); cur = ''; continue
        depth += ch in '(['; depth -= ch in ')]'; cur += ch
    out.append(cur); return out

def spawns(code, kind):
    """every spawnEnemy(...) / spawnPickup(...) call, with its loop count"""
    res = []
    loop = re.search(r'for\(let k=0;k<(\d+);k\+\+\)', code)
    count = int(loop.group(1)) if loop else 1
    if "forEach(m=>" in code:          # kismet: one of each listed type
        types = re.findall(r"'(\w+)'", code.split('forEach')[0])
        for t in types: res.append({'mob': t, 'n': 1, 'x': [-24, -14, 14], 'z': [-14, -12, 12], 'elite': .3})
        return res
    for m in re.finditer(r'spawn' + kind + r'\((.+?)\)(?=;|\})', code):
        a = split_args(m.group(1))
        first = a[0].strip()
        e = {'n': count if loop and loop.start() < m.start() else 1, 'x': coord(a[1]), 'z': coord(a[2])}
        if first.startswith('pick('): e['pool'] = re.findall(r"'(\w+)'", first)
        else: e['mob' if kind == 'Enemy' else 'item'] = first.strip("'")
        res.append(e)
    return res

def effects(code):
    e = {}
    for k, pat in (('xp', r'gainXP\((\d+)\)'), ('lira', r'S\.lira\+=(\d+)'), ('extra', r'S\.mExtra=(\d+)'),
                   ('mh', r'S\.maxhp\+=(\d+)'), ('mm', r'S\.maxmana\+=(\d+)')):
        m = re.search(pat, code)
        if m: e[k] = int(m.group(1))
    w = re.findall(r"giveWeapon\('(\w+)'", code) + re.findall(r"S\.weapons\.push\('(\w+)'\)", code)
    if w: e['weapons'] = list(dict.fromkeys(w))
    t = re.findall(r"teach\('([^']+)'\)", code)
    if t: e['teach'] = t
    toasts = [bb(x) for x in re.findall(r"toast\((['\"])(.*?)\1[,)]", code)]
    msgs = [bb(m[1]) for m in re.findall(r"toast\((['\"])((?:\\.|(?!\1).)*)\1", code)]
    msgs = [m.replace("\\'", "'") for m in msgs if '+' not in m[:2]]
    if msgs: e['msg'] = msgs[-1]
    return e

def phase(p):
    ops = []
    for m in re.finditer(r"PHASE\.(\w+)\(e(?:,([^)]*))?\)", fn(p['fn'])):
        args = [x.strip().strip("'") for x in (m.group(2) or '').split(',') if x.strip()]
        ops.append([m.group(1)] + [float(x) if re.fullmatch(r'[\d.]+', x) else x for x in args])
    return {'at': p['at'], 'bn': p.get('bn', ''), 'sub': p.get('sub', ''), 'ops': ops}

missions = []
for m in d['MISSIONS']:
    M = {k: m[k] for k in ('id', 'unit', 'title', 'xp') if k in m}
    M['phrase'] = m.get('phrase')
    if m.get('intro'): M['intro'] = {'name': m['intro']['name'], 'lines': [bb(x) for x in m['intro']['lines']]}
    M['pickups'] = spawns(fn(m.get('spawn')), 'Pickup') if m.get('spawn') else []
    M['reward'] = effects(fn(m.get('reward')))
    st = fn(m.get('start'))
    if st:
        M['start'] = {'teach': re.findall(r"teach\('([^']+)'\)", st), 'dawn': 'skyDawn(true)' in st}
    steps = []
    for s in m['steps']:
        S = {k: (bb(v) if isinstance(v, str) else v) for k, v in s.items() if not isinstance(v, dict) and k not in ('timeFn', 'fast', 'late', 'after', 'spawnMobs', 'phases')}
        if s.get('spawnMobs'): S['mobs'] = spawns(fn(s['spawnMobs']), 'Enemy')
        if s.get('timeFn'):
            tm = re.search(r'Math\.round\(([\d.]+)\+d/([\d.]+)\)', fn(s['timeFn']))
            S['time'] = [float(tm.group(1)), float(tm.group(2))] if tm else [20, 7]
        if s.get('fast'): S['fast'] = effects(fn(s['fast']))
        if s.get('late'): S['late'] = effects(fn(s['late']))
        if s.get('phases'): S['phases'] = [phase(p) for p in s['phases']]
        if s.get('after'): S['after'] = re.findall(r"banner\('([^']+)'", fn(s['after']))
        if s['t'] == 'choice':
            S['opts'] = [{k: bb(v) for k, v in o.items()} for o in s['opts']]
        steps.append(S)
    M['steps'] = steps
    missions.append(M)

json.dump({'missions': missions, 'gates': md['GATES'], 'zspawn': md['ZSPAWN'], 'zname': md['ZNAME'],
           'weapons': md['WEAPONS'], 'enemies': {k: {a: b for a, b in v.items() if a != 'mk' and not str(b).startswith('function')} for k, v in d['ENEMY'].items()}},
          open(out, 'w'), ensure_ascii=False, indent=1)
print(len(missions), 'missions')
