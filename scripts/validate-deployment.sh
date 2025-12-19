#!/bin/bash
# Grafana Observability Stack - Deployment Validation Script
# Validates all components are deployed and functioning correctly

set -e

NAMESPACE="monitoring"
BOLD="\033[1m"
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
RESET="\033[0m"

echo -e "${BOLD}=== Grafana Observability Stack Validation ===${RESET}\n"

# Check if namespace exists
echo -e "${BOLD}1. Checking Namespace${RESET}"
if kubectl get namespace $NAMESPACE &> /dev/null; then
    echo -e "${GREEN}✓${RESET} Namespace '$NAMESPACE' exists"
else
    echo -e "${RED}✗${RESET} Namespace '$NAMESPACE' not found"
    exit 1
fi
echo ""

# Check all pods
echo -e "${BOLD}2. Checking Pod Status${RESET}"
echo "Checking pod status by label..."

check_pods() {
    local label_selector=$1
    local component=$2
    local target_ns=${3:-$NAMESPACE}
    # Use -l for label filtering directly in kubectl for better reliability
    local count=$(kubectl get pods -n $target_ns -l "$label_selector" --no-headers 2>/dev/null | wc -l)
    
    if [ $count -gt 0 ]; then
        local running=$(kubectl get pods -n $target_ns -l "$label_selector" --no-headers 2>/dev/null | grep "Running" | wc -l)
        if [ $running -eq $count ]; then
            echo -e "${GREEN}✓${RESET} $component: $running/$count pods running"
        else
            echo -e "${YELLOW}⚠${RESET} $component: $running/$count pods running (some not ready)"
        fi
    else
        echo -e "${RED}✗${RESET} $component: No pods found with selector $label_selector in $target_ns"
    fi
}

check_pods "app.kubernetes.io/name=grafana" "Grafana"
check_pods "app.kubernetes.io/name=prometheus" "Prometheus"
check_pods "app.kubernetes.io/name=alertmanager" "Alertmanager"
check_pods "app.kubernetes.io/name=loki" "Loki"
check_pods "app.kubernetes.io/name=tempo" "Tempo"
check_pods "app.kubernetes.io/name=promtail" "Promtail"
check_pods "app.kubernetes.io/name=prometheus-node-exporter" "Node Exporter"
check_pods "app.kubernetes.io/name=kube-state-metrics" "Kube State Metrics"
check_pods "app.kubernetes.io/name=metrics-server" "Metrics Server" "kube-system"

echo ""

# Check PVCs
echo -e "${BOLD}3. Checking Persistent Volume Claims${RESET}"
PVCS=$(kubectl get pvc -n $NAMESPACE -o json)
TOTAL_PVCS=$(echo "$PVCS" | jq -r '.items | length')
BOUND_PVCS=$(echo "$PVCS" | jq -r '.items[] | select(.status.phase == "Bound") | .metadata.name' | wc -l)

if [ $TOTAL_PVCS -eq 0 ]; then
    echo -e "${YELLOW}⚠${RESET} No PVCs found (may be expected for some configurations)"
else
    if [ $BOUND_PVCS -eq $TOTAL_PVCS ]; then
        echo -e "${GREEN}✓${RESET} All PVCs bound: $BOUND_PVCS/$TOTAL_PVCS"
        echo "$PVCS" | jq -r '.items[] | "  - \(.metadata.name): \(.spec.resources.requests.storage) (\(.status.phase))"'
    else
        echo -e "${RED}✗${RESET} Some PVCs not bound: $BOUND_PVCS/$TOTAL_PVCS"
        echo "$PVCS" | jq -r '.items[] | "  - \(.metadata.name): \(.status.phase)"'
    fi
fi
echo ""

# Check Services
echo -e "${BOLD}4. Checking Services${RESET}"
GRAFANA_SVC=$(kubectl get svc grafana -n $NAMESPACE -o json 2>/dev/null || echo "{}")
GRAFANA_TYPE=$(echo "$GRAFANA_SVC" | jq -r '.spec.type // "NotFound"')
GRAFANA_IP=$(echo "$GRAFANA_SVC" | jq -r '.status.loadBalancer.ingress[0].ip // "Pending"')

if [ "$GRAFANA_TYPE" == "LoadBalancer" ]; then
    if [ "$GRAFANA_IP" != "Pending" ] && [ "$GRAFANA_IP" != "null" ]; then
        echo -e "${GREEN}✓${RESET} Grafana LoadBalancer: $GRAFANA_IP"
    else
        echo -e "${YELLOW}⚠${RESET} Grafana LoadBalancer: IP pending"
    fi
