# LabMates

A shared duty roster for med techs in the lab. Everyone logs their own duties and leave, and the Team tab shows who is on which shift and post each day. It runs in the phone's browser and can be added to the home screen like an app.

- **Hosting:** GitHub Pages (free)
- **Data and sign-in:** Supabase (free plan)

## What's in this folder

| File | What it is |
|---|---|
| `index.html` | The whole app |
| `config.js` | Your Supabase URL and key go here |
| `supabase-setup.sql` | Creates the database tables and security rules |
| `manifest.webmanifest`, `sw.js`, `icons/` | Let phones install it to the home screen and open it offline |

## How accounts work

- People sign up with their name, email and a password.
- **The first person to sign up becomes the admin** and gets in right away. Sign up first yourself.
- Everyone after that waits on a "Waiting for approval" screen until the admin approves them under **More → Members**. A red dot on the More tab means someone is waiting.
- Approved members can see everyone's duties, leave and notes. Each person can only change their own roster. The database enforces this, not just the app.
- The admin can remove someone (they're locked out right away) and restore them later.

## Setup (about 15 minutes, one time)

### 1. Create the Supabase project

1. Go to [supabase.com](https://supabase.com), sign in with GitHub, and create a new project. Pick the Southeast Asia (Singapore) region so it's fast from the Philippines. Save the database password somewhere safe; LabMates doesn't need it.
2. When the project is ready, open **SQL Editor → New query**, paste everything from `supabase-setup.sql`, and click **Run**. It should say "Success. No rows returned."
3. Open **Authentication → Sign In / Providers → Email**:
   - Keep **Email** enabled.
   - Turn **Confirm email** off. Otherwise each friend has to click a confirmation email first, and Supabase's built-in email sender only allows a few emails per hour. Your admin approval already keeps strangers out.
4. Open **Project Settings → API Keys** (or click **Connect** at the top) and copy:
   - the **Project URL** (looks like `https://abcd1234.supabase.co`)
   - the **publishable key** (starts with `sb_publishable_`) or, on older projects, the **anon public** key

   Never use the **secret** or **service_role** key here.
5. Paste both into `config.js`.

### 2. Put it on GitHub Pages

1. On GitHub, create a new **public** repository, for example `labmates`.
2. Click **Add file → Upload files** and upload everything in this folder, including the `icons` folder. Commit.
3. Go to **Settings → Pages**. Under **Build and deployment**, choose **Deploy from a branch**, branch **main**, folder **/ (root)**, and save.
4. After a minute, the site is live at `https://YOUR-USERNAME.github.io/labmates/`.

### 3. Point password resets at your site

In Supabase, open **Authentication → URL Configuration**:

- **Site URL:** `https://YOUR-USERNAME.github.io/labmates/`
- **Redirect URLs:** add the same address.

Without this, "Forgot password?" links open the wrong page.

### 4. Sign up first, then invite your friends

1. Open your site and create your account. You'll be the admin.
2. Send the link to your friends. When they sign up, approve them under **More → Members**.

## Adding it to the home screen

- **iPhone (Safari):** tap Share → **Add to Home Screen**.
- **Android (Chrome):** tap ⋮ → **Add to Home screen** or **Install app**.

It then opens full screen with the LabMates icon, and signs in automatically next time.

## Moving your roster from the Claude version

1. In the old Claude version, open **More → Backup and restore** and copy the backup text.
2. In the new site, sign in, open **More → Backup and restore**, paste it, and tap **Restore**.

## Good to know

- **Is the key in `config.js` a secret?** No. The publishable key is designed to be public. The security rules in `supabase-setup.sql` are what stop people who aren't approved from reading anything.
- **Free plan pause:** Supabase pauses a free project after about a week with little or no use, and emails you a warning first. If the lab opens it every day, this won't happen. If it does, open the project in the Supabase dashboard and click **Resume project**; data is kept.
- **Making someone else an admin:** in Supabase, open **Table Editor → profiles**, find their row and set `is_admin` to `true`.
- **Updating the app:** upload the new `index.html` to the repository. Phones pick it up the next time they open it online. If you change `sw.js`, bump the `CACHE` name inside it (for example `labmates-v2`).
- **No patient information.** This app is for staff schedules only. Don't put patient names or details in duty notes.
