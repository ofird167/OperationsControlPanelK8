import re

with open('manifests/05-app-stack.yaml.tmpl', 'r') as f:
    content = f.read()

# Replace backend-stable Deployment with Rollout
rollout_yaml = """apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: backend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: backend
  strategy:
    canary:
      canaryService: backend-canary-service
      stableService: backend-service
      trafficRouting:
        nginx:
          stableIngress: app-ingress-backend
      steps:
      - setWeight: 20
      - pause: {}
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
        - name: api-backend
          image: backend:latest
          imagePullPolicy: Never
          ports:
            - containerPort: 5000
          env:
            - name: APP_VERSION
              value: "v2-canary"
            - name: CONFIG_MAP_VAL
              valueFrom:
                configMapKeyRef:
                  name: app-config
                  key: CONFIG_MAP_VAL
            - name: DB_USER
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: database-user
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: database-password
            - name: DB_NAME
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: database-name
            - name: DB_HOST
              value: postgres-service
          livenessProbe:
            httpGet:
              path: /health
              port: 5000
            initialDelaySeconds: 10
            periodSeconds: 15
          readinessProbe:
            httpGet:
              path: /health
              port: 5000
            initialDelaySeconds: 5
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: backend-service
spec:
  ports:
    - port: 5000
      targetPort: 5000
  selector:
    app: backend
---
apiVersion: v1
kind: Service
metadata:
  name: backend-canary-service
spec:
  ports:
    - port: 5000
      targetPort: 5000
  selector:
    app: backend"""

# We need to replace everything from "apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: backend-stable"
# up to the end of backend-canary-service.
start_idx = content.find("apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: backend-stable")
end_idx = content.find("apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: frontend")

if start_idx != -1 and end_idx != -1:
    new_content = content[:start_idx] + rollout_yaml + "\n---\n" + content[end_idx:]
    with open('manifests/05-app-stack.yaml.tmpl', 'w') as f:
        f.write(new_content)
    print("Successfully patched 05-app-stack.yaml.tmpl")
else:
    print("Could not find blocks to replace!")