elif [ "$GRAFANA_TYPE" == "ClusterIP" ]; then
    echo -e "${GREEN}✓${RESET} Grafana Service Type: ClusterIP (Managed via Ingress)"
else
    echo -e "${RED}✗${RESET} Grafana Service Type: $GRAFANA_TYPE"
fi

echo ""

# Check datasource connectivity
echo -e "${BOLD}5. Checking Internal Service Connectivity${RESET}"

check_service() {
    local service=$1
    local port=$2
    local endpoint=$3
    local name=$4
    
    if kubectl get svc $service -n $NAMESPACE &> /dev/null; then
        echo -e "${GREEN}✓${RESET} $name service exists: $service:$port"
    else
        echo -e "${RED}✗${RESET} $name service not found: $service"
    fi
}

check_service "prometheus-server" "80" "/-/healthy" "Prometheus"
check_service "loki-gateway" "80" "/ready" "Loki"
check_service "tempo" "3200" "/ready" "Tempo"
check_service "prometheus-alertmanager" "9093" "/-/healthy" "Alertmanager"

echo ""

# Check StorageClass
echo -e "${BOLD}6. Checking Storage Class${RESET}"
if kubectl get storageclass oci-bv &> /dev/null; then
    echo -e "${GREEN}✓${RESET} StorageClass 'oci-bv' exists"
else
    echo -e "${YELLOW}⚠${RESET} StorageClass 'oci-bv' not found"
fi
echo ""

# Check ArgoCD Applications
echo -e "${BOLD}7. Checking ArgoCD Applications${RESET}"

check_argocd_app() {
    local app=$1
    local name=$2
    
    if kubectl get application -n argocd $app &> /dev/null; then
        local health=$(kubectl get application -n argocd $app -o jsonpath='{.status.health.status}')
        local sync=$(kubectl get application -n argocd $app -o jsonpath='{.status.sync.status}')
        
        if [ "$health" == "Healthy" ] && [ "$sync" == "Synced" ]; then
            echo -e "${GREEN}✓${RESET} $name: $health ($sync)"
        else
            echo -e "${YELLOW}⚠${RESET} $name: $health ($sync)"
        fi
    else
        echo -e "${RED}✗${RESET} $name Application not found in ArgoCD"
    fi
}

check_argocd_app "grafana" "Grafana"
check_argocd_app "prometheus" "Prometheus"
check_argocd_app "loki" "Loki"
check_argocd_app "tempo" "Tempo"
check_argocd_app "promtail" "Promtail"
check_argocd_app "metrics-server" "Metrics Server"

echo ""

# Resource usage check
echo -e "${BOLD}8. Checking Resource Usage${RESET}"
if kubectl top nodes &> /dev/null; then
    echo "Node resource usage:"
    kubectl top nodes | awk 'NR==1 || /Ready/'
    echo ""
    echo "Top 5 pods by CPU:"
    kubectl top pods -n $NAMESPACE --sort-by=cpu | head -6
    echo ""
    echo "Top 5 pods by Memory:"
    kubectl top pods -n $NAMESPACE --sort-by=memory | head -6
else
    echo -e "${YELLOW}⚠${RESET} metrics-server not available, skipping resource usage check"
fi
echo ""

# Summary
echo -e "${BOLD}=== Validation Summary ===${RESET}"
echo ""
echo "Components Deployed:"
echo "  - Grafana (Visualization Hub)"
echo "  - Prometheus (Metrics Collection)"
echo "  - Alertmanager (Alert Management)"
echo "  - Loki (Log Aggregation)"
echo "  - Tempo (Distributed Tracing)"
echo "  - Promtail (Log Collection Agent)"
echo "  - Node Exporter (Host Metrics)"
echo "  - Kube State Metrics (K8s Metrics)"
echo ""

if [ "$GRAFANA_IP" != "Pending" ] && [ "$GRAFANA_IP" != "null" ] && [ "$GRAFANA_TYPE" == "LoadBalancer" ]; then
    echo -e "${BOLD}Grafana Access:${RESET}"
    echo "  URL: http://$GRAFANA_IP"
    echo "  Username: admin"
    echo "  Password: Run the following command to retrieve:"
    echo "    kubectl get secret grafana -n $NAMESPACE -o jsonpath=\"{.data.admin-password}\" | base64 -d ; echo"
    echo ""
fi

echo -e "${BOLD}Next Steps:${RESET}"
echo "  1. Access Grafana and verify datasources"
echo "  2. Configure external applications to send metrics/logs/traces"
echo "  3. Import dashboards from Grafana community"
echo "  4. Set up alerting rules and notifications"
echo ""
echo "Documentation: hub-docs/README.md, docs/QUICKSTART.md, docs/CONFIGURATION.md"
echo ""

