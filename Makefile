
CLUSTER_NAME := podmortem-demo
PODMORTEM_NAMESPACE := podmortem-system
DEMO_NAMESPACE := demo
KUBECTL_CONTEXT := kind-$(CLUSTER_NAME)

.DEFAULT_GOAL := help

.PHONY: setup
setup: cluster deploy configure 
	@echo "Demo environment setup complete."

.PHONY: cluster
cluster:
	@./scripts/setup-kind-cluster.sh

.PHONY: deploy
deploy: 
	@echo "Deploying Podmortem operator..."
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl apply -f kubernetes/aiprovider-crd.yaml > /dev/null
	@kubectl apply -f kubernetes/patternlibrary-crd.yaml > /dev/null
	@kubectl apply -f kubernetes/podmortem-crd.yaml > /dev/null
	@kubectl apply -f kubernetes/operator-serviceaccount.yaml > /dev/null
	@kubectl apply -f kubernetes/operator-rbac.yaml > /dev/null
	@kubectl apply -f kubernetes/operator-deployment.yaml > /dev/null
	@kubectl apply -f kubernetes/ai-interface-deployment.yaml > /dev/null
	@kubectl apply -f kubernetes/ai-interface-service.yaml > /dev/null
	@kubectl apply -f kubernetes/log-parser-deployment.yaml > /dev/null
	@kubectl apply -f kubernetes/log-parser-service.yaml > /dev/null
	@kubectl apply -f kubernetes/pattern-cache-pvc.yaml > /dev/null
	@kubectl wait --for=condition=ready pod -l app=podmortem-operator -n $(PODMORTEM_NAMESPACE) --timeout=300s > /dev/null 2>&1

.PHONY: configure
configure: 
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl apply -f config/rbac.yaml > /dev/null
	@kubectl apply -f config/ai-provider.yaml > /dev/null
	@kubectl apply -f config/pattern-library.yaml > /dev/null
	@kubectl apply -f config/podmortem-monitor.yaml > /dev/null

.PHONY: destroy
destroy: 
	@./scripts/setup-kind-cluster.sh delete

.PHONY: run-quarkus-failure
run-quarkus-failure:
	@echo "Deploying Quarkus failure scenario..."
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl apply -f test-pods/quarkus-complex-failure.yaml > /dev/null
	@echo "Scenario deployed. Waiting for analysis..."
	@$(MAKE) --no-print-directory _wait-and-show-analysis
	@$(MAKE) --no-print-directory _reset-for-next-test

.PHONY: run-microservices-failure
run-microservices-failure:
	@echo "Deploying Microservices failure scenario..."
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl apply -f test-pods/microservices-cascade-failure.yaml > /dev/null
	@echo "Scenario deployed. Waiting for analysis..."
	@$(MAKE) --no-print-directory _wait-and-show-analysis
	@$(MAKE) --no-print-directory _reset-for-next-test

.PHONY: run-infrastructure-failure
run-infrastructure-failure:
	@echo "Deploying Infrastructure failure scenario..."
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl apply -f test-pods/kubernetes-infrastructure-failure.yaml > /dev/null
	@echo "Scenario deployed. Waiting for analysis..."
	@$(MAKE) --no-print-directory _wait-and-show-analysis
	@$(MAKE) --no-print-directory _reset-for-next-test

.PHONY: run-performance-failure
run-performance-failure:
	@echo "Deploying Performance failure scenario..."
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl apply -f test-pods/performance-memory-degradation.yaml > /dev/null
	@echo "Scenario deployed. Waiting for analysis..."
	@$(MAKE) --no-print-directory _wait-and-show-analysis
	@$(MAKE) --no-print-directory _reset-for-next-test

