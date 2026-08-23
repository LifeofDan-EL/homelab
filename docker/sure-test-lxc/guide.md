# Sure Test Environment — Quick Reference

Test LXC: `sure-test-lxc` (`192.168.8.31`), separate from production (`sure_app` on LXC 101).
Compose project lives at `~/sure-test` on the test LXC, source at `~/sure-test/repo`.
Managed as a Portainer stack named `sure-test` (Environments → sure-test-lxc → Stacks → sure-test).

**Important:** Portainer's remote build over the agent connection is broken (BuildKit/HTTP2 error).
Images must always be built manually via SSH, then referenced in compose with `image:` — never `build:`.

---

## Testing a branch or PR

SSH into the test LXC:

```bash
cd ~/sure-test/repo
git fetch origin

# for a regular branch:
git checkout <branch-name>
git pull

# for a PR that isn't a branch on the main repo (i.e. from a fork):
git fetch origin pull/<PR_NUMBER>/head:pr-<PR_NUMBER>
git checkout pr-<PR_NUMBER>

docker build -t sure-test:<branch-or-pr-tag> .
```

Then update the compose file's `image:` lines for `web` and `worker`:

```yaml
image: sure-test:<branch-or-pr-tag>
```

Redeploy in Portainer: **sure-test-lxc → Stacks → sure-test → Editor** → paste updated compose → **Update the stack**.

---

## Testing a specific release version

Same flow, using the release tag instead of a branch:

```bash
cd ~/sure-test/repo
git fetch --tags origin
git checkout v0.7.4-alpha.7        # swap in the tag you want

docker build -t sure-test:v0.7.4-alpha.7 .
```

Update compose `image:` to match the tag, redeploy via Portainer as above.

---

## Full compose reference

```yaml
version: '3.8'
x-db-env: &db_env
  POSTGRES_USER: ${POSTGRES_USER}
  POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
  POSTGRES_DB: ${POSTGRES_DB}
x-rails-env: &rails_env
  <<: *db_env
  SECRET_KEY_BASE: ${SECRET_KEY_BASE}
  SELF_HOSTED: "true"
  RAILS_FORCE_SSL: "false"
  RAILS_ASSUME_SSL: "false"
  HOST: ${HOST_NAME}
  DB_HOST: sure_test_db
  DB_PORT: 5432
  REDIS_URL: redis://sure_test_redis:6379/1
  SMTP_ADDRESS: ${SMTP_ADDRESS}
  SMTP_PORT: ${SMTP_PORT}
  SMTP_USERNAME: ${SMTP_USERNAME}
  SMTP_PASSWORD: ${SMTP_PASSWORD}
  SMTP_TLS_ENABLED: ${SMTP_TLS_ENABLED}
  EMAIL_SENDER: ${EMAIL_SENDER}
  APP_DOMAIN: ${APP_DOMAIN}
services:
  web:
    image: sure-test:<tag>          # <-- update per test
    container_name: sure_test_web
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - app_storage:/rails/storage
    environment:
      <<: *rails_env
    depends_on:
      sure_test_db:
        condition: service_healthy
      sure_test_redis:
        condition: service_healthy
    networks:
      - sure_test_net
  worker:
    image: sure-test:<tag>          # <-- update per test, match web
    container_name: sure_test_worker
    restart: unless-stopped
    command: bundle exec sidekiq
    volumes:
      - app_storage:/rails/storage
    environment:
      <<: *rails_env
    depends_on:
      sure_test_db:
        condition: service_healthy
      sure_test_redis:
        condition: service_healthy
    networks:
      - sure_test_net
  sure_test_db:
    image: postgres:16
    container_name: sure_test_db
    restart: unless-stopped
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      <<: *db_env
    healthcheck:
      test: [ "CMD-SHELL", "pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB" ]
      interval: 5s
      timeout: 5s
      retries: 5
    networks:
      - sure_test_net
  sure_test_redis:
    image: redis:latest
    container_name: sure_test_redis
    restart: unless-stopped
    volumes:
      - redis_data:/data
    healthcheck:
      test: [ "CMD", "redis-cli", "ping" ]
      interval: 5s
      timeout: 5s
      retries: 5
    networks:
      - sure_test_net
volumes:
  app_storage:
  postgres_data:
  redis_data:
networks:
  sure_test_net:
    name: sure_test_net
    driver: bridge
```

---

## Useful checks

**Logs (per service):**
```bash
cd ~/sure-test
docker compose logs -f web
docker compose logs -f worker
docker compose logs -f sure_test_db
docker compose logs -f sure_test_redis
```

**Rails console (debugging):**
```bash
docker compose exec web bin/rails console
```

**One-off command without staying in console:**
```bash
docker compose exec web bin/rails runner 'puts SomeModel.find("...").status'
```

**Confirm running containers / health:**
```bash
docker compose ps
```

**Confirm no duplicate/orphaned volumes after a Portainer redeploy:**
```bash
docker volume ls | grep -i sure
```
Should always show exactly 3: `sure-test_app_storage`, `sure-test_postgres_data`, `sure-test_redis_data`.

---

## Resetting test data

If a branch's migrations leave the DB in a broken state and you want a clean slate:

```bash
cd ~/sure-test
docker compose down -v   # WARNING: wipes app_storage, postgres_data, redis_data
docker compose up -d
```

Only do this when you're fine losing all test data — there's no undo.
