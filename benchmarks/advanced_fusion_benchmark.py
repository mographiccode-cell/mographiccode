import json,re,math,urllib.parse,urllib.request,ipaddress,time
from concurrent.futures import ThreadPoolExecutor,as_completed
from phishlens_benchmark import build_cases, BRANDS
from train_url_model import normalize_url, fnv1a, lexical_one

API='https://sonje03-phishlens-backend.hf.space/analyse'
URL_RE=re.compile(r"https?://[^\s<>\"']+",re.I)
OFFICIAL_URL={k:v[0].lower() for k,v in BRANDS.items()}
OFFICIAL_SENDER={k:v[1].split('@')[-1].lower() for k,v in BRANDS.items()}
M=None

def sigmoid(x):
    if x>=0:return 1/(1+math.exp(-x))
    e=math.exp(x);return e/(1+e)
def logit(p):
    p=max(1e-6,min(1-1e-6,p));return math.log(p/(1-p))
def load_model():
    with open('url_model_export.json') as f:return json.load(f)
def hash_prob(u):
    s='^'+normalize_url(u)+'$';counts={}
    for n in M['ngrams']:
        for i in range(max(0,len(s)-n+1)):
            k=fnv1a(s[i:i+n])%M['n_hash'];counts[k]=counts.get(k,0)+1.0
    norm=math.sqrt(sum(v*v for v in counts.values())) or 1.0;z=M['char_intercept'];w=M['char_coef']
    for k,v in counts.items():z+=w[k]*(v/norm)
    return sigmoid(z)
def lex_prob(u):
    x=lexical_one(u);z=M['lex_intercept']
    for i,v in enumerate(x):z+=M['lex_coef'][i]*((v-M['lex_mean'][i])/(M['lex_scale'][i] or 1.0))
    return sigmoid(z)
def ml_prob(u):
    cw,lw=M.get('blend',[0,1]);raw=cw*hash_prob(u)+lw*lex_prob(u);th=float(M.get('threshold',.5))
    return sigmoid(logit(raw)-logit(th))
def raw_split(u):
    try:return urllib.parse.urlsplit(u if re.match(r'^https?://',u,re.I) else 'http://'+u)
    except:return urllib.parse.urlsplit('http://invalid/')
def host_of(u):
    try:return (raw_split(u).hostname or '').lower()
    except:return ''
def regdom(host):
    parts=[x for x in (host or '').lower().split('.') if x]
    if len(parts)<=2:return '.'.join(parts)
    cc2={'co.uk','com.au','co.jp','com.br','co.in','com.sa','com.mx','co.nz','com.sg','com.tr','com.cn'};tail='.'.join(parts[-2:])
    return '.'.join(parts[-3:]) if tail in cc2 and len(parts)>=3 else tail
def is_official_host(host,brand):
    off=OFFICIAL_URL.get(brand,'');return host==off or host.endswith('.'+off)
def sender_is_official(sender_domain,brand):
    d=OFFICIAL_SENDER.get(brand,'');return bool(d and (sender_domain==d or sender_domain.endswith('.'+d)))
def nested_hosts(u):
    out=[]
    try:
        p=raw_split(u);q=urllib.parse.parse_qs(p.query)
        for vals in q.values():
            for v in vals:
                cur=v
                for _ in range(3):cur=urllib.parse.unquote(cur)
                if cur.startswith(('http://','https://')):out.append(host_of(cur))
    except:pass
    return [x for x in out if x]
def extract_urls(text):
    seen=[]
    for u in URL_RE.findall(text or ''):
        u=u.rstrip(').,;]>}')
        if u not in seen:seen.append(u)
    return seen

