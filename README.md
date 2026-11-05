# FindIt

FindIt is a community lost and found application built with React, TypeScript, Vite, Tailwind CSS, React Router and Supabase. It supports public listing search, authenticated reports, private contact conversations, photo uploads, and owner controlled listing management.

## Run locally

Requirements: Node.js 20+ and a Supabase project.

1. Install dependencies: `npm install`
2. Copy `.env.example` to `.env.local` and set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` from Supabase **Project Settings → API**. The anon/publishable key is intended for browser use; never put a service role key in frontend environment variables.
3. In Supabase SQL Editor, run `supabase/migrations/202611050001_findit.sql` (or apply it with Supabase CLI: `supabase db push`). The migration creates tables, indexes, constraints, RLS policies, the signup profile trigger, and the public `item-images` storage bucket with owner-scoped writes.
4. In Supabase **Authentication → URL Configuration**, set the local Site URL to `http://localhost:5173` and allow `http://localhost:5173/reset-password` as a redirect URL. Set your production URL and reset redirect in production.
5. Start the app: `npm run dev`.

The app uses Supabase Auth persistent browser sessions. Email signup creates a profile from the supplied display name. Google sign-in uses Supabase OAuth (`signInWithOAuth`) and returns to `/dashboard`. To enable it, open **Supabase Dashboard → Authentication → Providers → Google**, enable Google, and enter the OAuth client ID and secret from Google Cloud Console. Add the Supabase Auth callback URL shown in the provider settings to the Google OAuth client's authorized redirect URIs. In **Authentication → URL Configuration**, add your app's local and production `/dashboard` URLs to the allowed redirect URLs. Email password reset returns to `/reset-password`. If email confirmation is enabled, users must confirm their address before logging in.

## Admin setup

There is no public admin signup. After creating a trusted account, a project owner can grant admin access in Supabase SQL Editor with `update public.profiles set role='admin' where id='<trusted-user-uuid>';`. Admin access is checked through the `is_admin()` database function and RLS. Admins can inspect all items and reports through Supabase SQL Editor; the MVP does not include a separate admin UI.

## Privacy and safety

Only active listings are public. Item owners can see and manage their own listings. Conversations and messages are restricted to their participants by RLS. The default contact path does not reveal a poster's email or phone. Found-item contact details are not collected in the MVP; the public contact preference is stored for future UI but no sensitive contact fields are exposed. Ask users to post a general location, not a private address. Photo bucket reads are public for images attached to public listings; upload, update and delete require the authenticated user's folder.

## Current MVP scope

Listing search supports keywords, category, location and date, newest first. Dashboard supports own listing status changes and deletion. Conversations can be created from a listing, exchanged and marked read as opened. The RLS rules are the security boundary; the Supabase anon key is not a secret. Production deployment should additionally configure email delivery, CAPTCHA/rate limits, moderation operations and a published privacy/terms page.
