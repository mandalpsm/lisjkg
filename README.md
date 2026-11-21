# LIS Knowledge Graph Explorer — Full-Stack Edition

A deployable web application for exploring a Library & Information Science (LIS) journal-metadata collection
(27,825 records, 2020–2025, 100 journals) as a searchable bibliographic database **and** a knowledge graph.

| Layer | What it is |
|---|---|
| **Front end** | The single-page *Semantic KG Explorer* (`public/index.html`): Boolean/wildcard search, semantic search, 6 knowledge-graph models, Semantic Layer, dashboard, journal map, federated / linked-open-data search, Bengali–English retrieval, voice search, Evaluation Lab and **Study Lab**, accessibility panel. |
| **Back end** | A **zero-dependency Node.js server** (`server/`): REST search API, record/DOI lookup, exports (CSV, RIS, BibTeX, JSON, JSON-LD), **OAI-PMH 2.0**, type-ahead + "did you mean", read-only **Neo4j / GraphDB proxies**, security headers, rate limiting, request logging, Prometheus metrics, optional anonymous telemetry, backups. |
| **Data** | `data/dataset.json.gz` — the record set, served to the browser at `/api/dataset` (gzip, ETag cached) and indexed in memory by the server. |
| **Ops** | Dockerfile, docker-compose (with optional Neo4j / GraphDB), nginx, systemd, cron backup, smoke test, 21 automated tests. |

> **No `npm install` is needed.** The server uses only Node.js built-ins (Node **18 or newer**; developed and tested on Node 22).

---

## 1. Quick start

```bash
# 1. unzip, then:
cd lis-kg-explorer-fullstack
cp .env.example .env          # optional – everything has a default
node server/index.js          # or: npm start
```

Open **http://localhost:8080**. Startup takes about 3 seconds (the server builds its search index).

Other entry points:

| URL | Purpose |
|---|---|
| `/` | The explorer (front end) |
| `/api/docs` | Interactive API reference (generated from `docs/openapi.json`) |
| `/oai?verb=Identify` | OAI-PMH endpoint |
| `/health` | Liveness probe |
| `/journal-map.html` | The 3D journal map (also opened inside the explorer) |

Run the tests: `npm test` (about 12 seconds).

### Docker

```bash
cp .env.example .env
docker compose up -d --build                  # app only  -> http://localhost:8080
docker compose --profile neo4j up -d          # + Neo4j    (set NEO4J_PASSWORD in .env, NEO4J_URL=http://neo4j:7474)
docker compose --profile graphdb up -d        # + GraphDB  (GRAPHDB_URL=http://graphdb:7200/repositories/library)
```

---

## 2. Architecture

```
 Browser (single-page app)                         Node.js server (server/)                       Optional back ends
┌──────────────────────────────┐   /api/dataset   ┌────────────────────────────────────┐
│ index.html                   │ ───────────────► │ static files (+gzip, ETag)         │
│  • loads the dataset once    │                  │ REST API  /api/search, /records,   │
│  • client-side search, KG,   │   /api/config    │           /doi, /suggest, /export  │
│    dashboards, Study Lab     │ ◄──────────────► │ OAI-PMH   /oai                     │       ┌───────────┐
│  • journal map (iframe)      │                  │ Proxies   /api/neo4j/query ────────┼─────► │  Neo4j 5  │
└──────────────────────────────┘                  │           /api/graphdb/query ──────┼─────► │ GraphDB   │
 External open APIs (browser → OpenAlex,          │ Security headers · rate limiter ·  │       └───────────┘
 Crossref, Wikidata, DBpedia, DOAJ)               │ JSON logs · /metrics · telemetry · │
                                                  │ backup                              │
                                                  └───────────────┬────────────────────┘
                                                                  │ in-memory inverted index (built at start-up)
                                                          data/dataset.json.gz
```

Two search paths exist **by design**:

