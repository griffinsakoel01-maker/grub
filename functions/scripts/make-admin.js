/**
 * Gives a user the admin role (custom claim admin=true).
 *   GOOGLE_APPLICATION_CREDENTIALS=./service-account.json npm run make-admin -- you@example.com
 * The user must sign out and in again for the role to take effect.
 */
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');

const email = process.argv[2];
if (!email) {
  console.error('Usage: npm run make-admin -- someone@example.com');
  process.exit(1);
}
initializeApp({ credential: applicationDefault() });
getAuth()
  .getUserByEmail(email)
  .then(async (u) => {
    await getAuth().setCustomUserClaims(u.uid, { ...(u.customClaims || {}), admin: true });
    console.log(`✓ ${email} is now an admin. Ask them to sign out and back in.`);
    process.exit(0);
  })
  .catch((e) => {
    console.error(e.message);
    process.exit(1);
  });
