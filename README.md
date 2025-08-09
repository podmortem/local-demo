# Podmortem Local Demo

This is a local demo environment for Podmortem that uses Kind to create a test cluster with pod failure scenarios. Podmortem analyzes pod failures using pattern matching and AI to provide detailed explanations and remediation suggestions.

## Prerequisites

You need:
- Podman
- kubectl 
- kind
- make

Installation:

**macOS:**
```bash
brew install podman kubectl kind make
```

**Linux:**
```bash
# Install podman, kubectl, kind, make using your package manager
```

## AI Provider Setup

Podmortem uses AI to analyze failure patterns and provide remediation suggestions. You need to configure an AI provider before running scenarios.

### Supported Providers

**1. Ollama (Recommended for local testing)**
- Runs locally on your machine
- Supports various open-source models (Mistral, Llama, etc.)

**2. OpenAI-Compatible APIs**
- Works with any OpenAI-compatible API (OpenAI, Anthropic, local models, etc.)
- Requires API key

### Option 1: Local Ollama Setup

Install and run Ollama:
```bash
# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Pull and run a model (this may take a few minutes)
ollama pull mistral:7b
ollama serve
```

The demo is pre-configured to use Ollama at `http://localhost:11434/` with the `mistral:7b` model.

### Option 2: OpenAI-Compatible API Setup

Works with various providers:
- **OpenAI**: `https://api.openai.com/v1` (models: gpt-3.5-turbo, gpt-4, etc.)
- **Anthropic**: `https://api.anthropic.com/v1` (models: claude-3-sonnet, etc.)
- **Local OpenAI-compatible servers**: Like text-generation-webui, LocalAI, vLLM
- **Other cloud providers**: Many offer OpenAI-compatible endpoints

1. Get an API key from your chosen provider

2. Create a Kubernetes secret for your API key:
```bash
kubectl create secret generic openai-secret \
  --from-literal=api-key=YOUR_API_KEY \
  -n podmortem-system
```

3. Apply the OpenAI-compatible configuration:
```bash
# Update the secret with your API key
kubectl patch secret openai-secret -n podmortem-system \
  --type='json' -p='[{"op": "replace", "path": "/data/api-key", "value": "'$(echo -n YOUR_API_KEY | base64)'"}]'

# Switch to OpenAI-compatible provider
make setup-openai
```

4. Update the API URL and model for your provider:
```bash
# Use base URLs only - /chat/completions is added automatically
kubectl patch aiprovider openai-ai-provider -n podmortem-system --type='json' \
  -p='[{"op": "replace", "path": "/spec/apiUrl", "value": "YOUR_PROVIDER_BASE_URL"}]'
kubectl patch aiprovider openai-ai-provider -n podmortem-system --type='json' \
  -p='[{"op": "replace", "path": "/spec/modelId", "value": "YOUR_MODEL_NAME"}]'
```

## Pattern Libraries

Patterns are the foundation of Podmortem's intelligent log analysis. They define what to look for in pod failure logs and how to interpret those findings.

### What are Patterns?

Patterns are YAML-defined rules that:
- **Match specific log entries** using regex patterns
- **Assign confidence scores** to potential root causes  
- **Provide context extraction** around matched lines
- **Offer remediation guidance** with actionable fix suggestions
- **Link to documentation** for deeper understanding

### How Patterns Work

When a pod fails, Podmortem:
1. **Scans logs** against all loaded patterns
2. **Scores matches** based on pattern confidence and context
3. **Ranks findings** to identify the most likely root cause
4. **Extracts context** around critical log lines
5. **Provides AI analysis** using pattern insights and remediation guidance

### Pattern Structure Example

```yaml
- id: "quarkus_database_connection_failure"
  name: "Database Connection Failure"
  
  primary_pattern:
    regex: "Unable to connect to database|Connection refused.*database"
    confidence: 0.95    # How confident this pattern indicates the root cause (0.0-1.0)
  
  secondary_patterns:
    - regex: "SQLException|Connection timeout"
      weight: 0.4       # How much this pattern contributes to the overall score (0.0-1.0)
      proximity_window: 20    # Look for this pattern within 20 lines of the primary match
  
  severity: "CRITICAL"  # CRITICAL, HIGH, MEDIUM, LOW - impacts prioritization
  category: ["database", "connectivity"]
  
  remediation:
    description: "Application cannot connect to the database"
    common_causes:
      - "Database server is down"
      - "Incorrect connection credentials"
      - "Network connectivity issues"
    suggested_commands:
      - "kubectl get secrets -n your-namespace"
      - "kubectl logs database-pod -n database-namespace"
      - "ping database-hostname"
    documentation_links:
      - "https://quarkus.io/guides/datasource"
```