* **In the browser** the explorer searches the dataset it downloaded (fast, works offline after the first load, supports NEAR/n, Bengali glossaries, embeddings and all the analytics).
* **On the server** `/api/search` offers the same style of Boolean/phrase/wildcard retrieval to other programs (scripts, other websites, harvesters) without downloading 10 MB.

The two engines are separate implementations; their rankings are similar but not identical.

---

## 3. Project structure

```
lis-kg-explorer-fullstack/
├── server/
│   ├── index.js            HTTP server, routing, rate limits, error handling, graceful shutdown
│   ├── routes.js           All API endpoints
│   └── lib/
│       ├── config.js       Environment / .env loader
│       ├── dataset.js      Dataset loader, record model, DOI normalisation
│       ├── search.js       Inverted index, query parser, ranking, facets, spelling, type-ahead
│       ├── formats.js      RIS, BibTeX, CSV, JSON-LD, Dublin Core
│       ├── oai.js          OAI-PMH 2.0 data provider
│       ├── proxy.js        Read-only Neo4j / SPARQL proxies
│       ├── security.js     Headers (CSP, HSTS …), CORS, rate limiter, admin auth
│       ├── static.js       Safe static-file server (gzip, ETag, traversal protection)
│       ├── telemetry.js    Optional anonymous usage log + summary
│       ├── metrics.js      Prometheus metrics
│       └── backup.js       Backups with SHA-256 manifest + verification
├── public/                 index.html (front end), journal-map.html
├── data/dataset.json.gz    The collection (27,825 records)
├── docs/                   openapi.json, api-docs.html
├── scripts/                build-dataset, extract-from-standalone, backup, check-dataset, gen-openapi
├── tests/                  21 automated tests (node:test)
├── deploy/                 nginx.conf, systemd unit, cron, smoke-test.sh
├── Dockerfile · docker-compose.yml · .env.example · package.json
```

---

## 4. Configuration (`.env` or environment variables)

All settings are optional. Copy `.env.example` to `.env`; real environment variables override the file.

| Variable | Default | Meaning |
|---|---|---|
| `PORT` / `HOST` | `8080` / `0.0.0.0` | Listen address |
| `TRUST_PROXY` | `false` | Set `true` behind nginx/Cloudflare so client IP and HTTPS are taken from `X-Forwarded-*` |
| `CORS_ORIGINS` | *(empty)* | Empty = same-origin only; `*` or a comma-separated list to allow other sites to call the API |
| `RATE_LIMIT_PER_MIN` | `300` | Requests per minute per IP for `/api` and `/oai` |
| `DATASET_RATE_LIMIT_PER_MIN` | `30` | Separate, lower limit for the 10 MB `/api/dataset` download |
| `ADMIN_TOKEN` | *(empty)* | Enables `/metrics` and `/api/admin/*`. Without it these endpoints return 404 |
| `TELEMETRY` / `TELEMETRY_QUERIES` | `false` / `false` | Anonymous usage log (no IPs). Query text is stored **only** if `TELEMETRY_QUERIES=true` — tell your users first |
| `OAI_NAMESPACE`, `OAI_ADMIN_EMAIL` | example values | OAI-PMH identity — **change these** |
| `PROXY_ENABLED` | `false` | Master switch for the graph-database proxies |
| `NEO4J_URL`, `NEO4J_DB`, `NEO4J_USER`, `NEO4J_PASSWORD`, `NEO4J_ALLOW_WRITE` | — / `neo4j` / … / `false` | Neo4j HTTP (Query API v2) connection; write queries blocked unless allowed |
| `GRAPHDB_URL`, `GRAPHDB_USER`, `GRAPHDB_PASSWORD` | — | SPARQL repository endpoint, e.g. `http://localhost:7200/repositories/library` |
| `DATA_FILE`, `PUBLIC_DIR`, `LOG_DIR`, `BACKUP_DIR`, `BACKUP_KEEP` | `data/dataset.json.gz`, `public`, `logs`, `backups`, `14` | Paths and backup retention |

Generate an admin token: `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`

---

## 5. API reference (summary)

Full, browsable documentation is at **`/api/docs`**; the machine-readable spec is `/api/openapi.json`.