def score_url(u,sender_domain=''):
    risk=ml_prob(u);ml=risk;reasons=[];rawp=raw_split(u);host=(rawp.hostname or '').lower();netloc=(rawp.netloc or '').lower();nu=normalize_url(u);nh=nested_hosts(u)
    hard=False
    try:ipaddress.ip_address(host);risk=max(risk,.95);reasons.append('ip-host');hard=True
    except:pass
    if '@' in netloc:risk=max(risk,.995);reasons.append('userinfo-at');hard=True
    if host.startswith('xn--') or '.xn--' in host:risk=max(risk,.90);reasons.append('punycode');hard=True
    try:
        if rawp.port and rawp.port not in (80,443):risk=max(risk,.84);reasons.append('nonstandard-port');hard=True
    except ValueError:risk=max(risk,.90);reasons.append('invalid-port');hard=True
    if '%25' in (u or '').lower():risk=max(risk,.82);reasons.append('double-encoding')
    if len(u)>180:risk=max(risk,.58);reasons.append('very-long-url')
    cross_redirect=any(regdom(x)!=regdom(host) for x in nh)
    if cross_redirect:risk=max(risk,.84);reasons.append('cross-domain-redirect')

    tracker_to_official=False
    whole=(host+(rawp.path or '')+'?'+(rawp.query or '')).lower()
    for brand in OFFICIAL_URL:
        s_off=sender_is_official(sender_domain,brand);n_off=any(is_official_host(x,brand) for x in nh)
        if brand in host and not is_official_host(host,brand):
            if s_off and n_off and not hard:
                tracker_to_official=True;reasons.append('authenticated-tracker-to-official')
            else:risk=max(risk,.985);reasons.append('brand-domain-mismatch:'+brand);hard=True
        elif brand in whole and brand not in host and not is_official_host(host,brand) and not s_off:
            risk=max(risk,.78);reasons.append('brand-in-path-or-query:'+brand)
        if s_off and n_off and not hard:tracker_to_official=True

    official_any=any(is_official_host(host,b) for b in OFFICIAL_URL)
    if official_any and not hard:risk=min(risk,.16);reasons.append('official-domain')
    if tracker_to_official and not hard:
        # Authenticated sender + tracker that resolves only to the brand's official destination.
        risk=min(risk,.44);reasons.append('tracker-cap')
    if sender_domain and regdom(host)==regdom(sender_domain) and not hard:
        risk=min(risk,.36);reasons.append('sender-link-domain-aligned')
    return max(0,min(1,risk)),ml,reasons

def email_domain(addr):
    m=re.search(r'@([A-Za-z0-9.-]+)',addr or '');return m.group(1).lower().strip('.') if m else ''
def parse_header(text,name):
    m=re.search(r'^'+re.escape(name)+r':\s*(.+)$',text,re.I|re.M);return m.group(1).strip() if m else ''
def score_meta(c):
    text=c['text'];sender_dom=email_domain(c.get('sender',''));auth=parse_header(text,'Authentication-Results').lower();spf='spf=pass' in auth;dkim='dkim=pass' in auth;dmarc='dmarc=pass' in auth
    reply_dom=email_domain(parse_header(text,'Reply-To'));ret_dom=email_domain(parse_header(text,'Return-Path'));risk=.30;reasons=[];trusted_brand=None
    for b,d in OFFICIAL_SENDER.items():
        if sender_dom==d or sender_dom.endswith('.'+d):trusted_brand=b;break
    if trusted_brand and spf and dkim and dmarc:risk=.04;reasons.append('authenticated-official-sender')
    elif spf and dkim and dmarc:risk=.20;reasons.append('auth-pass-untrusted-domain')
    if reply_dom and regdom(reply_dom)!=regdom(sender_dom):risk=max(risk,.68);reasons.append('reply-to-mismatch')
    if ret_dom and regdom(ret_dom)!=regdom(sender_dom):risk=max(risk,.62);reasons.append('return-path-mismatch')
    if 'spf=fail' in auth and 'dkim=pass' not in auth:risk=max(risk,.74);reasons.append('spf-fail')
    frm=parse_header(text,'From').lower()
    for b,d in OFFICIAL_SENDER.items():
        if b in frm and not (sender_dom==d or sender_dom.endswith('.'+d)):risk=max(risk,.94);reasons.append('sender-brand-mismatch:'+b)
    return risk,trusted_brand,reasons
def credential_request(text):
    return bool(re.search(r'(enter|provide|submit|type).{0,55}(password|recovery code|verification code|one-time code|otp|mfa code)',(text or '').lower(),re.S))
def call_text(c):
    payload=json.dumps({'raw_text':c['text'],'sender_email':c['sender']}).encode()
    for a in range(3):
        try:
            req=urllib.request.Request(API,data=payload,headers={'Content-Type':'application/json'},method='POST')
            with urllib.request.urlopen(req,timeout=35) as r:d=json.loads(r.read().decode())
            return float((((d.get('agents') or {}).get('text') or {}).get('phishing_probability') or 0)),True
        except Exception:time.sleep(a+1)
    return .5,False