### Creating Your Own Patterns

You can create custom pattern libraries for your specific applications:

#### 1. Public Repository (Recommended)

```yaml
apiVersion: podmortem.redhat.com/v1alpha1
kind: PatternLibrary
metadata:
  name: my-custom-patterns
  namespace: podmortem-system
spec:
  repositories:
    - name: "my-patterns-repo"
      url: "https://github.com/your-org/my-app-patterns.git"
      branch: "main"
  enabledLibraries:
    - "my-app-core-patterns"
    - "my-app-integration-patterns"
```

#### 2. Private Repository

```yaml
# First create a secret for Git credentials
apiVersion: v1
kind: Secret
metadata:
  name: git-credentials
  namespace: podmortem-system
type: Opaque
stringData:
  username: "your-username"
  password: "your-token"
---
apiVersion: podmortem.redhat.com/v1alpha1
kind: PatternLibrary
metadata:
  name: private-patterns
  namespace: podmortem-system
spec:
  repositories:
    - name: "private-patterns-repo"
      url: "https://github.com/your-org/private-patterns.git"
      branch: "main"
      credentials:
        secretRef: "git-credentials"
```

#### 3. Repository Structure

Podmortem loads all `.yml` and `.yaml` files from your repository, so you can organize them however works best for your use:

```
my-app-patterns/
├── database-patterns.yml           # Database-related failures
├── network-patterns.yml            # Network and connectivity issues  
├── startup-patterns.yml            # Application startup problems
└── my-app-patternlibrary.yaml     # Configuration example
```

**Note**: The demo automatically loads Quarkus patterns from the `patterns-quarkus` repository. You can see the pattern library configuration in `config/pattern-library.yaml`.

## Quick Start

Setup:
```bash
cd podmortem/local-demo
make setup
```

Run a test scenario (automatically waits for analysis and resets for next test):
```bash
make run-quarkus-failure
```

The test will:
1. Deploy the failing pod
2. Show the pod failure logs
3. Wait for Podmortem to analyze the failure  
4. Show the AI analysis results
5. Clean up and reset for the next test

You can also watch manually:
```bash
make watch-analysis
```

View results:
```bash
make get-analysis
make logs
```

Cleanup:
```bash
make clean-pods
# or
make destroy
```

## Demo Scenarios

Each scenario automatically waits for analysis and resets when complete:
- `make run-quarkus-failure` - Database connection and CDI issues
- `make run-microservices-failure` - Circuit breaker and messaging failures  
- `make run-infrastructure-failure` - OOM kills and image pull issues
- `make run-performance-failure` - Memory exhaustion and GC issues

**Note**: Each test scenario will take 30-60 seconds to complete as it waits for the pod to fail and analysis to finish.

## Viewing Results

Watch for analysis:
```bash
make watch-analysis
```

Get analysis details:
```bash
make get-analysis
kubectl get podmortem -n demo -o yaml
```

Check operator logs:
```bash
make logs
```

View pod events:
```bash
make events
# or directly
kubectl get events -A --sort-by=.lastTimestamp
kubectl describe pod <pod> -n <ns>
```

Check cluster status:
```bash
make status
```

## Available Commands

Setup:
- `make setup` - Setup everything
- `make cluster` - Create cluster only
- `make setup-openai` - Switch to OpenAI-compatible provider
- `make destroy` - Remove everything

Pattern Management:
- `kubectl get patternlibrary -n podmortem-system` - View loaded pattern libraries
- `kubectl describe patternlibrary quarkus-patterns -n podmortem-system` - Check pattern sync status

Run scenarios (automated - waits for analysis and resets):
- `make run-quarkus-failure`
- `make run-microservices-failure` 
- `make run-infrastructure-failure`
- `make run-performance-failure`

Manual monitoring (if needed):
- `make watch-analysis`
- `make get-analysis`
- `make logs`
- `make events`
- `make status`

Cleanup:
- `make clean-pods`
- `make reset-monitor` - Clear analysis history by resetting the monitor
- `make clean-analysis` - Show how to manually clear analysis results
