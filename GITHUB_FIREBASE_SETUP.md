# Publishing Grub from GitHub to Firebase (one-time setup)

Same setup as CR Loyalty. After this, every change pushed to `main` goes live by itself
(GitHub → build → Firebase Hosting):

- **Grub app:** https://grub-kenya.web.app
- **Admin dashboard:** https://grub-kenya.web.app/admin

> If your Firebase project ID is not `grub-kenya`, change it in `.firebaserc` and in the
> `PROJECT_ID:` line of the three files in `.github/workflows/`.

## 1. Firebase console (project grub-kenya)
- Upgrade to the **Blaze** plan (needed for Cloud Functions; small apps stay within the free allowance).
- Build → **Authentication → Get started** → turn on **Email/Password** and **Google**.
- Build → **Firestore Database → Create database** → production mode → location **africa-south1 (Johannesburg)**.
- Build → **Storage → Get started** → same location.
- Build → **Hosting → Get started** (click through, run nothing).

## 2. Service account for GitHub (Google Cloud console)
- console.cloud.google.com → select **grub-kenya** → IAM & Admin → **Service Accounts** → **Create** (name: `github-publisher`).
- Give it these roles:
  - Firebase Admin
  - API Keys Admin
  - Service Usage Consumer
  - Cloud Functions Admin
  - Service Account User
  - Secret Manager Admin
  - Cloud Build Editor
  - Artifact Registry Administrator
  - Cloud Datastore User
- Open it → **Keys → Add key → Create new key → JSON** → download the file. Keep it private.

## 3. Gemini key (for the AI assistant)
- aistudio.google.com → **Get API key** → create it in the **grub-kenya** project → copy it.

## 4. GitHub secrets (repo griffinsakoel01-maker/grub)
Settings → Secrets and variables → Actions → **New repository secret**:

| Name | Value |
|---|---|
| `FIREBASE_SERVICE_ACCOUNT` | the whole contents of the JSON file from step 2 |
| `GEMINI_API_KEY` | the key from step 3 |

## 5. Go live
1. **Actions → Publish app → Run workflow.** The site is live in about 5 minutes (the first Flutter build is the slowest).
2. **Actions → Deploy server → Run workflow** (everything). This deploys the database rules, storage rules and the AI and admin functions.
3. **Actions → Set up data → seed-catalogue.** This uploads the recipes, products, shops and demo prices.
4. Open https://grub-kenya.web.app, sign up with your own email.
5. **Actions → Set up data → make-admin**, typing that email. Then sign in at `/admin`.

## Every day after that
Tell Claude what to change. Claude pushes to `main` and the site updates itself.
Each build writes a report (code check, tests, build log) to the `ci-report` branch, so problems can be found and fixed quickly.

## Android / iPhone apps (later, for Play Store / App Store)
The web version connects to Firebase automatically. For the phone apps run once on your computer:
`flutterfire configure --project=grub-kenya --platforms=android,ios,web`, then commit `lib/firebase_options.dart`.
