import json, time, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed

API='https://sonje03-phishlens-backend.hf.space/analyse'
BRANDS={
'microsoft':('account.microsoft.com','account-security-noreply@accountprotection.microsoft.com'),
'github':('github.com','noreply@github.com'),
'paypal':('www.paypal.com','service@paypal.com'),
'dhl':('www.dhl.com','tracking@dhl.com'),
'google':('accounts.google.com','no-reply@accounts.google.com'),
'aws':('console.aws.amazon.com','no-reply-aws@amazon.com'),
'linkedin':('www.linkedin.com','jobs-noreply@linkedin.com'),
'dropbox':('www.dropbox.com','no-reply@dropbox.com'),
'adobe':('account.adobe.com','mail@mail.adobe.com'),
'apple':('appleid.apple.com','no_reply@apple.com'),
'zoom':('zoom.us','no-reply@zoom.us'),
'slack':('slack.com','feedback@slack.com'),
'atlassian':('id.atlassian.com','noreply@am.atlassian.com'),
'spotify':('accounts.spotify.com','no-reply@spotify.com'),
'notion':('www.notion.so','team@makenotion.com')}

FILL=' This notice contains normal help-center wording, privacy information, account history, device context, accessibility notes, product updates, legal footer language, and customer-support instructions. Do not share passwords, private keys, recovery codes, payment PINs, or one-time codes by email.'

def safe_case(brand,variant,i):
    host,sender=BRANDS[brand]
    subjects=['Security alert: review recent account activity','Payment or billing notice — no immediate action required','Password reset requested — ignore if this was not you','New sign-in from a device we have not seen before','Your monthly statement and account activity are ready']
    urls=[f'https://{host}/security?utm_source=email&utm_medium=notification&ref={brand}-{i}',f'https://{host}/account/settings?continue=%2Fsecurity%2Factivity',f'https://{host}/help/security?campaign=mail_{i}&trackingId=SAFE-{i}']
    if variant==1: urls.append(f'https://links.{brand}.example/r?id={i}&target=https%3A%2F%2F{host}%2Fsecurity')
    if variant==2: urls.append(f'https://{host}/signin?redirect=%2Fbilling%2Freview&state={i}%3Aurgent%3Averify')
    extra=FILL*(3 if variant==0 else 8 if variant==1 else 14)
    body=f'''From: {sender}\nReply-To: {sender}\nReturn-Path: {sender}\nSubject: {subjects[(i+variant)%len(subjects)]}\nAuthentication-Results: SPF=PASS; DKIM=PASS; DMARC=PASS\n\nHello,\n\nThis is a legitimate {brand} notification. It may contain words such as urgent, verify, payment, password, security, login, and account because legitimate security and billing messages use them too. If you did not request the action, open {brand} from a saved bookmark instead of replying. We will never ask you to send a password or one-time code.\n\nReview: {urls[0]}\nSettings: {urls[1]}\nHelp: {urls[2]}\n{extra}\n\nExtracted URLs:\n'''+ '\n'.join(urls)
    return {'id':f'S-{brand}-{variant}','truth':'safe','difficulty':['hard','extreme','adversarial'][variant],'sender':sender,'text':body}

def phish_case(brand,variant,i):
    real,_=BRANDS[brand]
    attacker=f'{brand}-account-review.example'
    sender=f'security@{attacker}'
    if variant==0:
        urls=[f'https://{real}.{attacker}/verify/{i}?continue=https%3A%2F%2F{real}%2Fsecurity',f'https://{real}@{attacker}/login?state={i}',f'https://xn--{brand}-9za.example/auth/{i}']
        pre=FILL*3
    elif variant==1:
        urls=[f'https://192.0.2.{10+i%180}/{brand}/oauth/authorize?redirect_uri=https%3A%2F%2F{real}.{attacker}%2Fauth',f'https://{attacker}:8443/login?continue=https%3A%2F%2F{real}%2F',f'https://support.{real}.{attacker}/redirect?url=https%3A%2F%2F{real}%40{attacker}%2Fsignin']
        pre=FILL*9
    else:
        urls=[f'https://{real}@198.51.100.{20+i%150}/{brand}/session',f'https://{real}.secure-login.identity.{attacker}/oauth2/v2.0/authorize?client_id={brand}&redirect_uri=https%3A%2F%2F{real}%2F',f'https://{attacker}/r?next=https%253A%252F%252F{real}%2540auth-check.example%252Fverify']
        pre=('Your account review was completed successfully and no suspicious activity was detected. '+FILL)*16
    body=f'''From: {brand.title()} Security Team <{sender}>\nReply-To: identity@{attacker}\nReturn-Path: notices@{attacker}\nSubject: Routine account review completed — final identity confirmation\nAuthentication-Results: SPF=PASS; DKIM=PASS; DMARC=PASS\n\nHello,\n\n{pre}\n\nOne final automated check could not validate the billing or identity profile. To avoid a temporary restriction, confirm the account within 30 minutes. The verification page may request your password, recovery code, payment card, or six-digit sign-in code.\n\nOfficial review: {urls[0]}\nSecure sign-in: {urls[1]}\nPrivacy center: {urls[2]}\n\nExtracted URLs:\n'''+ '\n'.join(urls)
    return {'id':f'P-{brand}-{variant}','truth':'phishing','difficulty':['hard','extreme','adversarial'][variant],'sender':sender,'text':body}

