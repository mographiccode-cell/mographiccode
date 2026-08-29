import json,re,math,urllib.parse,urllib.request,ipaddress,time
from concurrent.futures import ThreadPoolExecutor,as_completed
import numpy as np
from phishlens_benchmark import build_cases, BRANDS
from train_url_model import normalize_url, fnv1a, lexical_one, N_HASH

API='https://sonje03-phishlens-backend.hf.space/analyse'
URL_RE=re.compile(r'https?://[^\s<>"\']+',re.I)
OFFICIAL_URL={k:v[0].lower() for k,v in BRANDS.items()}
OFFICIAL_SENDER={k:v[1].split('@')[-1].lower() for k,v in BRANDS.items()}

def sigmoid(x):
    if x>=0:return 1/(1+math.exp(-x))
    e=math.exp(x);return e/(1+e)

def load_model():
    with open('url_model_export.json') as f:return json.load(f)
M=None

def hash_prob(u):
    s='^'+normalize_url(u)+'$'; counts={}
    for n in (3,4,5):
        for i in range(max(0,len(s)-n+1)):
            k=fnv1a(s[i:i+n])%M['n_hash'];counts[k]=counts.get(k,0)+1.0
    norm=math.sqrt(sum(v*v for v in counts.values())) or 1.0
    z=M['char_intercept']
    w=M['char_coef']
    for k,v in counts.items(): z += w[k]*(v/norm)
    return sigmoid(z)

def lex_prob(u):
    x=lexical_one(u);z=M['lex_intercept']
    for i,v in enumerate(x):
        s=M['lex_scale'][i] or 1.0
        z+=M['lex_coef'][i]*((v-M['lex_mean'][i])/s)
    return sigmoid(z)

def host_of(u):
    try:return (urllib.parse.urlsplit(normalize_url(u)).hostname or '').lower()
    except:return ''

def regdom(host):
    parts=[x for x in host.split('.') if x]
    if len(parts)<=2:return '.'.join(parts)
    cc2={'co.uk','com.au','co.jp','com.br','co.in','com.sa','com.mx','co.nz','com.sg','com.tr','com.cn'}
    tail='.'.join(parts[-2:])
    return '.'.join(parts[-3:]) if tail in cc2 and len(parts)>=3 else tail

def is_official_host(host,brand):
    off=OFFICIAL_URL.get(brand,'')
    return host==off or host.endswith('.'+off)

def nested_hosts(u):
    out=[]
    try:
      p=urllib.parse.urlsplit(normalize_url(u));q=urllib.parse.parse_qs(p.query)
      for vals in q.values():
        for v in vals:
          cur=v
          for _ in range(2):
            cur=urllib.parse.unquote(cur)
          if cur.startswith(('http://','https://')):out.append(host_of(cur))
    except:pass
    return [x for x in out if x]

def score_url(u,sender_domain=''):
    ml=0.78*hash_prob(u)+0.22*lex_prob(u)
    risk=ml; reasons=[]
    nu=normalize_url(u); p=urllib.parse.urlsplit(nu);host=(p.hostname or '').lower(); netloc=p.netloc.lower()
    try:ipaddress.ip_address(host); risk=max(risk,.93);reasons.append('ip-host')
    except:pass
    if '@' in netloc:risk=max(risk,.98);reasons.append('userinfo-at')
    if host.startswith('xn--') or '.xn--' in host:risk=max(risk,.86);reasons.append('punycode')
    if p.port and p.port not in (80,443):risk=max(risk,.80);reasons.append('nonstandard-port')
    if '%25' in nu:risk=max(risk,.76);reasons.append('double-encoding')
    if len(nu)>180:risk=max(risk,.60);reasons.append('very-long-url')
    nh=nested_hosts(nu)
    if any(regdom(x)!=regdom(host) for x in nh):risk=max(risk,.70);reasons.append('cross-domain-redirect')
    for brand,off in OFFICIAL_URL.items():
      token=brand.replace('microsoft','microsoft').lower()
      if token in host and not is_official_host(host,brand):
        # tracking-like link from a strongly authenticated official sender is suspicious but not automatic phishing
        if sender_domain==OFFICIAL_SENDER.get(brand) and any(is_official_host(x,brand) for x in nh):
          risk=max(risk,.42);reasons.append('external-tracker-to-official')
        else:
          risk=max(risk,.97);reasons.append('brand-domain-mismatch:'+brand)
    # exact official host is strong benign evidence unless URL has a structural hard red flag
    official_any=any(is_official_host(host,b) for b in OFFICIAL_URL)
    hard=any(x in reasons for x in ('ip-host','userinfo-at','punycode','nonstandard-port'))
    if official_any and not hard:risk=min(risk,.18);reasons.append('official-domain')
    return max(0,min(1,risk)),ml,reasons

