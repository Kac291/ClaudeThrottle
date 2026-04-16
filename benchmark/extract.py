#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Dump user/assistant turns sequentially for manual review."""
import json, sys, io

# Force UTF-8 stdout on Windows
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    entries = [json.loads(l) for l in f if l.strip()]

def get_text(msg):
    c = msg.get('content')
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return '\n'.join(b.get('text','') for b in c if isinstance(b, dict) and b.get('type')=='text')
    return ''

turns = []
for e in entries:
    t = e.get('type')
    if t == 'user':
        m = e.get('message', {})
        # skip tool_result-only user messages
        c = m.get('content')
        if isinstance(c, list) and c and all(isinstance(b, dict) and b.get('type')=='tool_result' for b in c):
            continue
        txt = get_text(m)
        if txt:
            turns.append(('U', txt))
    elif t == 'assistant':
        m = e.get('message', {})
        txt = get_text(m)
        if txt.strip():
            turns.append(('A', txt))

# Merge consecutive same-role
merged = []
for r, t in turns:
    if merged and merged[-1][0] == r:
        merged[-1] = (r, merged[-1][1] + '\n' + t)
    else:
        merged.append([r, t])

for i, (r, t) in enumerate(merged):
    print(f"\n\n========== #{i:03d} {r} ==========")
    print(t)
