# Blocky DNS Ad-Blocker

Network-wide ad blocking and DNS resolver running on the Odroid C4 cluster.

## Overview

[Blocky](https://0xerr0r.github.io/blocky/) is a DNS proxy and ad-blocker that:
- Blocks ads, trackers, and malware at the DNS level
- Uses DNS-over-HTTPS (DoH) for upstream queries (privacy)
- Provides caching for faster repeat lookups
- Exposes Prometheus metrics for monitoring

## Architecture

```
                    +-----------+
   Clients -------->| Any Node  |:30053 (UDP)
   (router/devices) | Port 53   |:30054 (TCP)
                    +-----------+
                         |
         +---------------+---------------+
         |       |       |       |       |
      node1   node2   node3   ...    node7
      blocky  blocky  blocky        blocky
         |       |       |       |       |
         +-------+-------+-------+-------+
                         |
                    DoH Upstream
              (Cloudflare, Google)
```

- **DaemonSet**: One Blocky pod runs on each of the 7 nodes
- **NodePort Services**: DNS available on any node's IP
- **Tolerations**: Runs on both control plane and worker nodes

## Deployment

```bash
# Deploy all Blocky resources
kubectl apply -f k8s/blocky/

# Verify pods are running on all nodes
kubectl get pods -n dns -o wide

# Check logs
kubectl logs -n dns -l app=blocky --tail=50
```

## Configuration

Configuration is in `configmap.yaml`. Key settings:

### Upstream DNS (DoH)
```yaml
upstreams:
  groups:
    default:
      - https://cloudflare-dns.com/dns-query
      - https://dns.google/dns-query
```

### Blocklists
Three categories are enabled by default:
- **ads**: StevenBlack hosts, AdGuard DNS filter
- **trackers**: EasyPrivacy list
- **malware**: URLhaus abuse list

Lists refresh every 4 hours automatically.

### Caching
- Minimum TTL: 5 minutes
- Maximum TTL: 30 minutes
- Prefetching enabled for popular domains

## Usage

### Configure Your Router

Point your router's DNS settings to any node's IP on port 30053:

| Node | IP (check current) | DNS Port |
|------|-------------------|----------|
| node1 | 192.168.4.250 | 30053 (UDP) |
| node2-7 | See CLAUDE.md | 30053 (UDP) |

For redundancy, configure multiple nodes as DNS servers.

### Configure Individual Devices

Set DNS server to `<node-ip>:30053` (or just `<node-ip>` if your device uses standard port 53 and you configure port forwarding).

### Test DNS Resolution

```bash
# From any machine that can reach the cluster
dig @192.168.4.250 -p 30053 google.com

# Test ad blocking (should return 0.0.0.0)
dig @192.168.4.250 -p 30053 ads.google.com

# From within the cluster
kubectl run -it --rm dns-test --image=busybox --restart=Never -- \
  nslookup google.com blocky-dns-udp.dns.svc.cluster.local
```

## Services

| Service | Port | NodePort | Purpose |
|---------|------|----------|---------|
| blocky-dns-udp | 53/UDP | 30053 | DNS queries (primary) |
| blocky-dns-tcp | 53/TCP | 30054 | DNS queries (fallback) |
| blocky-metrics | 4000/TCP | 30055 | HTTP API and metrics |

## Monitoring

### Prometheus Metrics

Blocky exposes metrics at `/metrics` on port 4000 (NodePort 30055):

```bash
curl http://node1.local:30055/metrics
```

Key metrics:
- `blocky_query_total` - Total DNS queries
- `blocky_blocked_query_total` - Blocked queries
- `blocky_cache_hit_total` - Cache hits
- `blocky_request_duration_seconds` - Query latency

### Grafana Dashboard

Import the official Blocky dashboard (ID: 13768) or create custom panels using the metrics above.

Access: `http://node1.local:3000` (admin/admin)

## Common Operations

### Check Status
```bash
# Pod status
kubectl get pods -n dns

# Logs from all pods
kubectl logs -n dns -l app=blocky -f

# Logs from specific node
kubectl logs -n dns -l app=blocky --field-selector spec.nodeName=node1
```

### Update Blocklists

Blocklists refresh automatically every 4 hours. To force refresh:

```bash
# Restart all Blocky pods
kubectl rollout restart daemonset/blocky -n dns
```

### Modify Configuration

1. Edit `configmap.yaml`
2. Apply changes: `kubectl apply -f k8s/blocky/configmap.yaml`
3. Restart pods: `kubectl rollout restart daemonset/blocky -n dns`

### Troubleshooting

```bash
# Check if Blocky is responding
kubectl exec -n dns -it $(kubectl get pod -n dns -l app=blocky -o jsonpath='{.items[0].metadata.name}') -- wget -qO- http://localhost:4000/metrics | head

# Check resource usage
kubectl top pods -n dns

# Describe pod for events/errors
kubectl describe pods -n dns -l app=blocky
```

## Files

| File | Purpose |
|------|---------|
| `namespace.yaml` | Creates `dns` namespace |
| `configmap.yaml` | Blocky configuration (blocklists, upstream DNS, caching) |
| `daemonset.yaml` | Blocky deployment (one pod per node) |
| `service.yaml` | NodePort services for DNS and metrics |
