# Security hardening

This project is a static browser app. Any password check or Supabase publishable key in these HTML files can be inspected by visitors, so database protection must be enforced in Supabase with Row Level Security (RLS) or moved behind a server/API.

## Already adjusted in this repo

- Access passwords are no longer stored as clear text in the HTML files.
- The portaria residents query now requests only the fields it uses.

These changes do not replace RLS. They only reduce accidental exposure in the repository.

## Required Supabase review

Check these tables in Supabase:

- `moradores`
- `encomendas`

For each table:

1. Enable Row Level Security.
2. Avoid broad public `select`, `update`, or `insert` policies for the `anon` role.
3. If this app must stay static, allow only the smallest possible anonymous actions:
   - resident signup can insert into `moradores`;
   - resident signup can check whether one apartment already exists;
   - package confirmation can update only the package id in the confirmation link;
   - portaria/admin actions should move to an authenticated server endpoint before being trusted.

## Stronger fix

Move Supabase reads/writes for `portaria.html` and `admin.html` to a backend endpoint or Supabase Edge Function protected by server-side authentication. Client-side passwords should be treated only as a convenience screen, not as data security.
