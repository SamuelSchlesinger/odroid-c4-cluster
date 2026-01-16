# Kubernetes Tutorial: Deploying Your First Application

A hands-on walkthrough of deploying and exploring an application on the Odroid C4 K3s cluster.

## What You'll Learn

- How Kubernetes organizes applications (namespaces, deployments, services)
- How to deploy a multi-replica application
- How load balancing distributes traffic across pods
- How to inspect, scale, and manage running workloads
- The difference between connection-level and request-level load balancing

## Prerequisites

SSH access to the cluster:
```bash
# From the local network
ssh admin@node1.local

# From remote (via jump host)
ssh -J samuel@desktop admin@node1.local
```

## The Application: whoami

We'll deploy `traefik/whoami`, a tiny web server that returns information about the pod handling each request. This makes it easy to observe Kubernetes behavior.

## Step 1: Understanding the Manifest

The manifest file `whoami-app.yaml` defines three Kubernetes resources:

### Namespace
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: examples
```
Namespaces isolate resources. We create an `examples` namespace to keep tutorial workloads separate from system components.

### Deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami
  namespace: examples
spec:
  replicas: 3
  selector:
    matchLabels:
      app: whoami
  template:
    spec:
      containers:
        - name: whoami
          image: traefik/whoami:latest
          ports:
            - containerPort: 80
```
A Deployment manages a set of identical pods. Key points:
- `replicas: 3` - Kubernetes maintains exactly 3 running instances
- `selector` - How the deployment finds its pods (by label `app: whoami`)
- `template` - The pod specification: what container image to run, what ports to expose

### Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: whoami
  namespace: examples
spec:
  type: NodePort
  selector:
    app: whoami
  ports:
    - port: 80
      nodePort: 30080
