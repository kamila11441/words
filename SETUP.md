# Our Words — set up for your family

This is an installable web app. Family members use one shared link, choose their profile (photo and name), and sign in with its password. Signup uses an email behind the scenes for password recovery; it is not shown on the profile cards. There are four accounts total. Each person can sign in and tap their own round profile picture in the header to choose or change a photo. Their photo then appears beside their name on the sign-in screen. Until they upload one, their profile shows an initial. Anyone can edit or delete entries they added; the first account (admin) can also delete entries added by anyone else. All family members can see all entries and who contributed them.

The sign-in page also has a **Browse as guest** option. Guests can search and read all dictionary entries and contributor names, but cannot add, edit, or delete anything. This guest view is public to anyone who can access the app link; do not use it for entries you want kept private.

## 1. Create the shared database

1. Create a free project at [Supabase](https://supabase.com/).
2. In **SQL Editor**, run the complete contents of `schema.sql`.
3. In **Project Settings → API**, copy the Project URL and public `anon` key. The `anon` key is intended for browser apps; never use a `service_role` key here.
4. Open `app.js` and replace `YOUR_SUPABASE_URL` and `YOUR_SUPABASE_ANON_KEY` with those two values.
5. Install the Supabase CLI, link your project, then deploy the included Edge Function: `supabase functions deploy profile-login`. It uses Supabase's server-side service key in the function environment; never put that key in `app.js`.
6. In Supabase **Authentication → URL Configuration**, set the site URL and redirect URL to the final hosted app URL.
7. For easiest family signup, turn off email confirmation in **Authentication → Providers → Email**. Otherwise each new family member needs to confirm their email before signing in. Share the app link privately with the four family members.

The very first account created becomes the admin. Create the first profile as **Kamila** so Kamila is the admin. The admin can change the shared W app mark by clicking it in the header and choosing an image (up to 2 MB). This updates the mark shown in the app for all members. The admin is the only one allowed to delete entries created by other family members. The four-account limit is enforced in the database, including when accounts are created at the same time. Profile names and pictures are visible on the sign-in screen so members can choose their account; emails remain private.

## 2. Publish the app

The simplest route is GitHub Pages: create a private or public GitHub repository, upload the files in this folder to its root, then enable **Settings → Pages → Deploy from a branch** and select `main` / `/ (root)`. GitHub Pages serves over HTTPS, which allows installation on phones. Any update committed to the published branch appears on the shared link after deployment; installed copies check for updates when reopened. (A page already open may need a refresh.)

If you prefer, Vercel or Netlify can host the same static files. Keep the Supabase project configured as above. Supabase stores the family data; GitHub Pages only serves the app files.

## 3. Install on phones

- **iPhone/iPad:** open the link in Safari, tap Share, then **Add to Home Screen**.
- **Android:** open the link in Chrome, tap **Install app** or **Add to Home screen**.

## Notes

- This first version requires the internet to read and save shared entries. The app shell is cached for faster loading; dictionary data is stored securely in Supabase.
- The app uses Supabase JS from its CDN, so sign-in requires an internet connection.
- To change the admin later, use Supabase SQL Editor while signed in as the project owner: `update public.profiles set is_admin = true where id = 'USER_UUID';` Then remove admin from the old profile if needed. Do not make this query available to family members.
- This project currently supports one shared family dictionary with a maximum of four accounts.
