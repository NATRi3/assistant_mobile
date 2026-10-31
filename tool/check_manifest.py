#!/usr/bin/env python3
"""Validate the packaged Android manifest, not the source template."""
import sys,xml.etree.ElementTree as ET
manifest=ET.parse(sys.argv[1]).getroot();a='{http://schemas.android.com/apk/res/android}'
app=manifest.find('application');assert app is not None
assert app.get(a+'allowBackup')=='false'
assert app.get(a+'usesCleartextTraffic')=='false'
assert manifest.get('package')=='io.github.natri3.assistant'
uses=manifest.find('uses-sdk');assert uses.get(a+'minSdkVersion')=='28' and uses.get(a+'targetSdkVersion')=='36'
assert not any(p.get(a+'name')=='android.permission.REORDER_TASKS' for p in manifest.findall('uses-permission'))
for activity in app.findall('activity'):
    if activity.get(a+'exported')=='true':assert activity.get(a+'name')=='io.github.natri3.assistant.MainActivity', 'Unexpected exported activity'
for provider in app.findall('provider'):assert provider.get(a+'exported')!='true'
print('Packaged manifest transport, backup, SDK and activity surface checks pass.')
