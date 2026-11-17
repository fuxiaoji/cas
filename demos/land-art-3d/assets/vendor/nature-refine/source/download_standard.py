"""Download only selected files from the author's public free Standard archive."""
from __future__ import annotations
import io, json, re, struct, zipfile, hashlib
from pathlib import Path
import urllib.request, urllib.parse, http.cookiejar, urllib.error

ROOT = Path(__file__).resolve().parent
OPENER = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
def request(url, body=None, headers=None):
    return OPENER.open(urllib.request.Request(url, data=urllib.parse.urlencode(body).encode() if body else None, headers=headers or {}), timeout=60)
PAGE = 'https://quaternius.itch.io/stylized-nature-megakit'
html = request(PAGE).read().decode()
token = re.search(r'name="csrf_token" value="([^"]+)"', html).group(1)
download_page = json.load(request(PAGE + '/download_url', {'csrf_token': token}))['url']
request(download_page).close()
download = json.load(request(PAGE + '/file/11055123', {'csrf_token': token}))['url']

class RemoteArchive(io.RawIOBase):
    def __init__(self, url):
        self.url = url
        self.pos = 0
        self.length = 0
        self.cache = {}
        response = request(url, headers={'Range': 'bytes=-65536'})
        if response.status != 206:
            response.close()
            raise RuntimeError('Archive host does not support partial public downloads')
        self.length = int(response.headers['Content-Range'].rsplit('/', 1)[-1])
        tail = response.read()
        self.cache[self.length-len(tail)] = tail
    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.pos
    def seek(self, offset, whence=0):
        self.pos = offset if whence == 0 else self.pos + offset if whence == 1 else self.length + offset
        return self.pos
    def read(self, size=-1):
        size = self.length-self.pos if size < 0 else min(size, self.length-self.pos)
        if size <= 0: return b''
        for start, data in self.cache.items():
            if self.pos >= start and self.pos + size <= start+len(data):
                result = data[self.pos-start:self.pos-start+size]
                self.pos += size
                return result
        # Fetch extra bytes so ZipFile's header + filename + payload are one request.
        end = min(self.length-1, self.pos + max(size, 1024*1024)-1)
        try:
            response = request(self.url, headers={'Range': f'bytes={self.pos}-{end}'})
        except urllib.error.HTTPError as error:
            if error.code != 403: raise
            self.url = json.load(request(PAGE + '/file/11055123', {'csrf_token': token}))['url']
            response = request(self.url, headers={'Range': f'bytes={self.pos}-{end}'})
        if response.status != 206:
            response.close()
            raise RuntimeError('Partial archive range failed')
        data = response.read()
        self.cache[self.pos] = data
        result = data[:size]
        self.pos += len(result)
        return result

remote = RemoteArchive(download)
archive = zipfile.ZipFile(remote)
names = archive.namelist()
(ROOT/'standard-archive-files.json').write_text(json.dumps(names, indent=2), encoding='utf-8')
print('ARCHIVE', remote.length, len(names), flush=True)
models = ['glTF/CommonTree_1.gltf', 'glTF/CommonTree_3.gltf', 'glTF/CommonTree_5.gltf', 'glTF/Bush_Common.gltf']
pending = models + ['License_Standard.txt']
copied = []
while pending:
    name = pending.pop(0)
    if name in copied: continue
    target = ROOT/name
    data = target.read_bytes() if target.exists() else archive.read(name)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    copied.append(name)
    print('EXTRACT', name, len(data), flush=True)
    if name.endswith('.gltf'):
        doc = json.loads(data)
        for entry in doc.get('buffers',[]) + doc.get('images',[]):
            uri = entry.get('uri','')
            if uri and not uri.startswith('data:'):
                pending.append('glTF/'+uri)
receipt = {'author':'Quaternius','pack':'Stylized Nature MegaKit Standard','official_url':'https://quaternius.com/packs/stylizednaturemegakit.html','download_page':PAGE,'free_upload_id':11055123,'license':'CC0-1.0; see License_Standard.txt','archive_bytes':remote.length,'selection':'Only free Standard broadleaf trees and bush; no paid Pro/Source assets','files':[{'path':name,'bytes':(ROOT/name).stat().st_size,'sha256':hashlib.sha256((ROOT/name).read_bytes()).hexdigest()} for name in copied]}
(ROOT/'source-receipt.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')
