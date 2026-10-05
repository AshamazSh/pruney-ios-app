#!/usr/bin/env python3
"""Capture read-only Debug fixtures on an explicitly selected simulator."""
import argparse
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
SCENES = ['overview', 'swipe', 'filters', 'resize', 'final']
parser = argparse.ArgumentParser()
parser.add_argument('--device', required=True, help='Dedicated booted iPhone 11 Pro Max simulator UUID')
parser.add_argument('--language', help='Capture only one content.json language')
args = parser.parse_args()
content = json.loads((ROOT / 'tools/content.json').read_text())
for language, entry in content.items():
    if args.language and language != args.language:
        continue
    destination = ROOT / 'source-screens' / language
    destination.mkdir(parents=True, exist_ok=True)
    for scene in SCENES:
        subprocess.run(['xcrun', 'simctl', 'terminate', args.device, 'com.ashamazsh.pruney'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['xcrun', 'simctl', 'launch', args.device, 'com.ashamazsh.pruney', '-AppleLanguages', f'({language})', '-AppleLocale', entry['locale'], '-hasCompletedOnboarding', 'YES', '-appStoreScreenshot', scene], check=True, stdout=subprocess.DEVNULL)
        time.sleep(3)
        subprocess.run(['xcrun', 'simctl', 'io', args.device, 'screenshot', str(destination / f'{scene}.png')], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(f'Captured {language}/{scene}', flush=True)