### Search — `GET /api/search`

```
/api/search?q=digital+libraries&size=10&facets=1
/api/search?q="open access" AND (india OR bangladesh)&year_from=2022&sort=cites
/api/search?q=title:bibliometric year:2023
```

**Query language:** implicit `AND`; `OR`; `NOT` or `-term`; `"exact phrase"`; truncation `librar*`; single-character wildcard `organi?ation`; grouping `( … )`;
field prefixes `title:` `author:` `keyword:` `abstract:` `source:` `year:2020` / `year:2020-2024` `doi:10.xxxx/yyyy`.

| Parameter | Meaning |
|---|---|
| `q` | Query (max 500 characters) |
| `page`, `size` | Pagination (size 1–100, default 20) |
| `sort` | `relevance` (default), `cites`, `newest`, `oldest`, `title` |
| `expand` | `false` turns off synonym / abbreviation expansion (e.g. *AI* ↔ *artificial intelligence*) |
| `facets` | `1` adds year / source / publisher / country counts |
| `year_from`, `year_to`, `source`, `publisher`, `country`, `subject`, `min_cites`, `has_doi` | Filters |

The response contains `total`, `results[]` (with `score`), `didYouMean`, the parsed query, and `tookMs`.

### Other endpoints

| Endpoint | Purpose |
|---|---|
| `GET /api/records/{id}?format=json\|jsonld\|ris\|bibtex\|dc` | One record. `Accept: application/ld+json` also works |
| `GET /api/doi/{doi}` | Lookup by DOI (`10.1108/dlp-05-2020-0030` or a `https://doi.org/…` URL) |
| `GET /api/suggest?q=biblio` | Type-ahead terms + spelling suggestion |
| `GET /api/authors?q=majhi` | Author-name lookup |
| `GET /api/export?format=csv\|ris\|bibtex\|json\|jsonld&q=…&limit=1000` | Download results (max 5,000) or `ids=1,2,3` |
| `GET /api/meta` | Collection statistics and facet values |
| `GET /api/dataset` | Whole dataset (gzip JSON) — used by the front end |
| `GET /oai` | OAI-PMH 2.0 |
| `GET /health`, `GET /api/config` | Probes and public configuration |

**Record ids are positions in the dataset file.** They are stable until you rebuild or reorder the dataset. For permanent references use the **DOI**.

### OAI-PMH

```
/oai?verb=Identify
/oai?verb=ListSets                                   (one set per journal: src0, src1, …)
/oai?verb=ListRecords&metadataPrefix=oai_dc&from=2023-01-01&until=2023-12-31
/oai?verb=GetRecord&metadataPrefix=oai_dc&identifier=oai:<OAI_NAMESPACE>:123
```

Only `oai_dc` is offered; pages hold 100 records with resumption tokens. Because the dataset stores only the publication **year**, the datestamp of each record is `<year>-01-01`, and incremental harvesting by date is therefore coarse.

### Graph-database proxies

`POST /api/neo4j/query` `{ "query": "MATCH …", "parameters": {} }` and `POST /api/graphdb/query` `{ "query": "SELECT …" }`.
The front end's **Neo4j + GraphDB** panel uses these automatically ("Backend proxy" mode is pre-selected). Credentials live only in `.env`.

* Cypher is **read-only** by default (`CREATE`, `MERGE`, `DELETE`, `SET`, `REMOVE`, `LOAD CSV`, `CALL dbms…` etc. are rejected with 403). Set `NEO4J_ALLOW_WRITE=true` only on a private network.
* SPARQL accepts `SELECT`, `ASK`, `CONSTRUCT`, `DESCRIBE` only; updates and federated `SERVICE` clauses are rejected.
* These endpoints can still run expensive read queries. **Put authentication in front of them** (see `deploy/nginx.conf`) before exposing the site publicly.
* To load the data **into** the databases use the front end's Export (Cypher / Turtle) and import them with the database tools, as described in the in-app "Neo4j + GraphDB" help.

