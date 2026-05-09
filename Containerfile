ARG FRAPPE_BRANCH=version-16
ARG FRAPPE_IMAGE_PREFIX=frappe

FROM ${FRAPPE_IMAGE_PREFIX}/build:${FRAPPE_BRANCH} AS builder

ARG FRAPPE_BRANCH=version-16
ARG FRAPPE_PATH=https://github.com/frappe/frappe
ARG CACHE_BUST=""

USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
  && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg \
  && . /etc/os-release \
  && echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends postgresql-16 postgresql-client-16 redis-server gzip \
  && rm -rf /var/lib/apt/lists/*

COPY --chown=frappe:frappe scripts /opt/frappe/scripts
RUN chmod +x /opt/frappe/scripts/*.sh

USER frappe

RUN --mount=type=secret,id=apps_json,target=/opt/frappe/apps.json,uid=1000,gid=1000 \
  : "${CACHE_BUST}" && \
  bench init --apps_path=/opt/frappe/apps.json \
    --frappe-branch=${FRAPPE_BRANCH} \
    --frappe-path=${FRAPPE_PATH} \
    --no-procfile \
    --no-backups \
    --skip-redis-config-generation \
    --verbose \
    /home/frappe/frappe-bench && \
  cd /home/frappe/frappe-bench && \
  python /opt/frappe/scripts/patch_hrms_postgres.py && \
  /opt/frappe/scripts/write_runtime_files.sh && \
  /opt/frappe/scripts/build_seed.sh && \
  find apps -mindepth 1 -path "*/.git" | xargs rm -fr

FROM ${FRAPPE_IMAGE_PREFIX}/build:${FRAPPE_BRANCH} AS runtime

USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl gnupg nodejs \
  && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg \
  && . /etc/os-release \
  && echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends postgresql-client-16 gzip \
  && rm -rf /var/lib/apt/lists/*

USER frappe

COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench
COPY --from=builder --chown=frappe:frappe /opt/frappe/seed /opt/frappe/seed
COPY --from=builder --chown=frappe:frappe /opt/frappe/scripts/restore_seed_site.sh /usr/local/bin/restore-seed-site
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

USER root
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/restore-seed-site

USER frappe
WORKDIR /home/frappe/frappe-bench

VOLUME [ "/home/frappe/frappe-bench/sites", "/home/frappe/frappe-bench/logs" ]
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD [ "/home/frappe/frappe-bench/env/bin/gunicorn", \
  "--chdir=/home/frappe/frappe-bench/sites", \
  "--bind=0.0.0.0:8000", \
  "--threads=4", \
  "--workers=2", \
  "--worker-class=gthread", \
  "--worker-tmp-dir=/dev/shm", \
  "--timeout=120", \
  "--preload", \
  "frappe.app:application" ]
