"""Package the actual Godot coast screenshots into a self-contained review album.

Design: white/sea-mist paper, deep teal text, local Chinese sans typography;
large unframed photographs and quiet captions, only one wave playback control.
No concept imagery, web dependency, 3D module edit, or production acceptance claim.
Run again after the final Godot capture; source hashes are recorded on every run.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
from io import BytesIO
from html import escape
from html.parser import HTMLParser
import json
import os
from pathlib import Path
from urllib.parse import unquote, urlsplit

try:
    from PIL import Image
except ImportError:
    Image = None

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "artifacts/coast-v2-20261116"
OUTPUT = ROOT / "output/coast-v2-20261116"
VEHICLES = ROOT / "demos/land-art-3d/assets/vehicles3d"
REQUIRED = (
    "island-overview", "harbor-surf", "coastal-cliffs", "wetlands-river",
    "mountain-ridges", "wasteland-industry", "walls-and-defenses",
    "vehicle-fleet", "sunken-ruins", "crossroads", "strategic-scale",
)
TITLE = "归航海岸 · 场景评审"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_atomic(path: Path, data: str, encoding: str = "utf-8") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(data, encoding=encoding)
    os.replace(temporary, path)


def package_image(source: Path, key: str, category: str, records: list[dict]) -> dict:
    if not source.is_file():
        raise FileNotFoundError(f"缺少实际截图：{source}")
    folder = OUTPUT / "media" / category
    folder.mkdir(parents=True, exist_ok=True)
    suffix = ".webp" if Image is not None else source.suffix
    destination = folder / (key + suffix)
    source_data = source.read_bytes()
    size = None
    if Image is not None:
        with Image.open(BytesIO(source_data)) as image:
            image.load()
            size = list(image.size)
            # Format conversion only; no cropping, repainting, or invented detail.
            image.convert("RGB").save(destination, "WEBP", quality=90, method=5)
    else:
        destination.write_bytes(source_data)
    original = None
    if category != "waves":
        original = OUTPUT / "media/originals" / (key + source.suffix)
        original.parent.mkdir(parents=True, exist_ok=True)
        original.write_bytes(source_data)
    record = {
        "key": key,
        "source": source.relative_to(ROOT).as_posix(),
        "source_sha256": hashlib.sha256(source_data).hexdigest(),
        "source_bytes": len(source_data),
        "display": destination.relative_to(OUTPUT).as_posix(),
        "display_sha256": sha256(destination),
        "display_bytes": destination.stat().st_size,
        "size_px": size,
        "original": original.relative_to(OUTPUT).as_posix() if original else None,
        "provenance": "Actual Godot GPU capture; image format conversion only",
    }
    records.append(record)
    return record


def figure(record: dict, title: str, note: str = "", hero: bool = False) -> str:
    src = escape(record["display"], quote=True)
    href = escape(record["original"] or record["display"], quote=True)
    loading = 'loading="eager" fetchpriority="high"' if hero else 'loading="lazy"'
    detail = f"<span>{escape(note)}</span>" if note else ""
    return (
        f'<figure class="photo{ " hero-photo" if hero else ""}">'
        f'<a href="{href}" target="_blank" rel="noopener" aria-label="查看{escape(title, quote=True)}原图">'
        f'<img src="{src}" alt="{escape(title, quote=True)}，Godot 实际截图" '
        f'width="1600" height="900" {loading} decoding="async"></a>'
        f'<figcaption><strong>{escape(title)}</strong>{detail}</figcaption></figure>'
    )


CSS = """
:root{--paper:#fff;--mist:#eef5f4;--ink:#274c56;--muted:#657f85;--line:#d5e4e0;--teal:#277e86}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:var(--paper);color:var(--ink);font-family:"Microsoft YaHei UI","Microsoft YaHei","PingFang SC",sans-serif;font-size:17px;line-height:1.7;-webkit-font-smoothing:antialiased}
a{color:inherit;text-decoration:none}a:focus-visible,button:focus-visible{outline:3px solid var(--teal);outline-offset:5px}button{font:inherit}img{display:block;width:100%;height:auto}figure{margin:0}p{margin:0;max-width:48em}h1,h2{font-weight:500;margin:0;letter-spacing:-.045em;line-height:1.25}h1{font-size:clamp(36px,5.1vw,74px)}h2{font-size:clamp(27px,3vw,42px)}
.shell{width:min(1480px,calc(100% - 72px));margin-inline:auto}.masthead{display:flex;align-items:center;justify-content:space-between;padding:26px 0 21px;font-size:14px;color:var(--muted)}.brand{font-size:25px;font-weight:600;letter-spacing:.05em;color:var(--ink)}.edition{display:flex;gap:24px;align-items:center}.intro{padding:30px 0 29px;display:flex;align-items:flex-end;justify-content:space-between;gap:36px}.intro p{color:var(--muted);font-size:15px;max-width:30em}.photo a{display:block;background:var(--mist)}.photo img{aspect-ratio:16/9;object-fit:contain}.photo figcaption{padding:12px 0 0;display:flex;align-items:baseline;gap:20px;justify-content:space-between;font-size:14px;color:var(--muted)}.photo figcaption strong{font-size:15px;font-weight:500;color:var(--ink)}.photo figcaption span{font-size:13px;text-align:right;max-width:40em}.hero-photo figcaption{padding-top:14px}.chapter{padding-top:86px}.chapter-heading{display:flex;justify-content:space-between;align-items:flex-end;gap:32px;margin-bottom:26px}.chapter-heading p{color:var(--muted);font-size:15px;max-width:34em}.pair{display:grid;grid-template-columns:1fr 1fr;gap:26px}.chapter>.photo+.pair,.chapter>.pair+.photo,.chapter>.photo+.photo,.chapter>.pair+.pair{margin-top:34px}.wide-note{padding:19px 0 0;font-size:14px;color:var(--muted)}
.sea-band{margin-top:82px;padding:54px 0;background:var(--mist)}.sea-band .chapter-heading{margin-bottom:23px}.wave-player{position:relative;background:#c4d9db}.wave-player img{aspect-ratio:16/9;object-fit:contain}.wave-controls{display:flex;justify-content:space-between;align-items:center;gap:18px;padding:17px 0 0}.wave-controls p{font-size:14px;color:var(--muted)}.wave-button{border:1px solid var(--teal);border-radius:999px;background:var(--paper);color:var(--ink);padding:10px 24px;cursor:pointer;min-width:164px}.wave-button:disabled{cursor:wait;opacity:.65}.wave-button[aria-pressed="true"]{background:var(--teal);color:white}.wave-status{font-size:13px;font-variant-numeric:tabular-nums;color:var(--muted);margin-left:12px}.wave-tip{font-size:13px;color:var(--muted);margin-top:12px}.scope{background:var(--mist);margin-top:75px;padding:33px 36px;display:grid;grid-template-columns:1fr 2fr;gap:40px}.scope h2{font-size:24px}.scope p{font-size:15px;line-height:1.9}.footer{padding:32px 0 45px;color:var(--muted);font-size:13px;display:flex;justify-content:space-between;gap:20px}.footer a{text-decoration:underline;text-underline-offset:3px}
@media(max-width:850px){.shell{width:calc(100% - 36px)}.intro{display:block;padding-top:19px}.intro p{margin-top:19px}.chapter-heading{display:block}.chapter-heading p{margin-top:13px}.chapter{padding-top:57px}.pair{grid-template-columns:1fr;gap:29px}.sea-band{margin-top:55px;padding:34px 0}.scope{grid-template-columns:1fr;gap:17px;padding:25px 22px;margin-top:55px}.photo figcaption{gap:8px;display:block}.photo figcaption span{display:block;text-align:left;font-size:12px;margin-top:4px}.wave-controls{align-items:flex-start;flex-wrap:wrap}.wave-controls p{order:2;flex-basis:100%}.edition{gap:12px;font-size:12px}.masthead{padding-top:17px}.footer{display:block}.footer span{display:block;margin-bottom:10px}}
@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
"""


JS = """
const wavePaths=__WAVE_PATHS__;
const picture=document.getElementById('wave-picture');
const playButton=document.getElementById('wave-toggle');
const progress=document.getElementById('wave-status');
let ready=false,playing=false,frame=0,startAt=0,request=0;
function draw(index){frame=index;picture.src=wavePaths[index];progress.textContent=(index*.25).toFixed(2)+' / 4.00 秒';}
function tick(now){if(!playing)return;const next=Math.floor((now-startAt)/250)%wavePaths.length;if(next!==frame)draw(next);request=requestAnimationFrame(tick);}
function pause(){playing=false;cancelAnimationFrame(request);playButton.textContent='播放海浪';playButton.setAttribute('aria-pressed','false');}
function play(){if(!ready)return;playing=true;startAt=performance.now()-frame*250;playButton.textContent='暂停';playButton.setAttribute('aria-pressed','true');request=requestAnimationFrame(tick);}
playButton.addEventListener('click',()=>playing?pause():play());
document.addEventListener('visibilitychange',()=>{if(document.hidden)pause();});
Promise.all(wavePaths.map(path=>new Promise((resolve,reject)=>{const image=new Image();image.onload=()=>resolve(image);image.onerror=()=>reject(path);image.src=path;}))).then(()=>{
 ready=true;playButton.disabled=false;playButton.textContent='播放海浪';document.body.dataset.waveReady='true';
}).catch(path=>{playButton.textContent='画面加载失败';document.getElementById('wave-tip').textContent='请重新运行图册打包，再打开页面。';document.body.dataset.waveError=path;});
window.CASCoastReview={play,pause,get frame(){return frame;},get ready(){return ready;},get playing(){return playing;},frameCount:wavePaths.length,durationSeconds:4};
"""


def render_page(images: dict, wave_records: list[dict]) -> str:
    f = lambda key, title, note="", hero=False: figure(images[key], title, note, hero)
    waves_json = json.dumps([record["display"] for record in wave_records], ensure_ascii=False)
    javascript = JS.replace("__WAVE_PATHS__", waves_json)
    return f"""<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light"><title>{TITLE}</title><style>{CSS}</style></head>
<body><header class="shell masthead"><a class="brand" href="#top">归航</a><div class="edition"><span>海岸场景评审</span><time datetime="2026-11-16">2026.11.16</time></div></header>
<main id="top"><div class="shell"><div class="intro"><h1>海岸，与岛屿深处。</h1><p>本轮看海浪、地形与载具的实际呈现。<br>以下均为 Godot 实际截图，点击大图查看原图。</p></div>
{f('island-overview','海岛全景','从港口、聚落到山脊与驻防区。',True)}</div>
<section class="sea-band" aria-labelledby="sea-title"><div class="shell"><div class="chapter-heading"><h2 id="sea-title">海浪向岸边推进</h2><p>16 帧实际采样组成 4 秒序列。可以播放、暂停，观察浪线与浅水变化。</p></div>
<div class="wave-player"><img id="wave-picture" src="{wave_records[0]['display']}" width="1600" height="900" alt="实际海岸水面序列，当前暂停" decoding="async"></div>
<div class="wave-controls"><p>原始画面按每帧 0.25 秒播放，保留实际采样节奏。</p><div><button id="wave-toggle" class="wave-button" type="button" aria-pressed="false" aria-controls="wave-picture" disabled>准备海浪画面</button><span id="wave-status" class="wave-status">0.00 / 4.00 秒</span></div></div>
<p id="wave-tip" class="wave-tip">页面打开时暂停；点击后播放循环序列。</p></div></section>
<section class="shell chapter" aria-labelledby="coast-title"><div class="chapter-heading"><h2 id="coast-title">沿着海岸看</h2><p>近岸浅水、沙滩与悬崖分别呈现，水下遗迹保留在真实场景中。</p></div>
<div class="pair">{f('harbor-surf','港口与浪线')}{f('coastal-cliffs','悬崖与小海湾')}</div>
{f('sunken-ruins','水下的旧文明遗迹')}</section>
<section class="shell chapter" aria-labelledby="land-title"><div class="chapter-heading"><h2 id="land-title">从湿地走向山脊</h2><p>河流、沼泽、山地与道路，同处一张米制地理样区。</p></div>
<div class="pair">{f('wetlands-river','沼泽与河道')}{f('mountain-ridges','山脊与高差')}</div>
{f('crossroads','道路与聚落近景','观察建筑、道路、人物的相对尺度。')}</section>
<section class="shell chapter" aria-labelledby="ruins-title"><div class="chapter-heading"><h2 id="ruins-title">废土，和留下来的工事</h2><p>工业废墟、围墙与防御设施，是这一轮的场景表现样板。</p></div>
<div class="pair">{f('wasteland-industry','废弃工业区')}{f('walls-and-defenses','围墙与驻防设施')}</div></section>
<section class="shell chapter" aria-labelledby="vehicle-title"><div class="chapter-heading"><h2 id="vehicle-title">海上、岸上、空中</h2><p>八种真 3D 载具；只展示造型、材质与动作，尚不代表战斗或部署 AI。</p></div>
{f('vehicle-fleet','载具在海岸样区中')}
{f('vehicle-catalog','八种载具图册','普通与重型登陆艇、突击艇、两栖车、坦克、自行火炮、运输与武装直升机。')}
{f('rotorcraft-close','旋翼机近景','运输机与武装突击机的轮廓和装备差异。')}</section>
<section class="shell chapter" aria-labelledby="scale-title"><div class="chapter-heading"><h2 id="scale-title">把镜头拉远</h2><p>画面保留实际比例尺，便于评估陆地、设施和海面之间的关系。</p></div>
{f('strategic-scale','远景与实际比例尺','本次采样区边长 720 米，不代表满级家园全岛面积。')}
<aside class="scope"><h2>这次先看景</h2><p>这是独立的隔离美术样区，用于评审海浪、地形、设施和载具。720 米是本次采样区的边长，不是满级全岛。正式模式、战斗 AI、随机地图适配与 Android 实机尚未验收。</p></aside></section>
</main><footer class="shell footer"><span>归航 · 实际场景评审</span><a href="review-assets.json" target="_blank" rel="noopener">截图来源与文件核验</a></footer>
<script>{javascript}</script></body></html>"""


class LocalReferences(HTMLParser):
    def __init__(self):
        super().__init__()
        self.references = []

    def handle_starttag(self, tag, attributes):
        for key, value in attributes:
            if key in {"src", "href", "poster"} and value and not value.startswith("#"):
                self.references.append(value)


def validate(output: Path) -> dict:
    parser = LocalReferences()
    parser.feed((output / "index.html").read_text(encoding="utf-8"))
    manifest = json.loads((output / "review-assets.json").read_text(encoding="utf-8"))
    refs = set(parser.references)
    for record in manifest["images"]:
        refs.add(record["display"])
        if record["original"]:
            refs.add(record["original"])
    missing = []
    for reference in sorted(refs):
        url = urlsplit(reference)
        if url.scheme or url.netloc:
            raise ValueError(f"图册不应依赖网络路径：{reference}")
        local = (output / unquote(url.path)).resolve()
        if not local.is_relative_to(output.resolve()):
            raise ValueError(f"路径不在图册内：{reference}")
        if not local.is_file():
            missing.append(reference)
    if missing:
        raise FileNotFoundError("图册缺少路径：" + ", ".join(missing))
    waves = [record for record in manifest["images"] if record["key"].startswith("frame-")]
    if len(waves) != 16:
        raise ValueError(f"海浪序列应为16帧，实际{len(waves)}")
    for record in manifest["images"]:
        if sha256(output / record["display"]) != record["display_sha256"]:
            raise ValueError(f"显示文件核验不符：{record['display']}")
        if record["original"] and sha256(output / record["original"]) != record["source_sha256"]:
            raise ValueError(f"原图核验不符：{record['original']}")
    report = {"passed": True, "local_references_checked": len(refs), "images": len(manifest["images"]),
              "wave_frames": len(waves), "wave_duration_seconds": 4, "network_dependencies": 0,
              "display_bytes": sum(record["display_bytes"] for record in manifest["images"]),
              "scope": "Paths, copied original hashes and display hashes; browser appearance checked separately"}
    write_atomic(output / "review-validation.json", json.dumps(report, ensure_ascii=False, indent=2))
    return report


def main() -> None:
    arguments = argparse.ArgumentParser(description=__doc__)
    arguments.add_argument("--check", action="store_true", help="只核对已生成图册的本地路径与哈希")
    args = arguments.parse_args()
    if args.check:
        print(json.dumps(validate(OUTPUT), ensure_ascii=False))
        return
    missing = [SOURCE / "screenshots" / (key + ".png") for key in REQUIRED
               if not (SOURCE / "screenshots" / (key + ".png")).is_file()]
    missing += [SOURCE / "waves" / f"frame-{i:02d}.png" for i in range(16)
                if not (SOURCE / "waves" / f"frame-{i:02d}.png").is_file()]
    missing += [VEHICLES / name for name in ("godot-vehicle-catalog.png", "godot-rotorcraft-close.png")
                if not (VEHICLES / name).is_file()]
    if missing:
        raise FileNotFoundError("请先完成实际截图：\n" + "\n".join(map(str, missing)))
    records: list[dict] = []
    images = {key: package_image(SOURCE / "screenshots" / (key + ".png"), key, "stills", records)
              for key in REQUIRED}
    images["vehicle-catalog"] = package_image(VEHICLES / "godot-vehicle-catalog.png", "vehicle-catalog", "stills", records)
    images["rotorcraft-close"] = package_image(VEHICLES / "godot-rotorcraft-close.png", "rotorcraft-close", "stills", records)
    waves = [package_image(SOURCE / "waves" / f"frame-{i:02d}.png", f"frame-{i:02d}", "waves", records) for i in range(16)]
    manifest = {"title": TITLE, "generated_utc": datetime.now(timezone.utc).isoformat(),
                "description": "Actual Godot screenshots; no generated concept image, repainting, or invented footage.",
                "source": SOURCE.relative_to(ROOT).as_posix(), "images": records,
                "wave_sampling": {"frames":16,"seconds_per_frame":.25,"duration_seconds":4,"initial_state":"paused"},
                "acceptance_scope": "Isolated 720m-square art sample; not full maximum-level island, production AI, formal modes or Android acceptance"}
    write_atomic(OUTPUT / "review-assets.json", json.dumps(manifest, ensure_ascii=False, indent=2))
    write_atomic(OUTPUT / "index.html", render_page(images, waves))
    # Both launchers use quoted relative paths and work without a web server.
    write_atomic(ROOT / "CAS-Coast-Review.cmd", '@echo off\nstart "" "%~dp0output\\coast-v2-20261116\\index.html"\n', "ascii")
    write_atomic(OUTPUT / "CAS-Coast-Review.cmd", '@echo off\nstart "" "%~dp0index.html"\n', "ascii")
    report = validate(OUTPUT)
    print("COAST_REVIEW_PACKAGED " + json.dumps(report, ensure_ascii=False))
    print(OUTPUT / "index.html")


if __name__ == "__main__":
    main()
