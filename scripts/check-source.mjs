import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
const walk = dir => fs.readdirSync(dir,{withFileTypes:true}).filter(e=>!['.git','node_modules','.private-words','build','DerivedData'].includes(e.name)).flatMap(e=>e.isDirectory()?walk(path.join(dir,e.name)):[path.join(dir,e.name)]);
const files=walk('.');
// Optional, never committed: one private word per line (domain, company, hostnames…).
const privateWords = fs.existsSync('.private-words') ? fs.readFileSync('.private-words','utf8').split(/\r?\n/).map(w=>w.trim().toLowerCase()).filter(w=>w && !w.startsWith('#')) : [];
const project=fs.readFileSync('MNetBox.xcodeproj/project.pbxproj','utf8');
const sources=files.filter(f=>f.endsWith('.swift') && !f.startsWith('scripts/'));
const projectPaths = [...project.matchAll(/\bpath\s*=\s*(?:"([^"\n]+)"|([^;\n]+));/g)].map(m => (m[1] ?? m[2]).trim());
for (const file of sources) assert(projectPaths.includes(file.replaceAll('\\','/')), 'Missing Xcode source: '+file);
const definitions=[...project.matchAll(/^\s*([A-F0-9]{24})(?:\s*\/\*.*?\*\/)?\s*= /gm)].map(m=>m[1]);
assert.equal(new Set(definitions).size,definitions.length,'Duplicate project IDs');
for(const match of project.matchAll(/\b[A-F0-9]{24}\b/g)) assert(definitions.includes(match[0]),'Undefined project reference');
assert.equal((project.match(/isa = PBXNativeTarget/g)||[]).length,3);
assert.equal((project.match(/IPHONEOS_DEPLOYMENT_TARGET = 26.0/g)||[]).length,6);
for(const file of files.filter(f=>!f.endsWith('check-source.mjs'))) {
 const text=fs.readFileSync(file,'utf8');
 assert(!/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(text),'Private key: '+file);
 assert(!/\b(?:ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,}|nbt_[A-Za-z0-9]+\.[A-Za-z0-9]{20,})\b/.test(text),'Possible credential: '+file);
 // Public repository: no private addresses, e-mail addresses or locally listed private words.
 assert(!/(?<![\d.])(?:10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}(?![\d.])/.test(text),'Private IPv4 address: '+file);
 for (const [address] of text.matchAll(/[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})/g)) {
  const domain = address.split('@').pop().toLowerCase();
  assert(/(?:^|\.)(?:example\.(?:com|org|net)|example|test|invalid|localhost)$/.test(domain) || domain === 'users.noreply.github.com', 'E-mail address: '+file);
 }
 for (const word of privateWords) assert(!text.toLowerCase().includes(word),'Private word in '+file);
 if(file.endsWith('.swift') && !file.startsWith('scripts/')) {
  assert(!/httpMethod\s*=\s*"PUT"/.test(text),'Unsupported write request: '+file);
  if (file.startsWith('MNetBox/') && /httpMethod\s*=\s*"(?:PATCH|POST|DELETE)"/.test(text)) assert.equal(file, 'MNetBox/Core/Networking/APIClient.swift', 'Unexpected mutation transport');
  assert(!/\b(?:print|debugPrint|NSLog)\s*\(/.test(text),'Logging: '+file);
  assert(!/try!|as!|TODO|FIXME/.test(text),'Unfinished or unsafe code: '+file);
 }
}
const catalog=JSON.parse(fs.readFileSync('MNetBox/Resources/Localizable.xcstrings','utf8'));
for (const [key,entry] of Object.entries(catalog.strings)) {
 for (const language of ['en','fr']) {
  const value=entry.localizations?.[language]?.stringUnit?.value;
  assert(value?.length, 'Missing translation: '+language+' '+key);
  for (const specifier of ['%ld','%@']) assert.equal(value.split(specifier).length,key.split(specifier).length,'Format mismatch: '+key);
 }
}
for (const resource of ['MNetBox/Resources/Localizable.xcstrings','MNetBox/Resources/Assets.xcassets','MNetBox/Resources/PrivacyInfo.xcprivacy']) assert(projectPaths.includes(resource), 'Missing Xcode resource: '+resource);
assert(/knownRegions\s*=\s*\(\s*en,\s*fr,\s*Base,?\s*\)/.test(project), 'Missing French region');
console.log('PASS: '+sources.length+' Swift source memberships, project references, three targets, iOS 26 settings, basic credential and privacy hygiene and restricted mutation source checks.');
console.log('Swift compilation and XCTest execution require Xcode; they were not performed by this check.');
