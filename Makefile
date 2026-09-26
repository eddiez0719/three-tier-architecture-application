ENV ?= dev
REGION := ap-southeast-2
APP := orderhub
TAG := v1
TF := terraform -chdir=envs/$(ENV)
.PHONEY: help check push apply output test destroy clean-ecr

help:
	@echo "make check"
	@echo "make push"
	@echo "make apply" ENV=dev
	@echo "make output" ENV=dev
	@echo "make test" ENV=dev
	@echo "make destroy" ENV=dev
	@echo "make clean-ecr"

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