```
A Service provides a stable network endpoint for pods. Key points:
- `type: NodePort` - Exposes the service on every node at port 30080
- `selector: app: whoami` - Routes traffic to pods with this label
- Kubernetes automatically load-balances across all matching pods

## Step 2: Deploy the Application

Apply the manifest:
```bash
kubectl apply -f https://raw.githubusercontent.com/SamuelSchlesinger/odroid-c4-cluster/main/k8s/examples/whoami-app.yaml
```

Output:
```
namespace/examples created
deployment.apps/whoami created
service/whoami created
```

## Step 3: Verify the Deployment

Check that pods are running:
```bash
kubectl get pods -n examples -o wide
```

Output:
```
NAME                      READY   STATUS    RESTARTS   AGE   IP          NODE
whoami-6f8c84d46c-fkvsx   1/1     Running   0          39s   10.42.3.2   node5
whoami-6f8c84d46c-fnv8b   1/1     Running   0          39s   10.42.4.2   node2
whoami-6f8c84d46c-j7h2f   1/1     Running   0          39s   10.42.2.2   node6
```

Notice:
- 3 pods are running (matching `replicas: 3`)
- Each pod has a unique name suffix
- Pods are distributed across different nodes (node5, node2, node6)
- Each pod has its own cluster IP (10.42.x.x)

Check the service:
```bash
kubectl get svc -n examples
```

Output:
```
NAME     TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
whoami   NodePort   10.43.131.180   <none>        80:30080/TCP   39s
```

The service has a stable ClusterIP (10.43.131.180) and is exposed externally on port 30080.

## Step 4: Access the Application

The NodePort service makes the app accessible on port 30080 of any node:

```bash
curl http://node1.local:30080
```

Output:
```
Hostname: whoami-6f8c84d46c-fkvsx
IP: 127.0.0.1
IP: ::1
IP: 10.42.3.2
RemoteAddr: 10.42.0.0:37397
GET / HTTP/1.1
Host: localhost:30080
User-Agent: curl/8.14.1
Accept: */*
```

The response shows:
- `Hostname` - The pod that handled this request
- `IP` - The pod's network interfaces
- `RemoteAddr` - Where the request came from (the node's kube-proxy)
- HTTP headers from your request

## Step 5: Observe Load Balancing

Run multiple requests:
```bash
for i in $(seq 1 10); do
  curl -s http://localhost:30080 | grep Hostname
done
```

Output:
```
Hostname: whoami-6f8c84d46c-j7h2f
Hostname: whoami-6f8c84d46c-j7h2f
Hostname: whoami-6f8c84d46c-fnv8b
Hostname: whoami-6f8c84d46c-fkvsx
Hostname: whoami-6f8c84d46c-fnv8b
Hostname: whoami-6f8c84d46c-fnv8b
Hostname: whoami-6f8c84d46c-j7h2f
Hostname: whoami-6f8c84d46c-fkvsx
Hostname: whoami-6f8c84d46c-fkvsx
Hostname: whoami-6f8c84d46c-fnv8b
```

Requests are distributed across all three pods. This is Kubernetes load balancing in action.

### Browser vs curl: A Subtlety

If you access the app from a web browser and refresh repeatedly, you'll notice it always shows the same hostname. Why?

**The answer: connection reuse.**

Browsers use HTTP keep-alive, maintaining a persistent TCP connection for multiple requests. Kubernetes load-balances at the *connection* level, not the *request* level. Once a connection is established to a pod, all requests on that connection go to the same pod.

curl, by default, opens a new connection for each request, so you see different pods.

To see different pods from a browser:
- Open multiple incognito/private windows (each gets a new connection)
- Close and reopen the tab
- Wait for the keep-alive timeout

This is important to understand: Kubernetes Services provide connection-level load balancing, not HTTP request-level load balancing. For request-level distribution, you'd need an ingress controller or service mesh.

## Step 6: Explore the Pods

### View logs
```bash
kubectl logs -n examples -l app=whoami --tail=10
```

### Execute commands inside a pod
```bash
kubectl exec -n examples deploy/whoami -- cat /etc/os-release
```

### Get an interactive shell
```bash
kubectl exec -n examples -it deploy/whoami -- /bin/sh
```

### Check resource usage
```bash
kubectl top pods -n examples
```

## Step 7: Scale the Application

Scale up to 5 replicas:
```bash
kubectl scale deployment -n examples whoami --replicas=5
kubectl get pods -n examples
```

Scale down to 2:
```bash
kubectl scale deployment -n examples whoami --replicas=2
kubectl get pods -n examples
```

Kubernetes automatically terminates excess pods or creates new ones to match the desired count.

## Step 8: Clean Up

Delete everything in the namespace:
```bash
kubectl delete namespace examples
```

This removes the namespace and all resources within it (deployment, service, pods).

## Key Concepts Recap

| Concept | Purpose |
|---------|---------|
| **Namespace** | Isolates resources into logical groups |
| **Deployment** | Manages a set of identical pods, handles scaling and updates |
| **Pod** | The smallest deployable unit; one or more containers |
| **Service** | Stable network endpoint that load-balances across pods |
| **NodePort** | Exposes a service on a static port on every node |
| **Labels** | Key-value pairs used to select and organize resources |

## Common Commands Reference

```bash
# List resources
kubectl get pods -n examples
kubectl get svc -n examples
kubectl get all -n examples

# Detailed info
kubectl describe pod -n examples <pod-name>
kubectl describe svc -n examples whoami

# Logs
kubectl logs -n examples <pod-name>
kubectl logs -n examples -l app=whoami -f  # follow all

# Execute
kubectl exec -n examples <pod-name> -- <command>
kubectl exec -n examples -it <pod-name> -- /bin/sh

# Scale
kubectl scale deployment -n examples whoami --replicas=N

# Delete
kubectl delete namespace examples
```

## Next Steps

Now that you understand the basics:
1. Try modifying the manifest (change replicas, add resource limits)
2. Create a second service and observe internal DNS (`whoami.examples.svc.cluster.local`)
3. Add a ConfigMap to inject configuration into pods
4. Explore deployments with rolling updates (`kubectl set image`)