def email_domain(addr):
    m=re.search(r'@([A-Za-z0-9.-]+)',addr or '')
    return m.group(1).lower().strip('.') if m else ''

def parse_header(text,name):
    m=re.search(r'^'+re.escape(name)+r':\s*(.+)$',text,re.I|re.M)
    return m.group(1).strip() if m else ''

def score_meta(c):
    text=c['text']; sender_dom=email_domain(c.get('sender',''))
    auth=parse_header(text,'Authentication-Results').lower()
    spf='spf=pass' in auth; dkim='dkim=pass' in auth; dmarc='dmarc=pass' in auth
    reply_dom=email_domain(parse_header(text,'Reply-To')); ret_dom=email_domain(parse_header(text,'Return-Path'))
    risk=.28; reasons=[]; trusted_brand=None
    for b,d in OFFICIAL_SENDER.items():
      if sender_dom==d or sender_dom.endswith('.'+d):trusted_brand=b;break
    if trusted_brand and spf and dkim and dmarc:
      risk=.04;reasons.append('authenticated-official-sender')
    elif spf and dkim and dmarc:
      risk=.22;reasons.append('auth-pass-untrusted-domain')
    if reply_dom and regdom(reply_dom)!=regdom(sender_dom):risk=max(risk,.62);reasons.append('reply-to-mismatch')
    if ret_dom and regdom(ret_dom)!=regdom(sender_dom):risk=max(risk,.58);reasons.append('return-path-mismatch')
    if 'spf=fail' in auth and 'dkim=pass' not in auth:risk=max(risk,.72);reasons.append('spf-fail')
    # brand in display name but domain is not official
    frm=parse_header(text,'From').lower()
    for b,d in OFFICIAL_SENDER.items():
      if b in frm and not (sender_dom==d or sender_dom.endswith('.'+d)):
        risk=max(risk,.93);reasons.append('sender-brand-mismatch:'+b)
    return risk,trusted_brand,reasons

def call_text(c):
    payload=json.dumps({'raw_text':c['text'],'sender_email':c['sender']}).encode()
    for a in range(3):
      try:
        req=urllib.request.Request(API,data=payload,headers={'Content-Type':'application/json'},method='POST')
        with urllib.request.urlopen(req,timeout=35) as r:d=json.loads(r.read().decode())
        return float((((d.get('agents') or {}).get('text') or {}).get('phishing_probability') or 0)),True
      except Exception:
        time.sleep(a+1)
    return .5,False

def advanced_predict(c):
    text_score,ok=call_text(c)
    sender_dom=email_domain(c.get('sender',''))
    urls=URL_RE.findall(c['text'])
    url_rows=[score_url(u,sender_dom) for u in urls]
    max_url=max([x[0] for x in url_rows] or [.10]); mean_url=sum(x[0] for x in url_rows)/len(url_rows) if url_rows else .10
    meta,brand,mreasons=score_meta(c)
    hard_reasons=[r for x in url_rows for r in x[2] if r in ('ip-host','userinfo-at','punycode') or r.startswith('brand-domain-mismatch')]
    final=.58*max_url+.14*mean_url+.20*meta+.08*text_score
    if hard_reasons:final=max(final,.91)
    if max_url>=.88:final=max(final,.86)
    # strongly authenticated known sender + only low-risk/official links: neutralize text-model false positives
    if brand and meta<=.06 and max_url<.50:final=min(final,.24)
    # authenticated official sender with an external tracker back to official domain: still safe-ish, but not blindly trusted
    if brand and meta<=.06 and max_url<.68 and not hard_reasons:final=min(final,.44)
    pred='phishing' if final>=.55 else 'safe'
    return {'pred':pred,'risk':final,'text':text_score,'url':max_url,'url_mean':mean_url,'meta':meta,'urls':len(urls),'reasons':sorted(set(hard_reasons+mreasons)),'backend_ok':ok}