---

## 6. Data: updating or replacing the collection

**From a CSV export** (header names are case-insensitive; `Title` and `Year` are required):

```bash
node scripts/build-dataset.js path/to/kg_dataset.csv        # writes data/dataset.json.gz
node scripts/check-dataset.js                               # structural validation + quality report
# restart the server
```

Recognised columns: `Cites, Authors, Title, Year, Source, Publisher, Place, Country, ArticleURL, DOI, ISSN, Keywords, Abstract`
(`;` or `,` delimiter is detected; authors separated by `;`; keywords by `;` or `,`).

**From the single-file edition** (after you edit the standalone HTML): 

```bash
node scripts/extract-from-standalone.js path/to/LIS-KG-Explorer-complete.html
```

This rewrites `data/dataset.json.gz`, `public/journal-map.html` and `public/index.html` (payloads removed, server hooks added).

> The front end also lets users upload their own dataset in the browser. That affects only that browser session; the server's data are changed only by the commands above.

---

## 7. Operations

### Security (built in)

* Content-Security-Policy, `X-Content-Type-Options`, `Referrer-Policy`, `X-Frame-Options`, `Permissions-Policy`; HSTS when served over HTTPS.
* Per-IP rate limiting (HTTP 429 + `Retry-After`), request-size limits (HTTP 413), request timeouts.
* Path-traversal and dotfile protection for static files (tested).
* Admin endpoints disabled unless `ADMIN_TOKEN` is set; token compared in constant time.
* Database proxies: read-only guards, server-side credentials, response-size cap and timeouts.
* The CSP allows inline scripts (`'unsafe-inline'`) because the single-page front end is one HTML file with inline code, and `https:` connections because it queries open scholarly APIs. Tighten these if you strip those features.

### Monitoring

* JSON access/error logs on stdout (`docker compose logs -f app`, `journalctl -u lis-kg-explorer -f`).
* `GET /metrics` (Prometheus text format; needs `Authorization: Bearer <ADMIN_TOKEN>`): request counts, latency histogram, uptime, memory, record count.
* Optional telemetry (`TELEMETRY=true`): the front end sends result counts and response times to `/api/telemetry`; files are written to `logs/telemetry-YYYY-MM-DD.jsonl`. Summary: `GET /api/admin/telemetry-summary?days=7` (searches, zero-result rate, search success rate, median and p95 response time).
  Telemetry needs a privacy notice if you enable `TELEMETRY_QUERIES`.

### Backup and restore

```bash
node scripts/backup.js                     # dataset + logs -> backups/<timestamp>/ with MANIFEST.json (SHA-256); keeps newest 14
node scripts/backup.js verify backups/<timestamp>
crontab deploy/backup.cron                 # nightly at 02:30 (edit the path first)
```

Restore = copy `backups/<timestamp>/data/dataset.json.gz` back to `data/` and restart.
Back up Neo4j and GraphDB with their own tools (`neo4j-admin database dump`, GraphDB backup) — this project does not do that for you.
Users' personal browser data (saved items, notes, study results) can be backed up from **Study Lab → Maintenance & audit → Backup**.

### Deployment (production checklist)

1. Run behind HTTPS: `deploy/nginx.conf` (set `TRUST_PROXY=true`), or any reverse proxy / managed platform.
2. Run as a service: Docker (`restart: unless-stopped`) or `deploy/lis-kg-explorer.service`.
3. Set `ADMIN_TOKEN`, `OAI_NAMESPACE`, `OAI_ADMIN_EMAIL`; decide on `CORS_ORIGINS` and telemetry.
4. If you enable the proxies, protect `/api/neo4j/*` and `/api/graphdb/*` (nginx `auth_basic` example included).
5. Schedule backups; test one restore.
6. Run `sh deploy/smoke-test.sh https://your-domain`.

### Capacity

