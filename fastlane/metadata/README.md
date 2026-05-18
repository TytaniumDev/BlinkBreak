# App Store Connect metadata

This directory is Fastlane `deliver`'s standard layout. It lets the listing
copy live in the repo under code review, and optionally lets CI push listing
updates to App Store Connect without a human clicking around the web UI.

Layout:

- `en-US/*.txt` — per-locale marketing copy (name, subtitle, description,
  keywords, promotional text, release notes, support/marketing/privacy URLs)
- `review_information/*.txt` — contact info + notes shown to App Review
- `copyright.txt`, `primary_category.txt`, `secondary_category.txt` —
  app-level metadata shared across locales

For the initial 1.0 submission, the easiest path is to paste these values
into App Store Connect by hand (the listing needs screenshots + age rating
+ pricing anyway, which aren't in this directory). After that, future
listing tweaks can be pushed from CI via `fastlane deliver --skip-screenshots`
if desired.
