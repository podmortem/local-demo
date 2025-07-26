#!/bin/bash

set -e

CLUSTER_NAME="podmortem-demo"
PODMORTEM_NAMESPACE="podmortem-system"
DEMO_NAMESPACE="demo"

print_step() {
    echo "$1"
}

print_success() {
    echo "$1"
}

print_warning() {
    echo "Warning: $1"
}

print_error() {
    echo "Error: $1"
}

check_prerequisites() {
    if ! command -v kind &> /dev/null; then
        print_error "kind is not installed"
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed"
        exit 1
    fi
    
    if ! podman info &> /dev/null; then
        print_error "Podman is not running"
        exit 1
    fi
}

create_kind_config() {
    cat > /tmp/kind-config.yaml << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
- role: control-plane
  image: kindest/node:v1.29.0
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 8080
    protocol: TCP
  - containerPort: 443
    hostPort: 8443
    protocol: TCP
- role: worker
  image: kindest/node:v1.29.0
- role: worker
  image: kindest/node:v1.29.0
networking:
  apiServerAddress: "127.0.0.1"
  apiServerPort: 6443
EOF
}

setup_cluster() {
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        print_warning "Cluster ${CLUSTER_NAME} already exists"
        read -p "Delete and recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kind delete cluster --name="${CLUSTER_NAME}"
        else
            kubectl cluster-info --context kind-"${CLUSTER_NAME}" > /dev/null 2>&1
            return 0
        fi
    fi
    
    echo "Creating kind cluster..."
    kind create cluster --config=/tmp/kind-config.yaml --wait=300s > /dev/null
    kubectl wait --for=condition=Ready nodes --all --timeout=300s > /dev/null 2>&1
}

create_namespaces() {
    # Create podmortem-system namespace
    if ! kubectl get namespace "${PODMORTEM_NAMESPACE}" &> /dev/null; then
        kubectl create namespace "${PODMORTEM_NAMESPACE}" > /dev/null
        kubectl label namespace "${PODMORTEM_NAMESPACE}" \
            name="${PODMORTEM_NAMESPACE}" \
            app.kubernetes.io/name=podmortem-operator \
            app.kubernetes.io/part-of=podmortem > /dev/null
    fi
    
    # Create demo namespace
    if ! kubectl get namespace "${DEMO_NAMESPACE}" &> /dev/null; then
        kubectl create namespace "${DEMO_NAMESPACE}" > /dev/null
        kubectl label namespace "${DEMO_NAMESPACE}" \
            name="${DEMO_NAMESPACE}" \
            podmortem.redhat.com/monitored=true \
            app.kubernetes.io/name=podmortem-demo > /dev/null
    fi
}

install_ingress() {
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml > /dev/null 2>&1
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=90s > /dev/null 2>&1
}



display_cluster_info() {
    echo "Cluster: ${CLUSTER_NAME}"
    echo "Context: kind-${CLUSTER_NAME}"
    echo "Namespaces: ${PODMORTEM_NAMESPACE}, ${DEMO_NAMESPACE}"
    kubectl get nodes --no-headers | wc -l | xargs echo "Nodes:"
}

main() {
    echo "Setting up Podmortem demo cluster..."
    
    check_prerequisites
    create_kind_config
    setup_cluster
    create_namespaces
    install_ingress
    
    echo "Setup complete."
    display_cluster_info
}

case "${1:-}" in
    "delete")
        echo "Deleting cluster ${CLUSTER_NAME}..."
        kind delete cluster --name="${CLUSTER_NAME}"
        echo "Cluster deleted."
        ;;
    "info")
        display_cluster_info
        ;;
    *)
        main "$@"
        ;;
esac
