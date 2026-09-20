# Simplified Chinese dashboard localisation

Turns the Netdata Agent's local dashboard (`http://<host>:19999`) into a Simplified Chinese UI.

## Why this exists

The Agent does not build its own dashboard. During configure, `bundle_dashboard()` in
`packaging/cmake/Modules/NetdataDashboard.cmake` downloads a prebuilt React SPA from
`https://app.netdata.cloud/agent.tar.gz` and installs it verbatim.

That bundle contains no internationalisation layer at all: no `i18next`, no `react-intl`, no message
catalogs. The locale selector you can find in the dashboard's user settings only chooses the locale
used for `Intl` date and number formatting — it does not change any wording. The dashboard's source
is not public, so localisation cannot be done in the frontend source.

This directory therefore localises the **installed artifacts**: a small script translates the
rendered DOM in the browser using an exact-match dictionary.

## Contents

| File | Role |
|---|---|
| `zh-CN.js` | Runtime translator. Walks text nodes and a few user-visible attributes, then keeps up with React re-renders through a `MutationObserver`. |
| `zh-CN.json` | The dictionary: English string → Simplified Chinese. Flat, hand-editable. |
| `apply-zh-cn.sh` | Installs both files into a dashboard web directory and references the script from every HTML entry point. Idempotent, reversible. |

Only strings that appear as **keys in `zh-CN.json`** are ever replaced. Anything the dictionary does
not know is left exactly as the dashboard rendered it, so the dictionary can never corrupt code or
data that happens to share wording with the UI.

## Applying it

To an existing installation:

```sh
packaging/dashboard-i18n/apply-zh-cn.sh /usr/share/netdata/web
```

To a running container:

```sh
docker cp packaging/dashboard-i18n/. <container>:/tmp/dashboard-i18n/
docker exec <container> sh /tmp/dashboard-i18n/apply-zh-cn.sh /usr/share/netdata/web
```

Preview without writing, or revert:

```sh
packaging/dashboard-i18n/apply-zh-cn.sh --dry-run  /usr/share/netdata/web
packaging/dashboard-i18n/apply-zh-cn.sh --uninstall /usr/share/netdata/web
```

Builds from this repository apply the localisation automatically, right after the dashboard tarball
is extracted. Disable it with `-DENABLE_DASHBOARD_ZH_CN=OFF`.

**After applying, hard-reload the dashboard.** The Agent serves the dashboard's HTML with
`Cache-Control: public` and a one-day expiry, so a browser that already visited the page keeps
showing the cached English version until the cache is bypassed.

## Extending the dictionary

Add an entry to `zh-CN.json` and reload the page — there is no build step.

```json
"Anomaly Rate": "异常率"
```

Keys must match the string **exactly** as the dashboard renders it in a single text node, including
capitalisation (`Sign in`, `Sign In` and `Sign-in` are three different keys in this dashboard).
Values are substituted verbatim.

To find the exact wording of something you want to translate, open the browser console on the
dashboard and inspect the element, or run:

```js
[...document.querySelectorAll('*')].flatMap(e => [...e.childNodes])
  .filter(n => n.nodeType === 3 && n.nodeValue.trim()).map(n => n.nodeValue.trim())
```

## Scope and known limitations

Localised: navigation, tabs, buttons, table headers, empty states, dialogs, the time-range picker,
user settings, the welcome and claim pages, and the agent info page.

Deliberately **not** localised:

- Chart titles, metric names, dimension names, collector and service names. These are data, not UI
  chrome: they are what you search for, what appears in the API, and what the agent's own metadata
  defines. Translating them would make the UI disagree with everything else you query.
- Product names (`Netdata`), protocol and technology names (`CPU`, `IPC`, `Shell`, `Web`), and
  plugin/library identifiers.

Known limitations:

- **Composed sentences are not translated.** The dashboard builds many labels from several sibling
  text nodes, for example `Group by` + `dimension`, or `Showing` + `300` + `of total` + `300` +
  `charts`. Each fragment is a separate node, so exact matching cannot translate the sentence, and
  translating the fragments individually would produce broken Chinese. These lines stay in English.
- **Values embedded in a string.** `Total Servers: 1` is a single node containing the count, so it
  only matches that exact count and is therefore not in the dictionary.
- The dictionary is a growing asset. Wording that upstream adds later, or screens not yet covered,
  stay English until an entry is added.
- Dashboard wording changes when Netdata ships a new bundle. Missing translations are the only
  failure mode: the script never breaks a page, and a dictionary that cannot be loaded is reported
  in the console and degrades to an untranslated dashboard.
