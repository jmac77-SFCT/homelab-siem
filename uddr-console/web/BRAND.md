# Branding checklist

Everything brand-related is centralized so official DigiCert assets drop in
without touching view code. Provide these and I (or you) update the marked spots.

## 1. Colors → `src/theme/tokens.css`
Replace every value marked `TODO(brand)`:
- `--brand-primary`, `--brand-primary-hover`, `--brand-primary-weak`
- `--brand-accent`, `--brand-ink`
(Official hex from the DigiCert brand guidelines.)

## 2. Logo → `public/brand/`
Drop in official SVGs (keep these filenames, or update `src/theme/brand.js`):
- `digicert-logo.svg` — horizontal lockup (top-left, ~26px tall, on dark navy)
- `digicert-mark.svg` — square mark
- `favicon.svg` — replace the placeholder shield
The sidebar auto-falls back to a text wordmark until the logo file exists.

## 3. Typeface → `src/theme/tokens.css` (`--font-sans`)
Name the official DigiCert web font. If it's licensed/self-hosted, add the
`@font-face` (or vendor CSS) and point `--font-sans` at it.

## 4. Naming → `src/theme/brand.js`
- `productName`, `company`, `supportUrl`, `defaultOrg`.

## Note on assets
No file here is an official DigiCert asset — colors and the favicon are neutral
placeholders. Do not ship this externally until the real brand assets and any
required legal/trademark review are in place.