def advanced_predict(c):
    text_score,ok=call_text(c);sender_dom=email_domain(c.get('sender',''));urls=extract_urls(c['text']);urows=[score_url(u,sender_dom) for u in urls]
    max_url=max([x[0] for x in urows] or [.10]);mean_url=sum(x[0] for x in urows)/len(urows) if urows else .10;meta,brand,mreasons=score_meta(c);all_reasons=[r for x in urows for r in x[2]]
    hard=[r for r in all_reasons if r in ('ip-host','userinfo-at','punycode','invalid-port','nonstandard-port') or r.startswith('brand-domain-mismatch')]
    final=.60*max_url+.12*mean_url+.20*meta+.08*text_score
    if hard:final=max(final,.92)
    if max_url>=.90 and not (brand and meta<=.06 and any('tracker-cap' in x[2] for x in urows)):final=max(final,.88)
    if credential_request(c['text']):final=max(final,.82);mreasons=mreasons+['credential-request']
    if brand and meta<=.06 and max_url<.50 and not hard:final=min(final,.23)
    if brand and meta<=.06 and max_url<.68 and not hard:final=min(final,.43)
    pred='phishing' if final>=.55 else 'safe'
    return {'pred':pred,'risk':final,'text':text_score,'url':max_url,'url_mean':mean_url,'meta':meta,'urls':len(urls),'reasons':sorted(set(hard+mreasons)),'backend_ok':ok}
def generic_holdout(n=80):
    out=[]
    for i in range(n//2):
        dom=f'portal{i}.northstar-services.example';sender=f'notify@{dom}';url=f'https://{dom}/account/security/activity?utm_source=email&continue=%2Fbilling%2Fhistory&id={i}'
        body=f'From: Northstar Services <{sender}>\nReply-To: {sender}\nReturn-Path: {sender}\nAuthentication-Results: SPF=PASS; DKIM=PASS; DMARC=PASS\nSubject: Security and billing review\n\nA legitimate account notice. Review recent activity at {url}. Never send a password or OTP by email.'
        out.append({'id':f'H-S-{i}','truth':'safe','difficulty':'holdout','sender':sender,'text':body})
    for i in range(n//2):
        atk=f'northstar-verify-{i}.example';sender=f'notify@{atk}';pats=[f'https://portal{i}.northstar-services.example@198.51.100.{20+i}/login',f'https://secure.portal{i}.northstar-services.example.{atk}/verify',f'https://{atk}/redirect?next=https%253A%252F%252Fportal{i}.northstar-services.example%2540auth-check.example%252Flogin'];u=pats[i%3]
        body=f'From: Northstar Services <{sender}>\nReply-To: identity@{atk}\nReturn-Path: bounce@{atk}\nAuthentication-Results: SPF=PASS; DKIM=PASS; DMARC=PASS\nSubject: Account review completed\n\nYour account is active. One final identity confirmation is required at {u}. Enter your password and six-digit verification code if requested.'
        out.append({'id':f'H-P-{i}','truth':'phishing','difficulty':'holdout','sender':sender,'text':body})
    return out
def metrics(rows):
    tp=tn=fp=fn=0
    for r in rows:
        if r['truth']=='phishing' and r['pred']=='phishing':tp+=1
        elif r['truth']=='safe' and r['pred']=='safe':tn+=1
        elif r['truth']=='safe':fp+=1
        else:fn+=1
    d=lambda a,b:a/b if b else 0;p=d(tp,tp+fp);rc=d(tp,tp+fn)
    return {'tested':len(rows),'accuracy':d(tp+tn,len(rows)),'precision':p,'recall':rc,'f1':d(2*p*rc,p+rc),'tp':tp,'tn':tn,'fp':fp,'fn':fn,'fpr':d(fp,fp+tn),'fnr':d(fn,fn+tp)}
def run_cases(cases):
    rows=[]
    with ThreadPoolExecutor(max_workers=8) as ex:
        fut={ex.submit(advanced_predict,c):c for c in cases}
        for f in as_completed(fut):
            c=fut[f];r=f.result();r.update({'id':c['id'],'truth':c['truth'],'difficulty':c['difficulty']});rows.append(r)
    return rows
def main():
    global M;M=load_model();base=build_cases();hold=generic_holdout(80);rows=run_cases(base);hrows=run_cases(hold)
    result={'benchmark':'PhishLens advanced fusion v4','base':metrics(rows),'holdout':metrics(hrows),'base_mistakes':[r for r in rows if r['pred']!=r['truth']],'holdout_mistakes':[r for r in hrows if r['pred']!=r['truth']],'url_model_test_metrics':M.get('test_metrics'),'url_model_threshold':M.get('threshold'),'url_model_blend':M.get('blend')}
    print('ADVANCED_RESULT_BEGIN');print(json.dumps(result,indent=2,sort_keys=True));print('ADVANCED_RESULT_END')
if __name__=='__main__':main()