.PHONY: _wait-and-show-analysis
_wait-and-show-analysis:
	@echo "Getting pod logs..."
	@echo "----------------------------------------"
	@sleep 5
	@kubectl logs -l test-scenario=true -n $(DEMO_NAMESPACE) --tail=50 2>/dev/null || echo "Pod not ready yet, waiting..."
	@echo "----------------------------------------"
	@echo "Waiting for analysis to complete..."
	@echo "Press Ctrl+C to stop waiting..."
	@for i in $$(seq 1 60); do \
		POD_NAME=$$(kubectl get pods -l test-scenario=true -n $(DEMO_NAMESPACE) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
		if [ -n "$$POD_NAME" ]; then \
			ANALYSIS=$$(kubectl get pod $$POD_NAME -n $(DEMO_NAMESPACE) -o jsonpath='{.metadata.annotations.podmortem\.io/analysis}' 2>/dev/null); \
			if [ -n "$$ANALYSIS" ]; then \
				echo ""; \
				echo "========================================"; \
				echo "AI Analysis Complete:"; \
				echo "========================================"; \
				echo "$$ANALYSIS" | fold -s -w 80; \
				echo ""; \
				echo "----------------------------------------"; \
				SEVERITY=$$(kubectl get pod $$POD_NAME -n $(DEMO_NAMESPACE) -o jsonpath='{.metadata.annotations.podmortem\.io/severity}' 2>/dev/null); \
				TIMESTAMP=$$(kubectl get pod $$POD_NAME -n $(DEMO_NAMESPACE) -o jsonpath='{.metadata.annotations.podmortem\.io/analyzed-at}' 2>/dev/null); \
				if [ -n "$$SEVERITY" ]; then echo "Severity: $$SEVERITY"; fi; \
				if [ -n "$$TIMESTAMP" ]; then echo "Analyzed at: $$TIMESTAMP"; fi; \
				echo "----------------------------------------"; \
				echo "Tip: Use 'kubectl describe pod $$POD_NAME -n $(DEMO_NAMESPACE)' to see full details"; \
				break; \
			fi; \
		fi; \
		EVENT=$$(kubectl get events -n $(DEMO_NAMESPACE) --field-selector reason=PodmortemAnalysisComplete -o jsonpath='{.items[0].message}' 2>/dev/null); \
		if [ -n "$$EVENT" ] && [ "$$i" -gt 10 ]; then \
			echo ""; \
			echo "Analysis event detected (truncated summary):"; \
			echo "$$EVENT" | fold -s -w 80; \
			echo ""; \
			echo "Note: Full analysis may be available in pod annotations or Podmortem status"; \
			break; \
		fi; \
		echo "Waiting for analysis... ($$i/60)"; \
		sleep 5; \
	done
	@echo "----------------------------------------"

.PHONY: _reset-for-next-test
_reset-for-next-test:
	@echo "Cleaning up and resetting for next test..."
	@kubectl delete pod -l test-scenario=true -n $(DEMO_NAMESPACE) --ignore-not-found=true > /dev/null 2>&1
	@kubectl delete podmortem demo-monitor -n $(DEMO_NAMESPACE) --ignore-not-found=true > /dev/null 2>&1
	@sleep 2
	@kubectl apply -f config/podmortem-monitor.yaml > /dev/null
	@echo "Ready for next test!"

.PHONY: watch-analysis
watch-analysis:
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl get podmortem -n $(DEMO_NAMESPACE) --watch

.PHONY: get-analysis
get-analysis: 
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl get podmortem -n $(DEMO_NAMESPACE) -o yaml

.PHONY: get-pod-analysis
get-pod-analysis:
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@POD_NAME=$$(kubectl get pods -l test-scenario=true -n $(DEMO_NAMESPACE) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -n "$$POD_NAME" ]; then \
		echo "Pod: $$POD_NAME"; \
		echo "----------------------------------------"; \
		ANALYSIS=$$(kubectl get pod $$POD_NAME -n $(DEMO_NAMESPACE) -o jsonpath='{.metadata.annotations.podmortem\.io/analysis}' 2>/dev/null); \
		if [ -n "$$ANALYSIS" ]; then \
			echo "$$ANALYSIS"; \
		else \
			echo "No analysis found in pod annotations."; \
			echo "Checking Podmortem CR status..."; \
			kubectl get podmortem demo-monitor -n $(DEMO_NAMESPACE) -o jsonpath='{.status.recentFailures[0].explanation}' 2>/dev/null || echo "No analysis found."; \
		fi; \
	else \
		echo "No test pod found. Run a test scenario first."; \
	fi

.PHONY: logs
logs:
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl logs -l app=podmortem-operator -n $(PODMORTEM_NAMESPACE) --tail=50

.PHONY: logs-parser
logs-parser:
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl logs -l app=podmortem-log-parser -n $(PODMORTEM_NAMESPACE) --tail=50

.PHONY: logs-ai
logs-ai:
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl logs -l app=podmortem-ai-interface -n $(PODMORTEM_NAMESPACE) --tail=50

.PHONY: events
events:
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl get events -n $(DEMO_NAMESPACE) --sort-by='.lastTimestamp' | tail -20

.PHONY: status
status: ## Show cluster and operator status
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@echo "Nodes:"
	@kubectl get nodes
	@echo ""
	@echo "Operator Pods:"
	@kubectl get pods -n $(PODMORTEM_NAMESPACE)
	@echo ""
	@echo "Demo Pods:"
	@kubectl get pods -n $(DEMO_NAMESPACE)
	@echo ""
	@echo "AI Provider:"
	@kubectl get aiprovider -n $(PODMORTEM_NAMESPACE)
	@echo ""
	@echo "Pattern Library:"
	@kubectl get patternlibrary -n $(PODMORTEM_NAMESPACE)
	@echo ""
	@echo "Podmortem Monitor:"
	@kubectl get podmortem -n $(DEMO_NAMESPACE)

.PHONY: clean-pods
clean-pods:
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl delete pods -l test-scenario=true -n $(DEMO_NAMESPACE) --ignore-not-found=true > /dev/null 2>&1

.PHONY: clean-analysis
clean-analysis:
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@echo "Note: Analysis results are stored in podmortem status. To clear them, restart the monitor:"
	@echo "  kubectl delete podmortem demo-monitor -n $(DEMO_NAMESPACE)"
	@echo "  kubectl apply -f config/podmortem-monitor.yaml"

.PHONY: reset-monitor
reset-monitor:
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl delete podmortem demo-monitor -n $(DEMO_NAMESPACE) --ignore-not-found=true > /dev/null 2>&1
	@kubectl apply -f config/podmortem-monitor.yaml > /dev/null
	@echo "Monitor reset - analysis history cleared."

.PHONY: restart-operator
restart-operator:
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl rollout restart deployment/podmortem-operator -n $(PODMORTEM_NAMESPACE) > /dev/null
	@kubectl rollout restart deployment/podmortem-log-parser-service -n $(PODMORTEM_NAMESPACE) > /dev/null
	@kubectl rollout restart deployment/podmortem-ai-interface-service -n $(PODMORTEM_NAMESPACE) > /dev/null
	@kubectl rollout status deployment/podmortem-operator -n $(PODMORTEM_NAMESPACE) > /dev/null 2>&1

.PHONY: health-check
health-check:
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl cluster-info
	@echo ""
	@kubectl get pods -n $(PODMORTEM_NAMESPACE) -o wide
	@echo ""
	@kubectl get aiprovider -n $(PODMORTEM_NAMESPACE) -o jsonpath='{.items[0].status}' 2>/dev/null || echo "No AI provider found"
	@echo ""
	@kubectl get patternlibrary -n $(PODMORTEM_NAMESPACE) -o jsonpath='{.items[0].status}' 2>/dev/null || echo "No pattern library found"

.PHONY: build-test-image
build-test-image:
	@cd test-pods && podman build -t localhost/podmortem-test-logs:latest . > /dev/null

.PHONY: load-test-image
load-test-image: build-test-image
	@podman save localhost/podmortem-test-logs:latest | kind load image-archive /dev/stdin --name $(CLUSTER_NAME) > /dev/null

.PHONY: update-test-images
update-test-images:
	@find test-pods -name "*.yaml" -exec sed -i '' 's|ghcr.io/podmortem/podmortem/test-logs:latest|localhost/podmortem-test-logs:latest|g' {} \;
	@find test-pods -name "*.yaml" -exec sed -i '' 's|imagePullPolicy: Always|imagePullPolicy: Never|g' {} \;

.PHONY: dev-setup
dev-setup: cluster load-test-image update-test-images deploy configure
	@echo "Development environment ready."

.PHONY: port-forward-ai
port-forward-ai:
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl port-forward -n $(PODMORTEM_NAMESPACE) svc/podmortem-ai-interface-service 8081:8080

.PHONY: port-forward-parser
port-forward-parser:
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl port-forward -n $(PODMORTEM_NAMESPACE) svc/podmortem-log-parser-service 8080:8080

.PHONY: shell-operator
shell-operator:
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl exec -it -n $(PODMORTEM_NAMESPACE) deployment/podmortem-operator -- /bin/bash

.PHONY: setup-openai
setup-openai:
	@kubectl config use-context $(KUBECTL_CONTEXT)
	@kubectl apply -f config/ai-provider-openai.yaml > /dev/null
	@echo "OpenAI-compatible provider configured. Make sure to update the API key in the secret."

.PHONY: help
help:
	@awk 'BEGIN {FS = ":.*##"; printf "\nPodmortem Local Demo Commands:\n\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  %-25s %s\n", $$1, $$2 } /^##@/ { printf "\n%s\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: info
info:
	@echo "Demo Environment Information"
	@echo "Cluster: $(CLUSTER_NAME)"
	@echo "Context: $(KUBECTL_CONTEXT)"
	@echo "Namespaces: $(PODMORTEM_NAMESPACE), $(DEMO_NAMESPACE)"
	@echo ""
	@echo "Available Scenarios:"
	@ls test-pods/*.yaml | sed 's|test-pods/||' | sed 's|.yaml||' | sed 's|^|  - |'

.PHONY: version
version:
	@echo "Podmortem Demo: 1.0.0"
	@kubectl version --short 2>/dev/null || echo "kubectl not available"
	@kind version 2>/dev/null || echo "kind not available"
	@podman version --format "Podman: {{.Version}}" 2>/dev/null || echo "Podman not available" 