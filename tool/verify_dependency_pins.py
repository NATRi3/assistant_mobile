#!/usr/bin/env python3
"""Verify public release sidecars against artifacts captured by Gradle.
Only public artifact URLs are requested. No repository source is uploaded.
"""
import hashlib,json,pathlib,urllib.request,xml.etree.ElementTree as ET
root=pathlib.Path(__file__).resolve().parents[1]
metadata=ET.parse(root/'android/gradle/verification-metadata.xml')
pins=[('com.nimbusds','nimbus-jose-jwt','10.9.1','jar','https://repo.maven.apache.org/maven2'),('androidx.biometric','biometric','1.1.0','aar','https://dl.google.com/dl/android/maven2'),('com.google.guava','guava','33.7.2-android','jar','https://repo.maven.apache.org/maven2'),('org.jetbrains.kotlin','kotlin-gradle-plugin','2.4.21','gradle813.jar','https://repo.maven.apache.org/maven2')]
results=[]
for group,name,version,ext,host in pins:
 filename=f'{name}-{version}'+('-gradle813.jar' if ext=='gradle813.jar' else '.'+ext);url=f'{host}/{group.replace(".","/")}/{name}/{version}/{filename}'
 with urllib.request.urlopen(url,timeout=60) as f: data=f.read()
 with urllib.request.urlopen(url+'.sha1',timeout=60) as f: expected=f.read().decode().strip().split()[0]
 assert hashlib.sha1(data).hexdigest()==expected
 sha=hashlib.sha256(data).hexdigest()
 c=next(c for c in metadata.findall('.//{*}component') if (c.get('group'),c.get('name'),c.get('version'))==(group,name,version))
 a=next(a for a in c.findall('{*}artifact') if a.get('name')==filename)
 assert sha in {x.get('value') for x in a.findall('{*}sha256')}
 results.append({'artifact':f'{group}:{name}:{version}','url':url,'sha256':sha,'official_sha1_sidecar_matches':True,'gradle_sha256_matches':True})
print(json.dumps(results,indent=2))
