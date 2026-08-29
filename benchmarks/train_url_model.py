import os, re, json, math, urllib.request, urllib.parse, ipaddress
from collections import Counter

import numpy as np
import pyarrow.parquet as pq
from scipy.sparse import csr_matrix, hstack
from sklearn.linear_model import SGDClassifier, LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import accuracy_score, precision_recall_fscore_support, confusion_matrix, roc_auc_score
from sklearn.model_selection import train_test_split

BASE='https://huggingface.co/datasets/phreshphish/phreshphish/resolve/main/data/'
FILES={'train':'train-000.parquet','test':'test-000.parquet'}
N_HASH=32768
SUSP=('login','signin','verify','verification','secure','security','account','auth','oauth','password','billing','payment','wallet','support','update','confirm','recover','session')

def download(name):
    fn=FILES[name]
    if not os.path.exists(fn):
        url=BASE+fn+'?download=true'
        print('download',url,flush=True)
        urllib.request.urlretrieve(url,fn)
    return fn

def normalize_url(u):
    u=(u or '').strip()
    if not re.match(r'^https?://',u,re.I): u='http://'+u
    try:
        p=urllib.parse.urlsplit(u)
        host=(p.hostname or '').encode('idna','ignore').decode('ascii','ignore').lower()
        port=f':{p.port}' if p.port else ''
        path=urllib.parse.quote(urllib.parse.unquote(p.path or '/'),safe="/%:@-._~!$&'()*+,;=")
        query=urllib.parse.quote(urllib.parse.unquote(p.query or ''),safe='=&%:@-._~!$\'()*+,;/?')
        out=f'{(p.scheme or "http").lower()}://{host}{port}{path}'
        if query: out+='?'+query
        return out.lower()
    except Exception:
        return u.lower()

def fnv1a(s):
    h=2166136261
    for ch in s:
        h ^= ord(ch) & 0xff
        h = (h * 16777619) & 0xffffffff
    return h

def hashed_matrix(urls):
    indptr=[0]; indices=[]; data=[]
    for raw in urls:
        s='^'+normalize_url(raw)+'$'
        c=Counter()
        for n in (3,4,5):
            for i in range(max(0,len(s)-n+1)):
                c[fnv1a(s[i:i+n]) % N_HASH]+=1.0
        norm=math.sqrt(sum(v*v for v in c.values())) or 1.0
        for k,v in sorted(c.items()):
            indices.append(k); data.append(v/norm)
        indptr.append(len(indices))
    return csr_matrix((np.asarray(data,dtype=np.float32),np.asarray(indices,dtype=np.int32),np.asarray(indptr,dtype=np.int32)),shape=(len(urls),N_HASH),dtype=np.float32)

def entropy(s):
    if not s:return 0.0
    c=Counter(s); n=len(s)
    return -sum((v/n)*math.log2(v/n) for v in c.values())

def lexical_one(raw):
    u=normalize_url(raw)
    try:p=urllib.parse.urlsplit(u)
    except Exception:p=urllib.parse.urlsplit('http://invalid/')
    host=p.hostname or ''
    path=p.path or ''
    q=p.query or ''
    labels=[x for x in host.split('.') if x]
    ip=0
    try: ipaddress.ip_address(host); ip=1
    except Exception: pass
    port_nonstd=int(bool(p.port and p.port not in (80,443)))
    userinfo=int('@' in (p.netloc or '').split(host)[0])
    susp_host=sum(host.count(k) for k in SUSP)
    susp_all=sum(u.count(k) for k in SUSP)
    enc=u.count('%'); digits=sum(ch.isdigit() for ch in u); alpha=sum(ch.isalpha() for ch in u)
    return [
      len(u),len(host),len(path),len(q),host.count('.'),host.count('-'),u.count('-'),digits/max(len(u),1),
      enc/max(len(u),1),u.count('@'),u.count('_'),u.count('/'),max(len(labels)-2,0),path.count('/'),q.count('&')+bool(q),
      entropy(host),entropy(u),ip,int(host.startswith('xn--') or '.xn--' in host),port_nonstd,int(p.scheme=='https'),userinfo,
      susp_host,susp_all,max([len(x) for x in labels] or [0]),len(labels[-1]) if labels else 0,
      int('%25' in u),int('redirect' in q or 'continue=' in q or 'next=' in q or 'url=' in q),
      sum(1 for ch in host if ch.isdigit())/max(len(host),1), alpha/max(len(u),1),
      int(len(u)>120),int(len(u)>200),int(host.count('-')>=3),int(len(labels)>=5)
    ]

