#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default cluster name
CLUSTER_NAME="yodhin"

# Function to display menu
show_menu() {
    clear
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}      Kind Cluster Full Management Menu${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo -e "Current cluster: ${YELLOW}${CLUSTER_NAME}${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo -e "1. Set cluster name (current: ${YELLOW}${CLUSTER_NAME}${NC})"
    echo -e "2. Create Kind cluster and namespace 'has'"
    echo -e "3. Deploy Apache deployment with 2 replicas and NodePort 31000"
    echo -e "4. Install Argo CD using Helm"
    echo -e "5. Delete Kind cluster"
    echo -e "6. Exit"
    echo -e "${BLUE}===========================================${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to pause execution
pause() {
    echo -e "${YELLOW}Press any key to continue...${NC}"
    read -n 1 -s
}

# Function to set cluster name
set_cluster_name() {
    echo -e "${YELLOW}Current cluster name: ${CLUSTER_NAME}${NC}"
    read -p "Enter new cluster name: " new_name
    
    if [ -n "$new_name" ]; then
        CLUSTER_NAME="$new_name"
        echo -e "${GREEN}Cluster name set to: ${CLUSTER_NAME}${NC}"
    else
        echo -e "${RED}Cluster name cannot be empty. Keeping: ${CLUSTER_NAME}${NC}"
    fi
    pause
}

# Function to create default config if missing
create_default_config() {
    local cluster_name=$1
    cat > kind-config.yaml << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${cluster_name}

nodes:
- role: control-plane
  image: kindest/node:v1.27.3
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
  - containerPort: 31000
    hostPort: 31000
    protocol: TCP

- role: worker
- role: worker

networking:
  apiServerAddress: "0.0.0.0"
  apiServerPort: 6443
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
EOF
    echo -e "${GREEN}Default config file created: kind-config.yaml for cluster ${cluster_name}${NC}"
}

# Function to create cluster
create_cluster() {
    echo -e "${GREEN}Creating Kind cluster '${CLUSTER_NAME}'...${NC}"
    
    # Check if kind is installed
    if ! command_exists kind; then
        echo -e "${RED}Error: Kind is not installed. Please install Kind first.${NC}"
        pause
        return 1
    fi
    
    # Check if config file exists
    if [ ! -f "kind-config.yaml" ]; then
        echo -e "${YELLOW}kind-config.yaml not found. Creating default config...${NC}"
        create_default_config "$CLUSTER_NAME"
    else
        # Update cluster name in existing config if different
        current_name=$(grep -E "^name:" kind-config.yaml | awk '{print $2}' | tr -d '"' | tr -d "'")
        if [ "$current_name" != "$CLUSTER_NAME" ]; then
            echo -e "${YELLOW}Updating cluster name in config from '${current_name}' to '${CLUSTER_NAME}'...${NC}"
            sed -i.bak "s/name:.*/name: ${CLUSTER_NAME}/" kind-config.yaml
        fi
    fi
    
    kind create cluster --config kind-config.yaml --name "$CLUSTER_NAME"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to create Kind cluster '${CLUSTER_NAME}'.${NC}"
        pause
        return 1
    fi
    
    echo -e "${GREEN}Creating namespace 'has'...${NC}"
    kubectl create namespace has 2>/dev/null || echo "Namespace 'has' already exists or error occurred"
    
    echo
    echo -e "${GREEN}Checking nodes...${NC}"
    kubectl get nodes
    
    echo
    echo -e "${GREEN}Checking pods in namespace 'has'...${NC}"
    kubectl get pods -n has
    
    echo -e "${GREEN}Cluster '${CLUSTER_NAME}' created successfully!${NC}"
    pause
}

# Function to deploy Apache
deploy_apache() {
    echo -e "${GREEN}Deploying Apache deployment with 2 replicas in namespace 'has' for cluster '${CLUSTER_NAME}'...${NC}"
    
    # Check if kubectl is available and cluster is running
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${RED}Error: Kubernetes cluster '${CLUSTER_NAME}' is not available. Please create cluster first.${NC}"
        pause
        return 1
    fi
    
    # Set context to ensure we're working with the right cluster
    kubectl config use-context "kind-${CLUSTER_NAME}" 2>/dev/null
    
    kubectl create deployment apache-deploy --image=httpd --replicas=2 -n has 2>/dev/null || \
    kubectl scale deployment apache-deploy --replicas=2 -n has
    
    echo
    echo -e "${GREEN}Exposing deployment as NodePort service on port 80 with NodePort 31000...${NC}"
    kubectl expose deployment apache-deploy --type=NodePort --name=apache-service --port=80 --target-port=80 -n has 2>/dev/null || \
    echo "Service already exists, updating..."
    
    # Patch the service to set nodePort
    kubectl patch service apache-service -n has -p '{"spec":{"ports":[{"port":80,"nodePort":31000,"protocol":"TCP"}]}}' 2>/dev/null || \
    echo "Could not patch service, may already be configured"
    
    echo
    echo -e "${GREEN}Checking pods in namespace 'has'...${NC}"
    kubectl get pods -n has
    
    echo
    echo -e "${GREEN}Checking services in namespace 'has'...${NC}"
    kubectl get svc -n has
    
    echo -e "${YELLOW}Apache should be accessible at: http://localhost:31000${NC}"
    pause
}

# Function to install ArgoCD
install_argocd() {
    echo -e "${GREEN}Installing Argo CD using Helm in namespace 'argocd' for cluster '${CLUSTER_NAME}'...${NC}"
    
    # Check if helm is installed
    if ! command_exists helm; then
        echo -e "${RED}Error: Helm is not installed. Please install Helm first.${NC}"
        pause
        return 1
    fi
    
    # Set context to ensure we're working with the right cluster
    kubectl config use-context "kind-${CLUSTER_NAME}" 2>/dev/null
    
    kubectl create namespace argocd 2>/dev/null || echo "Namespace 'argocd' already exists"
    
    # Add Argo CD Helm repo
    helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || echo "Repo already exists"
    helm repo update
    
    # Install Argo CD
    helm upgrade --install argocd argo/argo-cd -n argocd --set server.service.type=NodePort --set server.service.nodePort=30080
    
    echo
    echo -e "${GREEN}Checking Argo CD pods in namespace 'argocd'...${NC}"
    kubectl get pods -n argocd --watch --timeout=30s || \
    kubectl get pods -n argocd
    
    echo
    echo -e "${GREEN}Argo CD installation complete!${NC}"
    echo -e "${YELLOW}Argo CD UI should be accessible at: http://localhost:30080${NC}"
    echo -e "${YELLOW}Default username: admin${NC}"
    echo -e "${YELLOW}Get password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d${NC}"
    pause
}

# Function to delete cluster
delete_cluster() {
    echo -e "${GREEN}Deleting Kind cluster...${NC}"
    
    if ! command_exists kind; then
        echo -e "${RED}Error: Kind is not installed.${NC}"
        pause
        return 1
    fi
    
    # List available clusters
    echo -e "${GREEN}Available clusters:${NC}"
    kind get clusters
    
    echo
    read -p "Enter cluster name to delete: " cluster_to_delete
    
    if [ -z "$cluster_to_delete" ]; then
        echo -e "${RED}No cluster name entered. Cancelled.${NC}"
        pause
        return
    fi
    
    if ! kind get clusters | grep -q "^${cluster_to_delete}$"; then
        echo -e "${RED}Cluster '${cluster_to_delete}' does not exist.${NC}"
        pause
        return
    fi
    
    read -p "Are you sure you want to delete cluster '${cluster_to_delete}'? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        kind delete cluster --name "$cluster_to_delete"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Cluster '${cluster_to_delete}' deleted successfully!${NC}"
        else
            echo -e "${RED}Failed to delete cluster '${cluster_to_delete}'.${NC}"
        fi
    else
        echo -e "${YELLOW}Deletion cancelled.${NC}"
    fi
    
    pause
}

# Main loop
while true; do
    show_menu
    read -p "Enter your choice (1-6): " choice
    
    case $choice in
        1)
            set_cluster_name
            ;;
        2)
            create_cluster
            ;;
        3)
            deploy_apache
            ;;
        4)
            install_argocd
            ;;
        5)
            delete_cluster
            ;;
        6)
            echo -e "${GREEN}Exiting... Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please enter a number between 1-6.${NC}"
            pause
            ;;
    esac
done