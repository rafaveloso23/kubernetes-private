#----------------------
# Documentation Steps
#----------------------
.PHONY: cleanup-docs

cleanup-docs: 
	@rm ./README.md

prepare-readme: 
	@echo "Preparing all Environment Documentation..."
	@terraform-docs -c ./docs/.readme.yml . > README.md
	@echo "...Done 🏁"

.PHONY: cleanup-tfvars

cleanup-tfvars:
	@rm ./terraform.tfvars

prepare-tfvars:
	@echo "Preparando arquivo de Tfvars..."
	@terraform-docs -c ./docs/.terraform-docs.yml . > terraform.tfvars
	@echo "...Done 🏁"

#--------------------------------------
# Landing Zone Terraform Creation Steps
#--------------------------------------

#Faça um login utilizando o device code:
az-login:
	az login --use-device-code

service-principal:
	export ARM_CLIENT_SECRET=$$(az ad sp create-for-rbac --name $(SERVICE_PRINCIPAL_NAME) --query password -o tsv); \
	export ARM_CLIENT_ID=$$(az ad sp list --display-name $(SERVICE_PRINCIPAL_NAME) --query '[0].appId' -o tsv); \
	export ARM_TENANT_ID=$$(az ad sp list --display-name $(SERVICE_PRINCIPAL_NAME) --query '[0].appOwnerOrganizationId' -o tsv)

base-tf:

	az group create --location $$TF_REGION --name $$TF_BACKEND_RESOURCE_GROUP

	az storage account create --resource-group $$TF_BACKEND_RESOURCE_GROUP --name $$TF_BACKEND_STORAGE_ACCOUNT --sku Standard_LRS --encryption-services blob
	
	az storage container create --name $$TF_BACKEND_CONTAINER --account-name $$TF_BACKEND_STORAGE_ACCOUNT

	az keyvault create --name $$KEY_VAULT_NAME --resource-group $$TF_BACKEND_RESOURCE_GROUP --location $$TF_REGION

	az keyvault set-policy --name $$KEY_VAULT_NAME --object-id $$ARM_CLIENT_ID --secret-permissions get list --key-permissions get list --certificate-permissions get list

	az keyvault secret set --vault-name $$KEY_VAULT_NAME --name "TF-BACKEND-STORAGE-ACCOUNT" --value $$TF_BACKEND_STORAGE_ACCOUNT
	az keyvault secret set --vault-name $$KEY_VAULT_NAME --name "TF-BACKEND-KEY" --value $$TF_BACKEND_KEY
	az keyvault secret set --vault-name $$KEY_VAULT_NAME --name "TF-BACKEND-RESOURCE-GROUP" --value $$TF_BACKEND_RESOURCE_GROUP
	az keyvault secret set --vault-name $$KEY_VAULT_NAME --name "TF-BACKEND-CONTAINER" --value $$TF_BACKEND_CONTAINER
	az keyvault secret set --vault-name $$KEY_VAULT_NAME --name "ARM-CLIENT-ID" --value $$ARM_CLIENT_ID
	az keyvault secret set --vault-name $$KEY_VAULT_NAME --name "ARM-CLIENT-SECRET" --value $$ARM_CLIENT_SECRET
	az keyvault secret set --vault-name $$KEY_VAULT_NAME --name "ARM-TENANT-ID" --value $$ARM_TENANT_ID
	az keyvault secret set --vault-name $$KEY_VAULT_NAME --name "SERVICE-PRINCIPAL-NAME" --value $$SERVICE_PRINCIPAL_NAME

#terraform init config:
terraform-init:
	terraform init -reconfigure \
	-backend-config "resource_group_name=$$TF_BACKEND_RESOURCE_GROUP" \
	-backend-config "storage_account_name=$$TF_BACKEND_STORAGE_ACCOUNT" \
	-backend-config "container_name=$$TF_BACKEND_CONTAINER" \
	-backend-config "key=$$TF_BACKEND_KEY"

#--------------------------------------
# Azure Devops Creation Steps
#--------------------------------------
##Config default Az Devops Project
#Export the env var AZURE_DEVOPS_EXT_PAT with a valid PAT, to access your Azure Devops Organization
#Validade your config using:

az-devops-project-list:
	az devops project list --org https://dev.azure.com/$$AZ_DEVOPS_ORG

#Config a default Azure Devops Project:
az-default-devops-project:
	az devops configure --defaults organization=https://dev.azure.com/$$AZ_DEVOPS_ORG project=$$AZ_DEVOPS_PROJECT