def generic_holdout(n=80):
    out=[]
    for i in range(n//2):
      dom=f'portal{i}.northstar-services.example'; sender=f'notify@{dom}'
      url=f'https://{dom}/account/security/activity?utm_source=email&continue=%2Fbilling%2Fhistory&id={i}'
      body=f'From: Northstar Services <{sender}>\nReply-To: {sender}\nReturn-Path: {sender}\nAuthentication-Results: SPF=PASS; DKIM=PASS; DMARC=PASS\nSubject: Security and billing review\n\nA legitimate account notice. Review recent activity at {url}. Never send a password or OTP by email.'
      out.append({'id':f'H-S-{i}','truth':'safe','difficulty':'holdout','sender':sender,'text':body})
    for i in range(n//2):
      atk=f'northstar-verify-{i}.example'; sender=f'notify@{atk}'
      pats=[f'https://portal{i}.northstar-services.example@198.51.100.{20+i}/login',f'https://secure.portal{i}.northstar-services.example.{atk}/verify',f'https://{atk}/redirect?next=https%253A%252F%252Fportal{i}.northstar-services.example%2540auth-check.example%252Flogin']
      u=pats[i%3]
      body=f'From: Northstar Services <{sender}>\nReply-To: identity@{atk}\nReturn-Path: bounce@{atk}\nAuthentication-Results: SPF=PASS; DKIM=PASS; DMARC=PASS\nSubject: Account review completed\n\nYour account is active. One final identity confirmation is required at {u}. Enter password and six-digit verification code if requested.'
      out.append({'id':f'H-P-{i}','truth':'phishing','difficulty':'holdout','sender':sender,'text':body})
    return out

def metrics(rows):
    tp=tn=fp=fn=0
    for r in rows:
      if r['truth']=='phishing' and r['pred']=='phishing':tp+=1
      elif r['truth']=='safe' and r['pred']=='safe':tn+=1
      elif r['truth']=='safe':fp+=1
      else:fn+=1
    d=lambda a,b:a/b if b else 0
    p=d(tp,tp+fp);rc=d(tp,tp+fn)
    return {'tested':len(rows),'accuracy':d(tp+tn,len(rows)),'precision':p,'recall':rc,'f1':d(2*p*rc,p+rc),'tp':tp,'tn':tn,'fp':fp,'fn':fn,'fpr':d(fp,fp+tn),'fnr':d(fn,fn+tp)}

def run_cases(cases):
    rows=[]
    with ThreadPoolExecutor(max_workers=8) as ex:
      fut={ex.submit(advanced_predict,c):c for c in cases}
      for f in as_completed(fut):
        c=fut[f];r=f.result();r.update({'id':c['id'],'truth':c['truth'],'difficulty':c['difficulty']});rows.append(r)
    return rows

def main():
    global M;M=load_model()
    base=build_cases();hold=generic_holdout(80)
    rows=run_cases(base);hrows=run_cases(hold)
    result={'benchmark':'PhishLens advanced fusion v3','base':metrics(rows),'holdout':metrics(hrows),'base_mistakes':[r for r in rows if r['pred']!=r['truth']],'holdout_mistakes':[r for r in hrows if r['pred']!=r['truth']],'url_model_test_metrics':M.get('test_metrics')}
    print('ADVANCED_RESULT_BEGIN');print(json.dumps(result,indent=2,sort_keys=True));print('ADVANCED_RESULT_END')

if __name__=='__main__':main()
