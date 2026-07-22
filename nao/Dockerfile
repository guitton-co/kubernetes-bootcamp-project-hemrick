FROM getnao/nao:latest

# nao_config.prod.yaml (default) = Cloud Run, relies on attached-SA ADC for
# BigQuery. nao_config.k8s.yaml = DO cluster build, mounts a service-account
# key instead (no ADC there) — pass --build-arg NAO_CONFIG_FILE=nao_config.k8s.yaml.
ARG NAO_CONFIG_FILE=nao_config.prod.yaml

COPY . /app/project/
COPY ${NAO_CONFIG_FILE} /app/project/nao_config.yaml

ENV NAO_DEFAULT_PROJECT_PATH=/app/project
