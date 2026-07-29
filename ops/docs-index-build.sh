#!/usr/bin/env bash
# ОГЛАВЛЕНИЕ РЕПОЗИТОРИЯ (29.07, заказ Антона: «единый файл-оглавление всего репозитория, с указанием
# ВСЕХ документов и их назначением, рядом статус, дата создания, дата актуализации, дата последней
# правки»).
#
# ЧТО СОБИРАЕТСЯ МАШИНОЙ, А ЧТО ЧЕЛОВЕКОМ — граница проведена намеренно:
#   создан / последняя правка   git, без вариантов: первый и последний коммит файла;
#   назначение                  первая осмысленная строка документа (можно переопределить в мета-файле);
#   статус                      мета-файл; по умолчанию выводится из пути (спринты — архив и т.п.);
#   АКТУАЛИЗИРОВАН              ТОЛЬКО мета-файл, и это принципиально.
#
# ПОЧЕМУ «актуализирован» нельзя брать из git. Правка файла означает, что его ТРОГАЛИ, а не что его
# СВЕРИЛИ с реальностью. Документ можно поправить в одном абзаце, оставив соседний врущим; и наоборот —
# документ, которого не касались месяц, может быть верен целиком. Если подставить сюда дату коммита,
# колонка станет вторым столбцом «последняя правка» и будет создавать ложное чувство проверенности.
# Поэтому пусто = «не подтверждалась»: честное «не знаю» вместо красивой даты.
#
# Мета-файл: docs/INDEX-meta.json  {"путь": {"purpose": "...", "status": "...", "checked": "YYYY-MM-DD"}}
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
python3 - "$@" <<'PY'
import json, pathlib, re, subprocess, sys, datetime

REPO = pathlib.Path('.')
# ⚠️ ПЕРЕНОСИМОСТЬ (29.07, «аналогично по всем репозиториям»): в репозитории без каталога `docs/`
# оглавление кладётся в корень. Ничего больше от структуры проекта скрипт не ждёт — только git.
_D = pathlib.Path('docs') if pathlib.Path('docs').is_dir() else pathlib.Path('.')
META = _D / 'INDEX-meta.json'
OUT  = _D / 'INDEX.md'
meta = json.loads(META.read_text(encoding='utf-8')) if META.exists() else {}

files = [f for f in subprocess.run(['git','ls-files','*.md'],capture_output=True,text=True).stdout.split()
         if not f.startswith('.claude/worktrees/')]

def git_dates(p):
    a = subprocess.run(['git','log','--reverse','--format=%ad','--date=short','--',p],capture_output=True,text=True).stdout.split('\n')[0]
    b = subprocess.run(['git','log','-1','--format=%ad','--date=short','--',p],capture_output=True,text=True).stdout.strip()
    return a or '—', b or '—'

def purpose_of(p):
    if p in meta and meta[p].get('purpose'): return meta[p]['purpose']
    # ⚠️ 29.07: первая версия брала «первую непустую строку» и приносила мусор — разделители
    # `---` из front-matter и одиночные тире. Строка должна быть ПРЕДЛОЖЕНИЕМ: минимум двадцать
    # букв. Иначе колонка «назначение» заполнена, но ничего не сообщает — худший вид пустоты.
    t = pathlib.Path(p).read_text(encoding='utf-8', errors='ignore').splitlines()
    # ⚠️ ШАПКА ТОЧНЕЕ ВСЕГО, если она есть (29.07, при переносе в репозиторий памяти): файлы памяти
    # несут `description:` во front-matter — это назначение, написанное автором явно. Брать вместо
    # него первую строку тела значит игнорировать готовый ответ.
    if t and t[0].strip() == '---':
        for l in t[1:40]:
            if l.strip() == '---': break
            m = re.match(r'\s*description:\s*(.+)', l)
            if m:
                d = m.group(1).strip().strip('"\'')
                if len(re.findall(r'[А-Яа-яA-Za-z]', d)) >= 12:
                    return (d[:95] + '…') if len(d) > 95 else d
    # ⚠️ ЗАГОЛОВОК ТОЧНЕЕ ТЕЛА (29.07, вторая правка). Первая содержательная строка у скиллов и
    # спринтов оказывалась случайной фразой из середины мысли. H1 писался как НАЗВАНИЕ документа —
    # это и есть назначение. Берём его, а тело оставляем запасным вариантом.
    for l in t[:40]:
        if l.startswith('# '):
            h = re.sub(r'^#\s*', '', l).strip()
            h = re.sub(r'^SPRINT-\d+[a-z]?\s*[—:-]?\s*', '', h).strip('« »')
            if len(re.findall(r'[А-Яа-яA-Za-z]', h)) >= 12:
                return (h[:95] + '…') if len(h) > 95 else h
            break
    lead = ''
    in_fm = False
    for i, l in enumerate(t):
        s = l.strip()
        if i == 0 and s == '---': in_fm = True; continue
        if in_fm:
            if s == '---': in_fm = False
            continue
        if not s or s.startswith(('#', '>', '|', '---', '```', '- ', '* ')): continue
        cand = re.sub(r'[*_`\[\]]|\(([^)]*)\)', '', s).strip()
        if len(re.findall(r'[А-Яа-яA-Za-z]', cand)) < 20: continue
        lead = cand
        break
    return (lead[:95] + '…') if len(lead) > 95 else (lead or '—')

