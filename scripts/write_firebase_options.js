#!/usr/bin/env node
/**
 * Used by GitHub Actions. Fills lib/firebase_options.dart with the Firebase
 * WEB app settings of the project (creating the web app the first time), so
 * the published site connects to Firebase without running flutterfire by hand.
 *
 * It only replaces the placeholder file. Once you run `flutterfire configure`
 * on your computer and commit the real file (needed for the Android/iOS apps),
 * this script leaves it alone.
 *
 * Needs GOOGLE_APPLICATION_CREDENTIALS (the service-account JSON).
 *   node scripts/write_firebase_options.js <project-id>
 */
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const project = process.argv[2];
if (!project) {
  console.error('Usage: write_firebase_options.js <project-id>');
  process.exit(1);
}
const file = path.join(__dirname, '..', 'lib', 'firebase_options.dart');
const current = fs.readFileSync(file, 'utf8');
if (!current.includes('PLACEHOLDER')) {
  console.log('firebase_options.dart is already configured – leaving it as it is.');
  process.exit(0);
}

try {
  const sa = JSON.parse(fs.readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS, 'utf8'));
  console.log(`Service account: ${sa.client_email} (project in key: ${sa.project_id}); target project: ${project}`);
  if (sa.project_id !== project) console.log('⚠ The key belongs to a different project than PROJECT_ID.');
} catch (e) {
  console.log('Could not read service account file:', e.message);
}

const fb = (args) => {
  try {
    const out = execSync(`npx --yes firebase-tools@latest ${args} --project ${project} --json`, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] });
    return JSON.parse(out.slice(out.indexOf('{')));
  } catch (e) {
    console.log('firebase-tools failed:', (e.stdout || '').trim());
    if (fs.existsSync('firebase-debug.log')) {
      const log = fs.readFileSync('firebase-debug.log', 'utf8').split('\n');
      console.log('--- firebase-debug.log (last 40 lines) ---\n' + log.slice(-40).join('\n'));
    }
    process.exit(1);
  }
};

let apps = fb('apps:list WEB').result || [];
let appId = apps.length ? apps[0].appId : null;
if (!appId) {
  console.log('No Firebase web app yet – creating "Grub web"…');
  appId = fb('apps:create WEB "Grub web"').result.appId;
}

const cfgRes = fb(`apps:sdkconfig WEB ${appId}`).result || {};
let cfg = cfgRes.sdkConfig;
if (!cfg && cfgRes.fileContents) {
  const m = cfgRes.fileContents.match(/\{[\s\S]*\}/);
  cfg = m ? Function(`return (${m[0]})`)() : null;
}
if (!cfg || !cfg.apiKey) {
  console.error('Could not read the web app config.', JSON.stringify(cfgRes).slice(0, 500));
  process.exit(1);
}

const q = (v) => (v ? `'${String(v).replace(/'/g, "\\'")}'` : 'null');
const dart = `// GENERATED in GitHub Actions by scripts/write_firebase_options.js (web only).
// For the Android/iOS apps run \`flutterfire configure\` and commit the result.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    throw UnsupportedError('Mobile Firebase not configured yet – run flutterfire configure.');
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: ${q(cfg.apiKey)},
    appId: ${q(cfg.appId)},
    messagingSenderId: ${q(cfg.messagingSenderId)},
    projectId: ${q(cfg.projectId)},
    authDomain: ${q(cfg.authDomain)},
    storageBucket: ${q(cfg.storageBucket)},
    measurementId: ${q(cfg.measurementId)},
  );
}
`;
fs.writeFileSync(file, dart);
console.log(`✓ Wrote web Firebase settings for ${cfg.projectId} (${appId}).`);
