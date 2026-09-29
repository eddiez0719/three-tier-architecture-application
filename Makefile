ENV ?= dev
REGION := ap-southeast-2
APP := orderhub
TAG := v1
TF := terraform -chdir=envs/$(ENV)
MON_TF := terraform -chdir=monitoring
.PHONY: help check push apply output test destroy clean-ecr monitor load errors monitor-destroy

help:
	@echo "make check"
	@echo "make push"
	@echo "make apply" ENV=dev
	@echo "make output" ENV=dev
	@echo "make test" ENV=dev
	@echo "make destroy" ENV=dev
	@echo "make clean-ecr"
	@echo "make monitor ENV=dev EMAIL=you@example.com"
	@echo "make load ENV=dev"
	@echo "make errors ENV=dev"
	@echo "make monitor-destroy ENV=dev"

check:
	@echo "Checking environment: $(ENV)"

push:
	@set -e; \
	REGISTRY=$$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$(REGION).amazonaws.com; \
	aws ecr describe-repositories --repository-names $(APP) --region $(REGION) >/dev/null 2>&1 || aws ecr create-repository --repository-name $(APP) --region $(REGION) >/dev/null; \
	aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $$REGISTRY; \
	docker build --platform linux/amd64 -t $$REGISTRY/$(APP):$(TAG) ./app; \
	docker push $$REGISTRY/$(APP):$(TAG)

apply:
	$(TF) init
	$(TF) plan
	$(TF) validate
	$(TF) apply -auto-approve

output:
	$(TF) output

test:
	@set -e; \
	URL=$$($(TF) output -raw alb_url); \
	echo "== GET /";                 curl -s "$$URL/"; \
	echo "== POST /api/orders";      curl -s -X POST "$$URL/api/orders" -H 'Content-Type: application/json' -d '{"customer":"Alice","item":"Laptop","quantity":2}'; \
	echo "== POST /api/orders";      curl -s -X POST "$$URL/api/orders" -H 'Content-Type: application/json' -d '{"customer":"Bob","item":"Monitor","quantity":1}'; \
	echo "== GET /api/orders";       curl -s "$$URL/api/orders"; \
	echo "== GET /api/orders/1";     curl -s "$$URL/api/orders/1"; \
	echo "== POST quantity=0 (400)"; curl -s -X POST "$$URL/api/orders" -H 'Content-Type: application/json' -d '{"customer":"Bob","item":"Mouse","quantity":0}'; \
	echo "== GET / x6 (host)";       for n in 1 2 3 4 5 6; do curl -s "$$URL/"; done

destroy:
	$(TF) destroy -auto-approve

clean-ecr:
	aws ecr delete-repository --repository-name $(APP) --region $(REGION) --force

monitor:
	@test -n "$$GRAFANA_URL" -a -n "$$GRAFANA_AUTH" || { echo "export GRAFANA_URL and GRAFANA_AUTH first"; exit 1; }
	@test -n "$(EMAIL)" || { echo "usage: make monitor ENV=$(ENV) EMAIL=you@example.com"; exit 1; }
	$(MON_TF) init -input=false -reconfigure -backend-config="key=$(ENV)/monitoring/terraform.tfstate"
	$(MON_TF) apply -auto-approve -var="env=$(ENV)" -var="alert_email=$(EMAIL)"

load:
	@URL=$$($(TF) output -raw alb_url); \
	for n in $$(seq 1 100); do \
	  curl -s -o /dev/null -X POST "$$URL/api/orders" -H 'Content-Type: application/json' -d '{"customer":"Load","item":"Keyboard","quantity":1}'; \
	  curl -s -o /dev/null "$$URL/api/orders"; \
	done; \
	echo "sent 200 requests to $$URL"

errors:
	@URL=$$($(TF) output -raw alb_url); \
	for n in $$(seq 1 60); do \
	  curl -s -o /dev/null -X POST "$$URL/api/orders" -H 'Content-Type: application/json' -d '{"customer":"Bad","item":"Mouse","quantity":0}'; \
	done; \
	echo "sent 60 bad requests (HTTP 400) to $$URL"

monitor-destroy:
	@test -n "$$GRAFANA_URL" -a -n "$$GRAFANA_AUTH" || { echo "export GRAFANA_URL and GRAFANA_AUTH first"; exit 1; }
	$(MON_TF) init -input=false -reconfigure -backend-config="key=$(ENV)/monitoring/terraform.tfstate"
	$(MON_TF) destroy -auto-approve -var="env=$(ENV)" -var="alert_email=unused@example.com"
