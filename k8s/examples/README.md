# Kubernetes Examples

Hands-on tutorials for deploying and managing applications on the Odroid C4 K3s cluster.

## Prerequisites

Access to the cluster via SSH:
```bash
# From desktop (local network)
ssh admin@node1.local

# From MacBook (via jump host)
ssh -J samuel@desktop admin@node1.local
```

## Example 1: whoami-app

A simple web application that returns information about the pod serving each request. Demonstrates:
- Deployments with multiple replicas
- Services and load balancing
- Scaling applications
- Viewing logs
- Executing commands in pods

### Deploy the Application

```bash
# Apply the manifest
kubectl apply -f https://raw.githubusercontent.com/SamuelSchlesinger/odroid-c4-cluster/main/k8s/examples/whoami-app.yaml

# Or if you have the file locally:
kubectl apply -f /path/to/whoami-app.yaml
```

### Verify Deployment

```bash
# Check the namespace was created
kubectl get namespaces

# Check the deployment status
kubectl get deployment -n examples

# Watch pods come up (Ctrl+C to exit)
kubectl get pods -n examples -w

# See which nodes the pods are scheduled on
kubectl get pods -n examples -o wide
```

### Access the Application

The service is exposed on NodePort 30080. Access it from any node:

```bash
# From within the cluster
curl http://localhost:30080

# From the desktop (any node works)
curl http://node1.local:30080
curl http://node3.local:30080

# From MacBook via SSH
ssh -J samuel@desktop admin@node1.local "curl -s http://localhost:30080"
```

### Observe Load Balancing

Run multiple requests and watch the `Hostname` field change as different pods serve each request:

```bash
# Make 10 requests and show which pod handled each
for i in $(seq 1 10); do
  curl -s http://localhost:30080 | grep Hostname
done
```

Expected output shows requests distributed across replicas:
```
Hostname: whoami-7d4b8c9f5-abc12
Hostname: whoami-7d4b8c9f5-xyz34
Hostname: whoami-7d4b8c9f5-def56
Hostname: whoami-7d4b8c9f5-abc12
...
```

### Explore the Pods

```bash
# List all pods with their IPs
kubectl get pods -n examples -o wide

# Describe a pod (detailed info, events, conditions)
kubectl describe pod -n examples -l app=whoami | head -50

# View logs from a specific pod
kubectl logs -n examples -l app=whoami --tail=20

# Follow logs in real-time (Ctrl+C to exit)
kubectl logs -n examples -l app=whoami -f

# Execute a command inside a pod
kubectl exec -n examples deploy/whoami -- cat /etc/os-release

# Get an interactive shell
kubectl exec -n examples -it deploy/whoami -- /bin/sh
```

### Scale the Application

```bash
# Scale up to 5 replicas
kubectl scale deployment -n examples whoami --replicas=5

# Watch pods come up
kubectl get pods -n examples -w

# Scale down to 2 replicas
kubectl scale deployment -n examples whoami --replicas=2

# Verify
kubectl get pods -n examples
```

### View Resource Usage

```bash
# CPU and memory usage per pod
kubectl top pods -n examples

# Across all nodes
kubectl top nodes
```

### Update the Application

```bash
# Change the image (triggers rolling update)
kubectl set image deployment/whoami -n examples whoami=traefik/whoami:v1.10

# Watch the rollout
kubectl rollout status deployment/whoami -n examples

# View rollout history
kubectl rollout history deployment/whoami -n examples

# Rollback if needed
kubectl rollout undo deployment/whoami -n examples
```

### Inspect the Service

```bash
# View service details
kubectl get service -n examples

# See endpoints (pod IPs behind the service)
kubectl get endpoints -n examples

# Describe service
kubectl describe service whoami -n examples
```

### Debug Networking

```bash
# Test DNS resolution from within a pod
kubectl exec -n examples deploy/whoami -- nslookup whoami.examples.svc.cluster.local

# Test connectivity to another pod
kubectl exec -n examples deploy/whoami -- wget -qO- http://whoami.examples.svc.cluster.local
```

### Clean Up

```bash
# Delete everything in the examples namespace
kubectl delete namespace examples

# Or delete just the application
kubectl delete -f whoami-app.yaml
```

## Tips

### Quick Access Aliases

Add to your `.bashrc` on the nodes:
```bash
alias k='kubectl'
alias kge='kubectl get -n examples'
alias kgp='kubectl get pods -n examples'
```

### Common Troubleshooting

```bash
# Pod stuck in Pending? Check events:
kubectl describe pod -n examples <pod-name>

# Pod in CrashLoopBackOff? Check logs:
kubectl logs -n examples <pod-name> --previous

# Can't pull image? Check node has network:
kubectl get events -n examples --sort-by='.lastTimestamp'
```

### Useful Flags

- `-o wide` - Show more columns (node, IP, etc.)
- `-o yaml` - Full YAML output
- `-w` - Watch for changes
- `--all-namespaces` or `-A` - All namespaces
- `-l app=whoami` - Filter by label

## Next Steps

After completing this tutorial, try:
1. Creating your own deployment from scratch
2. Adding a ConfigMap or Secret
3. Setting up a horizontal pod autoscaler
4. Deploying a stateful application with persistent storage
