FROM ubuntu:22.04

# Avoid interactive prompts during apt installs
ENV DEBIAN_FRONTEND=noninteractive

# Install core system dependencies (including docker.io for the docker client CLI)
RUN apt-get update && apt-get install -y \
    curl \
    git \
    python3 \
    python3-pip \
    sshpass \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

# Install Docker Python SDK and Ansible
RUN pip3 install --no-cache-dir docker cryptography ansible

# Install Ansible Community Docker Collection
RUN ansible-galaxy collection install community.docker

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/v1.30.0/bin/linux/amd64/kubectl" && \
    chmod +x ./kubectl && \
    mv ./kubectl /usr/local/bin/kubectl

# Install Helm
RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
    chmod +x get_helm.sh && \
    ./get_helm.sh && \
    rm get_helm.sh

# Install Argo Rollouts plugin
RUN curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64 && \
    chmod +x ./kubectl-argo-rollouts-linux-amd64 && \
    mv ./kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts

# Install Linkerd CLI
RUN curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh && \
    cp ~/.linkerd2/bin/linkerd /usr/local/bin/linkerd

WORKDIR /workspace

CMD ["bash"]
