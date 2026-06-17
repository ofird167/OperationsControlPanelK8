import re

with open('scripts/bootstrap.sh', 'r') as f:
    content = f.read()

linkerd_install = """        echo "=== Installing Linkerd Service Mesh ==="
        linkerd install --crds | kubectl apply -f -
        linkerd install | kubectl apply -f -
        kubectl annotate namespace default linkerd.io/inject=enabled --overwrite
        
        echo "=== Bootstrapping Observability"""

content = content.replace('        echo "=== Bootstrapping Observability', linkerd_install)

with open('scripts/bootstrap.sh', 'w') as f:
    f.write(content)
    
print("Successfully updated bootstrap.sh for Linkerd.")
