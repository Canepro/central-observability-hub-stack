# Observability Hub Data Flow

This diagram visualizes how data flows from various Spoke clusters and external applications into the Central OKE Hub.

```mermaid
graph LR
    subgraph spokes [Spoke Clusters (K3s, Podman, etc.)]
        PromAgent[Prometheus Agent]
        LokiAgent[Promtail / FluentBit]
        AppTraces[OTEL SDK / Collector]
    end

    subgraph hub [OKE Hub Cluster (Central Hub)]
        LB[OCI Load Balancer]
        
        subgraph backend [Storage & Backend]
            Mimir[(Prometheus: Metrics)]
            Loki[(Loki: Logs)]
            Tempo[(Tempo: Traces)]
        end
        
        subgraph visualization [Visualization]
            Grafana[Grafana Dashboard]
        end

        ArgoCD[ArgoCD: The Brain]
    end

    %% Data Flow
    PromAgent -- "Remote Write (HTTPS)" --> LB
    LokiAgent -- "Push Logs (HTTPS)" --> LB
    AppTraces -- "OTLP (HTTPS)" --> LB
    
    LB -- "/api/v1/write" --> Mimir
    LB -- "/loki/api/v1/push" --> Loki
    LB -- "/v1/traces" --> Tempo
    
    Grafana -- "Queries" --> Mimir
    Grafana -- "Queries" --> Loki
    Grafana -- "Queries" --> Tempo
    
    ArgoCD -- "Self-Manage (SSA)" --> hub
```

## Flow Description
1. **Ingestion**: External agents (Prometheus Agent, Promtail) push telemetry via the OCI Load Balancer using HTTPS and Basic Auth.
2. **Persistence**: The Hub components store high-velocity data (metrics) on Block Volumes and high-volume data (logs/traces) on OCI Object Storage.
3. **Visualization**: Grafana queries the backend services internally within the cluster.
4. **Management**: ArgoCD monitors the repository and applies updates to the Hub cluster itself via Server-Side Apply.

