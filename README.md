# LabMates

A shared duty roster for med techs in the lab. Everyone logs their own duties and leave, and the Team tab shows who is on which shift and post each day. It runs in the phone's browser and can be added to the home screen like an app.

- **Hosting:** GitHub Pages (free)
- **Data and sign-in:** Supabase (free plan). Sign in with Google, or with email and a password.

## What's in this folder

| File | What it is |
|---|---|
| `index.html` | The page, its styles and its security policy |
| `app.js` | The app itself |
| `config.js` | Your Supabase URL and publishable key |
| `vendor/` | Pinned copies of the Supabase and PDF libraries, checked by the browser before they run |
| `supabase-setup.sql` | Database tables and security rules |
| `manifest.webmanifest`, `sw.js`, `icons/` | Home-screen install and offline opening |

## How accounts work

- People choose how to sign in:
  - **Continue with Google:** name and Gmail come from Google; LabMates never sees their Google password.
  - **Email and password:** any password of 6 or more characters (letters, numbers or symbols, so a 6-digit number works).
- Anyone can add a password to a Google account later under **More → Set or change password**.
- **Everyone starts as "Waiting for approval", including the first person.** Admin rights are given only from the Supabase SQL Editor (setup step 4), so a stranger who finds the link can't make themselves admin.
- The admin approves people under **More → Members**, which shows each person's name, email and sign-in method (Google, Password, or both). A red dot on More means someone is waiting.
- Approved members see everyone's duties, leave and notes. Each person can change only their own roster. The database enforces this, not just the app.
- Removing someone locks them out on their next refresh. Their account stays so it can be restored.

## Setup

### 1. Supabase project

1. Create a project at [supabase.com](https://supabase.com) (region: Southeast Asia, Singapore).
2. **SQL Editor → New query**: paste all of `supabase-setup.sql` and click **Run**.
3. Set up Google sign-in (next section).
4. **Project Settings → API Keys** (or **Connect**): copy the Project URL and the **publishable** key (`sb_publishable_…`) into `config.js`.

### 2. GitHub Pages

1. Upload every file and folder here to a public repo.
2. **Settings → Pages**: Deploy from a branch, **main**, **/ (root)**.

### 3. Google sign-in

In [Google Cloud Console](https://console.cloud.google.com):
1. Create a project called `LabMates`.
2. Open **Google Auth Platform**. Under **Branding**, enter the app name and your email. **Don't upload a logo**; a logo requires Google's review.
3. Under **Audience**, choose **External**, then click **Publish app** so anyone with a Google account can sign in (in "Testing" mode only listed test users can). Basic name-and-email sign-in doesn't need Google's review.
4. Under **Clients**, create an OAuth client of type **Web application**:
   - **Authorized JavaScript origins:** `https://yvnredondo.github.io`
   - **Authorized redirect URIs:** `https://gtpwvbxtvmisbqyrppki.supabase.co/auth/v1/callback`
5. Copy the **Client ID** and **Client secret**.

In Supabase:
1. **Authentication → Sign In / Providers → Google:** turn it on, paste the Client ID and Client secret, save.
2. **Authentication → URL Configuration:** **Site URL** `https://yvnredondo.github.io/labmates/`, and the same address under **Redirect URLs**. No wildcards.
3. **Authentication → Sign In / Providers:** keep **Email** on and **Confirm email** off. Keep **Allow anonymous sign-ins** off. The database also refuses phone and anonymous sign-ups as a second lock.
4. **Authentication → Sign In / Providers → Email:** **Minimum password length** 6, **Password requirements** "No required characters".

The client secret goes only into Supabase. Never put it in this repo or send it to anyone.

### 4. Make yourself admin (one time)

1. Open the site and sign in (Google or email). You'll see "Waiting for approval".
2. In Supabase **SQL Editor**, run (with your email):
   ```sql
   update public.profiles set status = 'approved', is_admin = true
   where id = (select id from auth.users where email = 'you@example.com');
   ```
3. Back in the app, tap **Check again**.

To add another admin later, run the same line with their email. To remove admin rights, run it with `is_admin = false`.

## Security

**What protects the data**
- Row level security in the database decides who can read and change what. The app can't get around it, and neither can anyone calling Supabase directly with the public key.
- Google sign-in uses one-time codes (PKCE), wiped from the address bar right after use.
- Signed-out visitors can't read anything. Pending, removed or declined accounts see only their own name.
- Rosters are limited to 300 KB and names to 40 characters.
- Everything people type (names, posts, notes) is shown as plain text, never run as code.
- The page has a strict content security policy. It runs only its own scripts, and can only talk to your Supabase project and Google Fonts. Injected code is blocked, and data can't be sent anywhere else.
- The two libraries are stored in this repo at fixed versions with integrity hashes. If either file is altered, the browser refuses to run it.
- Signing out uploads any unsynced changes, signs the account out of all devices, and deletes the roster copy saved on that phone.

**Settings to check in Supabase**
- Google: on. Email: on, **Confirm email** off. Anonymous: off.
- **Allow new users to sign up:** once all your friends have joined, you can turn this off. Turn it back on when someone new joins.
- **Members:** check the name, email and sign-in method before approving anyone, and only approve people you know.

**Trade-offs of email and password (know these)**
- **Emails aren't checked.** With no email service, Supabase can't confirm people own the email they sign up with. Someone could make a password account using a coworker's email. If that coworker later uses Google with the same Gmail, Supabase joins the two, and the stranger's password would also open it. Admin approval is the guard: approve only people you've confirmed in person. If a member sees "Google + password" in Members but never set a password, remove the account and ask them.
- **Short passwords are easier to guess.** Supabase slows down repeated wrong guesses, but a 6-digit number is much weaker than a longer password. Members choose; encourage something longer.
- **No reset emails.** Supabase's free built-in email only reaches your Supabase team. Gmail users can reset by signing in with Google and setting a new password. For others, reset it yourself (below).

**Resetting a forgotten password (admin)**
In the SQL Editor, run with their email and a temporary password, then tell them to change it in **More → Set or change password**:
```sql
update auth.users set encrypted_password = extensions.crypt('TEMP-PASSWORD', extensions.gen_salt('bf'))
where email = 'their-email@example.com';
```
To send real reset emails instead, connect a free email service (for example Brevo) under **Authentication → Emails → SMTP Settings** and turn **Confirm email** on. That also fixes the unchecked-email issue.
- **Google consent screen:** it shows your Supabase address (`gtpwvbxtvmisbqyrppki.supabase.co`). That's expected. A custom domain can replace it, but it's a paid Supabase add-on.

**Keep your accounts safe**
- Turn on two-factor authentication for your **GitHub** and **Supabase** accounts. Anyone who gets into either can change the app or the data.
- Only the **publishable** key goes in `config.js`. Never put the **secret** or **service_role** key in any file in this repo.

**If you move to a different Supabase project**, update both `config.js` and the project address in the `Content-Security-Policy` line near the top of `index.html`. Otherwise the policy will block the connection.

## Updating the app

Upload the changed files to the repo. Phones get the new version the next time they open the app online. If you replace a file in `vendor/`, its integrity hash in `index.html` must be updated too. If you change `sw.js`, bump the `CACHE` name inside it.

## Moving your roster from the Claude version

In the old version, open **More → Backup and restore** and copy the text. In the new site, open the same screen, paste it, and tap **Restore**.

## Good to know

- **Free plan pause:** Supabase pauses a free project after about a week with little use and emails you first. Open the project and click **Resume project**; data is kept.
- **No patient information.** This app is for staff schedules only. Don't put patient names or details in notes.
