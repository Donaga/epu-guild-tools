"""Read-only source health/change report; never mark advice reviewed by fetching."""
from pathlib import Path
import argparse,hashlib,json,re,sys,urllib.error,urllib.request
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urlparse
from build_guide_catalog import HOSTS,ROOT,validate

def content_hash(text):
    # Ignore executable markup and whitespace, retain source text for change
    # detection. A changed hash is a review signal, not proof the advice changed.
    text=re.sub(r'<(script|style)\b[^>]*>.*?</\1>','',text,flags=re.I|re.S)
    text=re.sub(r'<[^>]+>',' ',text)
    return hashlib.sha256(re.sub(r'\s+',' ',text).strip().encode()).hexdigest()

class ReviewedRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):
        parsed=urlparse(newurl)
        if parsed.scheme!='https' or parsed.hostname not in HOSTS:raise ValueError('Redirect left approved source hosts')
        return super().redirect_request(req,fp,code,msg,headers,newurl)

def check(r):
    result={'id':r['id'],'url':r['url'],'reviewed':r['reviewed']}
    try:
        req=urllib.request.Request(r['url'],headers={'User-Agent':'EPU-Guild-Tools-guide-review/1.0'})
        with urllib.request.build_opener(ReviewedRedirect).open(req,timeout=20) as response:
            raw=response.read(3000001)
        if len(raw)>3000000:raise ValueError('Source exceeds review size limit')
        text=raw.decode('utf-8','replace');digest=content_hash(text)
        dates=re.findall(r'(?:dateModified|datePublished)"\s*:\s*"([^" ]+)',text)
        result.update(status='changed' if r.get('pageHash') and r['pageHash']!=digest else 'ok',pageHash=digest,sourceDates=dates[:2])
        if 'forever' not in text.lower():result['status']='edition_unconfirmed'
    except urllib.error.HTTPError as e:result.update(status='blocked' if e.code in (401,403,429) else ('missing' if e.code in (404,410) else 'error'),httpStatus=e.code)
    except Exception as e:result.update(status='error',reason=str(e))
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path);p.add_argument('--limit',type=int);args=p.parse_args()
    data=validate(json.loads((ROOT/'data/guide_sources.json').read_text(encoding='utf-8')))
    rows=data['guides'][:args.limit] if args.limit else data['guides']
    with ThreadPoolExecutor(max_workers=4) as pool:report=list(pool.map(check,rows))
    output=json.dumps({'notice':'Read-only health report. Inspect source content and official patch notes before changing reviewed dates or advice. Blocked pages are not proof of broken links.','sources':report},indent=2)
    if args.output:args.output.write_text(output,encoding='utf-8')
    else:print(output)
    sys.exit(1 if any(r['status'] in {'missing','edition_unconfirmed'} for r in report) else 0)
