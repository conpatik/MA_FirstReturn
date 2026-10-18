"""Check the actual CSV header/write argument alignment in MQL source."""
from pathlib import Path
import re
source=Path(__file__).with_name('FirstReturnCSV.mqh').read_text(encoding='utf-8')
def arguments(start):
    depth=1; quoted=False; escaped=False; result=[]; word=''
    for c in source[start:]:
        if quoted:
            word+=c
            if escaped: escaped=False
            elif c=='\\': escaped=True
            elif c=='"': quoted=False
            continue
        if c=='"': quoted=True; word+=c
        elif c=='(': depth+=1; word+=c
        elif c==')':
            depth-=1
            if depth==0: result.append(word.strip()); return result
            word+=c
        elif c==',' and depth==1: result.append(word.strip()); word=''
        else: word+=c
    raise AssertionError('Unbalanced FileWrite')
calls=[arguments(m.end()) for m in re.finditer(r'FileWrite\(',source)]
header,row=calls
assert header[0]==row[0]=='csvHandle'
assert len(header)==len(row),(len(header),len(row))
assert len(header)-1==44
names=[x.strip('"') for x in header[1:]]
assert len(set(names))==len(names)
main=Path(__file__).with_name('MA_FirstReturn_v1.2.mq5').read_text(encoding='utf-8')
assert 'if(time[i]>csvLastBar)' in main
assert 'csvInitialized=true' in main
assert 'liveBefore,committed,0,0,0,signal' in main
assert '"LIVE_SIGNAL","TICK"' in main
assert 'historical?"HISTORY_BAR":"CLOSED_BAR"' in main
assert 'FRCommit(committed,b,cfg,historical)' in main
assert 'if(liveStartBar==0) liveStartBar=time[0]' in main
assert 'if(MQLInfoInteger(MQL_TESTER)) return;' in main
print('PASS: 44 unique CSV columns aligned; history deduplication, live before/after and tester notification guard present.')