def status_of(p):
    if p in meta and meta[p].get('status'): return meta[p]['status']
    if p.startswith('docs/sprints/SPRINT-'): return 'архив спринта'
    if p.startswith('docs/research/'):       return 'исследование'
    if p.startswith('.claude/skills/'):      return 'скилл (живой)'
    if 'proposed' in p or 'draft' in p:      return 'черновик'
    return 'живой'

rows, no_meta = [], []
for p in sorted(files):
    created, edited = git_dates(p)
    checked = (meta.get(p) or {}).get('checked') or '—'
    if p not in meta: no_meta.append(p)
    rows.append((p, purpose_of(p), status_of(p), created, checked, edited))

today = subprocess.run(['date','-u','+%Y-%m-%d'],capture_output=True,text=True).stdout.strip()
head = f"""# Оглавление репозитория

Все документы репозитория одним списком: назначение, статус, когда создан, когда в последний раз
**подтверждалась актуальность** и когда файл правился. Собирается машиной — `bash ops/docs-index-build.sh`,
поэтому не устаревает молча. Собрано: {today}, документов: {len(rows)}.

⚠️ **«Актуализирован» и «последняя правка» — РАЗНЫЕ вещи, и колонки намеренно две.** Правка означает,
что файл трогали; актуализация — что его сверили с реальностью целиком. Документ можно поправить в
одном абзаце, оставив соседний врущим, и наоборот: нетронутый месяц файл может быть полностью верен.
Прочерк в «актуализирован» читается как **«не подтверждалась»** — честное «не знаю» вместо красивой
даты, которую подставил бы git.

Как заполнять: `{META}` — `{{"путь": {{"purpose": "…", "status": "…", "checked": "ГГГГ-ММ-ДД"}}}}`.
Назначение без записи в мета-файле берётся из первой содержательной строки документа.

| Документ | Назначение | Статус | Создан | Актуализирован | Последняя правка |
|---|---|---|---|---|---|
"""
_pre = '../' if OUT.parent.name == 'docs' else ''
body = '\n'.join(f'| [{p}]({(_pre if not p.startswith("docs/") else "")}{p[5:] if (p.startswith("docs/") and _pre) else p}) | {pu} | {st} | {cr} | {ch} | {ed} |'
                 for p, pu, st, cr, ch, ed in rows)
tail = f"""

## Что этот файл НЕ доказывает

Он показывает расхождения, которые видит машина, и НЕ видит устаревший смысл: абзац про поведение,
изменённое три дня назад, выглядит для него так же, как верный. Колонка «актуализирован» ровно про
это и существует — её ставит человек, прочитав документ, а не скрипт по факту коммита.

**Документов без записи в мета-файле: {len(no_meta)}** — у них назначение выведено из текста, а
актуальность никем не подтверждалась.
"""
OUT.write_text(head + body + tail, encoding='utf-8')
print(f'оглавление собрано: {len(rows)} документов, без мета-записи {len(no_meta)}')
PY
