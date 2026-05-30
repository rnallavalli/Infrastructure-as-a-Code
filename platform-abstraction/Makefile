.PHONY: help validate generate plan apply deploy destroy clean

CONFIG ?= app-config.yaml
TF_DIR = ../terraform

help: ## Show available commands
	@echo ""
	@echo "  Platform Abstraction Layer - Developer Commands"
	@echo "  ================================================"
	@echo ""
	@echo "  make validate    Validate your app-config.yaml"
	@echo "  make generate    Generate Terraform vars from YAML"
	@echo "  make plan        Generate + terraform plan"
	@echo "  make deploy      Generate + terraform apply (full deploy)"
	@echo "  make destroy     Tear down infrastructure"
	@echo "  make dry-run     Preview generated config without writing"
	@echo "  make clean       Remove generated files"
	@echo ""

validate: ## Validate app-config.yaml without generating
	@python3 scripts/generate.py --config $(CONFIG) --validate-only

generate: ## Generate terraform.tfvars from app-config.yaml
	@python3 scripts/generate.py --config $(CONFIG)

dry-run: ## Preview what would be generated
	@python3 scripts/generate.py --config $(CONFIG) --dry-run

plan: generate ## Generate config + run terraform plan
	@cd $(TF_DIR) && terraform init -upgrade -input=false
	@cd $(TF_DIR) && terraform plan \
		-var-file=environments/$$(grep environment $(CONFIG) | head -1 | awk '{print $$2}' | tr -d '"').tfvars \
		-out=tfplan

apply: generate ## Generate config + run terraform apply
	@cd $(TF_DIR) && terraform init -upgrade -input=false
	@cd $(TF_DIR) && terraform apply -auto-approve tfplan

deploy: plan apply ## Full deployment (generate + plan + apply)

destroy: ## Destroy all infrastructure
	@cd $(TF_DIR) && terraform destroy \
		-var-file=environments/$$(grep environment $(CONFIG) | head -1 | awk '{print $$2}' | tr -d '"').tfvars

clean: ## Remove generated files
	@rm -f $(TF_DIR)/environments/*.tfvars
	@rm -f $(TF_DIR)/tfplan
	@echo "  Cleaned generated files"