Measured on the shipped dataset (27,825 records): index build ≈ 2.5 s, ≈ 150 MB JS heap, typical queries 5–70 ms. Everything is held in memory in one process, which is comfortable up to a few hundred thousand records. For millions of records, or many concurrent heavy users, replace `server/lib/search.js` with a dedicated engine (OpenSearch / Elasticsearch / Meilisearch) and keep the same routes. The browser edition downloads the whole dataset (≈ 10 MB gzip); that is also the practical size limit of the in-browser features.

---

## 8. Testing

```bash
npm test
```

21 tests cover: health/config; security headers; every query operator; filters/facets/sorting/pagination; synonym expansion; spelling and type-ahead; record, DOI and all export formats; the dataset download (gzip + ETag); OAI-PMH verbs, errors and resumption tokens; static-file traversal protection; error handling; rate limiting and CORS; admin auth; telemetry privacy; backup verification (including tamper detection); the Neo4j and SPARQL proxy guards (against a stub database); and CSV → dataset conversion.

The browser front end itself has no automated tests in this package; it was exercised manually/with a headless browser against this server (dataset load via `/api/dataset`, search, "did you mean", Study Lab, journal map).

---

## 9. What this edition adds, and what it does not

**Adds to the single-file edition:** a real server (REST API, OAI-PMH, JSON-LD/RIS/BibTeX/CSV export), server-side graph-database proxies with credentials kept off the browser, security headers and rate limiting, logging/metrics/telemetry, verified backups, containerised deployment, a repeatable data pipeline (CSV → dataset) and automated tests.

**Does not include (be aware):**

* **No user accounts, shared workspaces or server-side storage of users' saved items.** Those still live in each user's browser (local storage); use the backup tool in the Study Lab.
* **No SPARQL endpoint of its own.** RDF/Turtle can be exported from the front end and loaded into GraphDB; the proxy then queries *your* GraphDB.
* **No full-text search engine, no horizontal scaling.** One Node process, in-memory index.
* **OAI-PMH:** `oai_dc` only; year-level datestamps; no deleted-record tracking.
* **Server search differs from browser search:** no NEAR/n, no Bengali/Hindi glossary translation, no embedding ("semantic") ranking on the server.
* **Docker, docker-compose, nginx and systemd files were written to standard practice but could not be run in the environment where this package was built** (no Docker daemon, no internet). Test them in your environment; `deploy/smoke-test.sh` helps. The Node server, API, OAI-PMH, proxy guards, scripts and tests *were* executed and pass.
* **No real-user usability study results are included.** The Study Lab collects them; running the study is up to you.
* The front end calls third-party services directly from the browser (OpenAlex, Crossref, Wikidata, DBpedia, DOAJ, Google Fonts, cdnjs). Offline or firewalled installations will lose those features (the core search still works).
* No software licence has been chosen — see `LICENSE-NOTE.txt`.

---

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| Page shows "Loading…" forever | Open `/api/dataset` in a new tab. If it fails, check `DATA_FILE` and the server log. |
| `Dataset request failed (HTTP 429)` | Rate limit hit; raise `DATASET_RATE_LIMIT_PER_MIN` or wait a minute. |
| Neo4j / GraphDB panel: "Proxy 503" | Set `PROXY_ENABLED=true` and the database URL variables, restart. |
| Proxy 403 "Write clause blocked" | By design. Use read queries, or `NEO4J_ALLOW_WRITE=true` on a private deployment. |
| Everyone shares one rate-limit bucket / wrong IP in logs | Behind a reverse proxy set `TRUST_PROXY=true`. |
| Mixed-content or HSTS missing behind HTTPS proxy | Pass `X-Forwarded-Proto` (see `deploy/nginx.conf`) and set `TRUST_PROXY=true`. |
| `/metrics` returns 404 | `ADMIN_TOKEN` is not set (intentional). |
| Journal map blank | It loads three.js from cdnjs; allow `https://cdnjs.cloudflare.com` or serve the library locally and adjust the CSP in `server/lib/security.js`. |
| Port already in use | Change `PORT`. |

---

*Generated for the LIS Knowledge Graph Explorer project. Version 1.0.0.*