def specials():
    return [
    {'id':'S-forwarded-spf-fail','truth':'safe','difficulty':'adversarial','sender':'it-security@university.edu','text':'From: University IT <it-security@university.edu>\nAuthentication-Results: SPF=FAIL (forwarded); DKIM=PASS; DMARC=PASS\nSubject: Required MFA enrollment reminder\n\nStudents must enroll MFA at https://sso.university.edu/login . Do not reply with credentials. '+FILL*20},
    {'id':'S-marketing-tracker','truth':'safe','difficulty':'adversarial','sender':'news@trusted-store.example','text':'From: Trusted Store <news@trusted-store.example>\nAuthentication-Results: SPF=PASS; DKIM=PASS; DMARC=PASS\nSubject: Final hours — verify delivery address before sale closes\n\nA legitimate promotion using tracking redirects. No password is requested. https://trk.trusted-store.example/click/8df3?dest=https%3A%2F%2Ftrusted-store.example%2Fsale '+FILL*18},
    {'id':'S-cloud-share','truth':'safe','difficulty':'adversarial','sender':'no-reply@dropbox.com','text':'From: Dropbox <no-reply@dropbox.com>\nAuthentication-Results: SPF=PASS; DKIM=PASS; DMARC=PASS\nSubject: A document was shared with you\n\nA colleague shared a file. Open https://www.dropbox.com/scl/fi/4f8d2/report.pdf?rlkey=abc123&dl=0 . If unexpected, ignore it. '+FILL*18},
    {'id':'S-oauth-consent','truth':'safe','difficulty':'adversarial','sender':'no-reply@accounts.google.com','text':'From: Google <no-reply@accounts.google.com>\nAuthentication-Results: SPF=PASS; DKIM=PASS; DMARC=PASS\nSubject: Review third-party app access\n\nYou can review account permissions at https://accounts.google.com/AccountChooser?continue=https%3A%2F%2Fmyaccount.google.com%2Fpermissions . '+FILL*20},
    {'id':'S-billing-urgent','truth':'safe','difficulty':'adversarial','sender':'no-reply-aws@amazon.com','text':'From: AWS Billing <no-reply-aws@amazon.com>\nAuthentication-Results: SPF=PASS; DKIM=PASS; DMARC=PASS\nSubject: Budget threshold exceeded — review now\n\nYour budget threshold was exceeded. Review charges at https://console.aws.amazon.com/billing/home . No payment credentials are requested by email. '+FILL*20},
    {'id':'P-userinfo-at','truth':'phishing','difficulty':'adversarial','sender':'security@account-center.example','text':'From: Microsoft Security <security@account-center.example>\nAuthentication-Results: SPF=PASS; DKIM=PASS; DMARC=PASS\nSubject: Sign-in restored successfully\n\nYour account is active; complete one final session confirmation at https://login.microsoftonline.com@198.51.100.44/common/oauth2/authorize . Alternative https://account.microsoft.com.security-check.example/ . The page asks for password and MFA code. '+FILL*18},
    {'id':'P-encoded-redirect','truth':'phishing','difficulty':'adversarial','sender':'accounts@google-security.example','text':'From: Google Accounts <accounts@google-security.example>\nAuthentication-Results: SPF=PASS; DKIM=PASS; DMARC=PASS\nSubject: Privacy review completed\n\nOne link remains: https://support.google.com.security-check.example/redirect?continue=https%3A%2F%2Faccounts.google.com%40auth-review.example%2Fsignin . Enter your recovery password if prompted. '+FILL*20},
    {'id':'P-brand-in-path','truth':'phishing','difficulty':'adversarial','sender':'notify@secure-docs.example','text':'From: DocuSign <notify@secure-docs.example>\nAuthentication-Results: SPF=PASS; DKIM=PASS; DMARC=PASS\nSubject: Completed agreement requires archive verification\n\nArchive at https://secure-docs.example/docusign.com/account/verify?document=88421 . Sign in with your corporate password to retain the audit trail. '+FILL*20},
    {'id':'P-safe-looking-query','truth':'phishing','difficulty':'adversarial','sender':'billing@paypal-review.example','text':'From: PayPal <billing@paypal-review.example>\nAuthentication-Results: SPF=PASS; DKIM=PASS; DMARC=PASS\nSubject: Refund processed successfully\n\nYour refund was processed. Confirm settlement at https://paypal-review.example/redirect?trusted=https%3A%2F%2Fwww.paypal.com%2Fmyaccount&next=https%3A%2F%2Fauth.paypal-review.example%2Flogin . '+FILL*19},
    {'id':'P-long-benign-prefix','truth':'phishing','difficulty':'adversarial','sender':'support@apple-security.example','text':'From: Apple Support <support@apple-security.example>\nAuthentication-Results: SPF=PASS; DKIM=PASS; DMARC=PASS\nSubject: Your support case was closed\n\n'+('Your support case is closed. No suspicious activity was found. Read our privacy and accessibility documentation. '+FILL)*20+'\nFinal archive step: https://appleid.apple.com@203.0.113.88/account/verify . Enter Apple ID password and six-digit code.'}
    ]

