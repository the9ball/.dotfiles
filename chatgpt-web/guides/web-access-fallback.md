# Web Access Fallback Guide

## When to use

When built-in web tools cannot retrieve or extract requested public content, use Desktop Commander to attempt `curl` before reporting failure or asking the user to provide the content. A successful HTTP response is **not** proof that the requested content was extracted.

## Retrieve once, preserve the response

1. Create a temporary working directory with `mktemp -d` (preferably under `/tmp`).
2. Use a GET request with a browser-like User-Agent and Accept-Language headers. Save the response body to a file, and record the HTTP status and effective URL separately. Inspect response size and type where useful.
3. Analyze the saved response locally; do not make an identical network request merely because parsing failed.
4. Do not save authentication tokens, cookies, or sensitive headers in diagnostic files. Respect authentication requirements, access restrictions, and rate limits.

Example (adapt paths and URLs to the target environment):

```sh
workdir=$(mktemp -d)
# Run cleanup when finished, including on failure.
curl -L --max-time 20 -sS \
  -A 'Mozilla/5.0' -H 'Accept-Language: ja,en;q=0.8' \
  -w 'HTTP=%{http_code} URL=%{url_effective} SIZE=%{size_download}\n' \
  -o "$workdir/response.html" 'https://example.com/page'
# Inspect "$workdir/response.html" with local parsing tools.
rm -rf -- "$workdir"
```

## Recover from extraction failure

- First inspect the **saved** response. Try alternate representations such as HTML `<title>`, Open Graph or other metadata, JSON-LD, embedded JSON, and visible page content as appropriate.
- Check whether the response is a login page, challenge, empty shell, error page, or genuinely useful content. A 200 status alone is insufficient.
- Re-fetch only if the saved response is incomplete, stale, unusable, or a different URL, endpoint, or representation is needed. Prefer a canonical URL or a legitimately public API where appropriate.
- Keep attempts bounded and purposeful; change the approach rather than repeating the same request without evidence it might succeed.

## Follow relevant references

When interpreting a post, article, or discussion, inspect relevant linked, quoted, or parent content if it is needed to answer accurately. For example, an X post may contain a quoted post represented separately in public structured data. Do not assume the primary post text is the full context. Avoid unnecessary traversal of unrelated links.

## Completion and reporting

Verify that the **requested information**, not merely an HTTP response, was retrieved. State what was confirmed, what could not be extracted, and any material limitations. If reasonable retrieval and extraction alternatives fail, report that fact without inventing content. Remove the temporary directory and its contents when the investigation ends; do not rely on files surviving across turns.