def lexical_matrix(urls): return np.asarray([lexical_one(u) for u in urls],dtype=np.float32)

def load_parquet(kind):
    fn=download(kind)
    t=pq.read_table(fn,columns=['url','label']).to_pydict()
    urls=[str(x) for x in t['url']]
    y=np.asarray([1 if str(x).lower()=='phish' else 0 for x in t['label']],dtype=np.int8)
    print(kind,'rows',len(urls),'phish',int(y.sum()),'benign',int((1-y).sum()),flush=True)
    return urls,y

def met(y,p):
    pr=(p>=0.5).astype(int); tn,fp,fn,tp=confusion_matrix(y,pr,labels=[0,1]).ravel()
    precision,recall,f1,_=precision_recall_fscore_support(y,pr,average='binary',zero_division=0)
    return {'accuracy':float(accuracy_score(y,pr)),'precision':float(precision),'recall':float(recall),'f1':float(f1),'auc':float(roc_auc_score(y,p)),'tp':int(tp),'tn':int(tn),'fp':int(fp),'fn':int(fn)}

def main():
    tr_u,tr_y=load_parquet('train'); te_u,te_y=load_parquet('test')
    Xh=hashed_matrix(tr_u); Xl=lexical_matrix(tr_u)
    scaler=StandardScaler().fit(Xl)
    Xls=scaler.transform(Xl)
    char=SGDClassifier(loss='log_loss',alpha=2e-6,max_iter=80,tol=1e-4,class_weight='balanced',random_state=42,average=True)
    lex=LogisticRegression(C=1.5,max_iter=800,class_weight='balanced',solver='liblinear')
    char.fit(Xh,tr_y); lex.fit(Xls,tr_y)
    del Xh,Xl,Xls
    th=hashed_matrix(te_u); tl=scaler.transform(lexical_matrix(te_u))
    pc=char.predict_proba(th)[:,1]; pl=lex.predict_proba(tl)[:,1]
    # blend selected on robustness rather than overfitting a single shard
    pb=0.78*pc+0.22*pl
    result={'dataset':'PhreshPhish v1.0.1','train_file':FILES['train'],'test_file':FILES['test'],'train_rows':len(tr_u),'test_rows':len(te_u),'char':met(te_y,pc),'lexical':met(te_y,pl),'blend':met(te_y,pb)}
    print('URL_MODEL_RESULT_BEGIN'); print(json.dumps(result,indent=2,sort_keys=True)); print('URL_MODEL_RESULT_END')
    export={
      'version':'phresh-url-v1','n_hash':N_HASH,'ngrams':[3,4,5],
      'char_coef':[round(float(x),7) for x in char.coef_[0]],'char_intercept':round(float(char.intercept_[0]),7),
      'lex_coef':[round(float(x),7) for x in lex.coef_[0]],'lex_intercept':round(float(lex.intercept_[0]),7),
      'lex_mean':[round(float(x),7) for x in scaler.mean_], 'lex_scale':[round(float(x),7) for x in scaler.scale_],
      'blend':[0.78,0.22], 'test_metrics':result['blend']
    }
    with open('url_model_export.json','w') as f: json.dump(export,f,separators=(',',':'))
    print('export_bytes',os.path.getsize('url_model_export.json'),flush=True)

if __name__=='__main__': main()