def build_cases():
    out=[]; i=1
    for brand in BRANDS:
        for v in range(3):
            out.append(safe_case(brand,v,i)); out.append(phish_case(brand,v,i)); i+=1
    out.extend(specials())
    return out

def post_case(c):
    payload=json.dumps({'raw_text':c['text'],'sender_email':c['sender']}).encode()
    for attempt in range(4):
        try:
            req=urllib.request.Request(API,data=payload,headers={'Content-Type':'application/json'},method='POST')
            with urllib.request.urlopen(req,timeout=35) as r:
                d=json.loads(r.read().decode())
            pred='phishing' if d.get('verdict')=='phishing' else 'safe'
            ag=d.get('agents') or {}
            return {'ok':True,'id':c['id'],'truth':c['truth'],'difficulty':c['difficulty'],'pred':pred,'fused':float(d.get('fused_score') or 0),'text':float((ag.get('text') or {}).get('phishing_probability') or 0),'url':float((ag.get('url') or {}).get('phishing_probability') or 0),'meta':float((ag.get('metadata') or {}).get('phishing_probability') or 0)}
        except Exception as e:
            if attempt==3: return {'ok':False,'id':c['id'],'truth':c['truth'],'difficulty':c['difficulty'],'error':str(e)}
            time.sleep(2*(attempt+1))

def metrics(rows):
    good=[r for r in rows if r.get('ok')]
    tp=tn=fp=fn=0
    for r in good:
        if r['truth']=='phishing' and r['pred']=='phishing': tp+=1
        elif r['truth']=='safe' and r['pred']=='safe': tn+=1
        elif r['truth']=='safe': fp+=1
        else: fn+=1
    div=lambda a,b:a/b if b else 0
    p=div(tp,tp+fp); rec=div(tp,tp+fn)
    return {'tested':len(good),'failed':len(rows)-len(good),'tp':tp,'tn':tn,'fp':fp,'fn':fn,'accuracy':div(tp+tn,len(good)),'precision':p,'recall':rec,'f1':div(2*p*rec,p+rec),'fpr':div(fp,fp+tn),'fnr':div(fn,fn+tp)}

def main():
    cases=build_cases(); print('cases',len(cases),flush=True)
    rows=[]
    with ThreadPoolExecutor(max_workers=8) as ex:
        futs={ex.submit(post_case,c):c for c in cases}
        done=0
        for f in as_completed(futs):
            rows.append(f.result()); done+=1
            if done%10==0: print('progress',done,'/',len(cases),flush=True)
    result={'benchmark':'PhishLens adversarial email+URL benchmark v2','generated_cases':len(cases),'metrics':metrics(rows),'hard_metrics':metrics([r for r in rows if r.get('difficulty')=='hard']),'extreme_metrics':metrics([r for r in rows if r.get('difficulty')=='extreme']),'adversarial_metrics':metrics([r for r in rows if r.get('difficulty')=='adversarial']),'mistakes':[r for r in rows if r.get('ok') and r['truth']!=r['pred']],'errors':[r for r in rows if not r.get('ok')],'rows':sorted(rows,key=lambda x:x['id'])}
    print('BENCHMARK_RESULT_BEGIN')
    print(json.dumps(result,indent=2,sort_keys=True))
    print('BENCHMARK_RESULT_END')

if __name__=='__main__': main()
