import os, asyncio, sys
from playwright.async_api import async_playwright

OUTPUT_DIR = r"D:\Landpages_Projects\app\public\projects"
os.makedirs(OUTPUT_DIR, exist_ok=True)

LOCAL_PROJECTS = [
    {"name": "sesam", "port": 5181, "path": r"D:\Landpages_Projects\sesam.sa"},
    {"name": "jun", "port": 5182, "path": r"D:\Landpages_Projects\jun.omn"},
    {"name": "heed", "port": 5183, "path": r"D:\Landpages_Projects\heed_cafe"},
    {"name": "uniqpi", "port": 5184, "path": r"D:\Landpages_Projects\uniq_pi"},
    {"name": "mycard", "port": 5185, "path": r"D:\Landpages_Projects\mycard.oman"},
    {"name": "avastudio", "port": 5186, "path": r"D:\Landpages_Projects\avastudio.qa"},
]

# For static HTML projects, just open the file directly
LOCAL_FILES = [
    {"name": "sesam", "file": r"D:\Landpages_Projects\sesam.sa\index.html"},
    {"name": "jun", "file": r"D:\Landpages_Projects\jun.omn\index.html"},
    {"name": "heed", "file": r"D:\Landpages_Projects\heed_cafe\index.html"},
    {"name": "uniqpi", "file": r"D:\Landpages_Projects\uniq_pi\index.html"},
    {"name": "mycard", "file": r"D:\Landpages_Projects\mycard.oman\index.html"},
    {"name": "avastudio", "file": r"D:\Landpages_Projects\avastudio.qa\index.html"},
]

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page(viewport={"width": 1440, "height": 900})

        for proj in LOCAL_FILES:
            name = proj["name"]
            filepath = proj["file"]
            if not os.path.exists(filepath):
                print(f"SKIP: {filepath} not found")
                continue
            print(f"Capturing: {name}...")
            try:
                url = f"file:///{filepath}"
                await page.goto(url, wait_until="domcontentloaded", timeout=10000)
                await page.wait_for_timeout(1000)
                out = os.path.join(OUTPUT_DIR, f"{name}.jpg")
                await page.screenshot(path=out, type="jpeg", quality=85)
                print(f"  OK: {out}")
            except Exception as e:
                print(f"  Error: {e}")

        await browser.close()
    print("All done!")

asyncio.run(main())
