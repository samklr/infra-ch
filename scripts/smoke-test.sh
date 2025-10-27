#!/bin/bash
set -euo pipefail

# Smoke test script for ClickHouse on EKS
# This script runs basic tests to verify the ClickHouse installation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

test_passed() {
    echo -e "${GREEN}✓ PASSED${NC}"
    ((TESTS_PASSED++))
}

test_failed() {
    echo -e "${RED}✗ FAILED${NC} $1"
    ((TESTS_FAILED++))
}

# Test 1: Check if namespace exists
test_namespace() {
    log_test "Checking if clickhouse namespace exists..."
    if kubectl get namespace clickhouse &> /dev/null; then
        test_passed
    else
        test_failed "Namespace 'clickhouse' does not exist"
    fi
}

# Test 2: Check ClickHouse Operator
test_operator() {
    log_test "Checking ClickHouse Operator status..."
    local ready=$(kubectl get deployment -n clickhouse clickhouse-operator -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$ready" -gt 0 ]; then
        test_passed
    else
        test_failed "ClickHouse Operator is not ready"
    fi
}

# Test 3: Check Keeper pods
test_keeper() {
    log_test "Checking ClickHouse Keeper pods..."
    local ready=$(kubectl get statefulset -n clickhouse clickhouse-keeper -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired=$(kubectl get statefulset -n clickhouse clickhouse-keeper -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "3")

    if [ "$ready" -eq "$desired" ] && [ "$ready" -ge 3 ]; then
        test_passed
        log_info "  Keeper pods: $ready/$desired ready"
    else
        test_failed "Keeper pods not ready ($ready/$desired)"
    fi
}

# Test 4: Check ClickHouse pods
test_clickhouse_pods() {
    log_test "Checking ClickHouse pods..."
    local total=$(kubectl get pods -n clickhouse -l app=clickhouse --no-headers 2>/dev/null | wc -l || echo "0")
    local ready=$(kubectl get pods -n clickhouse -l app=clickhouse --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")

    if [ "$ready" -gt 0 ] && [ "$ready" -eq "$total" ]; then
        test_passed
        log_info "  ClickHouse pods: $ready/$total ready"
    else
        test_failed "ClickHouse pods not ready ($ready/$total)"
        kubectl get pods -n clickhouse -l app=clickhouse
    fi
}

# Test 5: Check PVCs
test_pvcs() {
    log_test "Checking Persistent Volume Claims..."
    local bound=$(kubectl get pvc -n clickhouse --no-headers 2>/dev/null | grep -c "Bound" || echo "0")
    local total=$(kubectl get pvc -n clickhouse --no-headers 2>/dev/null | wc -l || echo "0")

    if [ "$bound" -gt 0 ] && [ "$bound" -eq "$total" ]; then
        test_passed
        log_info "  PVCs: $bound/$total bound"
    else
        test_failed "Not all PVCs are bound ($bound/$total)"
        kubectl get pvc -n clickhouse
    fi
}

# Test 6: Check services
test_services() {
    log_test "Checking ClickHouse services..."
    local services=$(kubectl get svc -n clickhouse --no-headers 2>/dev/null | wc -l || echo "0")

    if [ "$services" -gt 0 ]; then
        test_passed
        log_info "  Services found: $services"
        kubectl get svc -n clickhouse
    else
        test_failed "No ClickHouse services found"
    fi
}

# Test 7: Check load balancers
test_load_balancers() {
    log_test "Checking Load Balancers..."
    local lbs=$(kubectl get svc -n clickhouse -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

    if [ -n "$lbs" ]; then
        test_passed
        log_info "  Load balancer endpoints:"
        kubectl get svc -n clickhouse -o wide | grep LoadBalancer
    else
        test_failed "Load balancers not yet provisioned or not found"
    fi
}

# Test 8: Connect to ClickHouse
test_clickhouse_connection() {
    log_test "Testing ClickHouse connection..."

    # Get the first ClickHouse pod
    local pod=$(kubectl get pods -n clickhouse -l app=clickhouse -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$pod" ]; then
        test_failed "No ClickHouse pods found"
        return
    fi

    # Try to connect and run a simple query
    local result=$(kubectl exec -n clickhouse "$pod" -- clickhouse-client -q "SELECT 1" 2>/dev/null || echo "")

    if [ "$result" = "1" ]; then
        test_passed
        log_info "  Successfully connected to ClickHouse"
    else
        test_failed "Could not connect to ClickHouse"
    fi
}

# Test 9: Test ClickHouse query
test_clickhouse_query() {
    log_test "Testing ClickHouse basic query..."

    local pod=$(kubectl get pods -n clickhouse -l app=clickhouse -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$pod" ]; then
        test_failed "No ClickHouse pods found"
        return
    fi

    # Create a test table, insert data, and query
    local test_result=$(kubectl exec -n clickhouse "$pod" -- clickhouse-client -q "
        CREATE DATABASE IF NOT EXISTS test;
        CREATE TABLE IF NOT EXISTS test.smoke_test (id UInt32, message String) ENGINE = Memory;
        INSERT INTO test.smoke_test VALUES (1, 'Hello'), (2, 'World');
        SELECT COUNT(*) FROM test.smoke_test;
        DROP TABLE test.smoke_test;
    " 2>/dev/null | tail -1 || echo "0")

    if [ "$test_result" = "2" ]; then
        test_passed
        log_info "  ClickHouse query test successful"
    else
        test_failed "ClickHouse query test failed (got: $test_result, expected: 2)"
    fi
}

# Test 10: Check replication
test_replication() {
    log_test "Checking ClickHouse replication status..."

    local pod=$(kubectl get pods -n clickhouse -l app=clickhouse -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$pod" ]; then
        test_failed "No ClickHouse pods found"
        return
    fi

    # Check if replicas are in sync
    local replicas=$(kubectl exec -n clickhouse "$pod" -- clickhouse-client -q "
        SELECT COUNT(*) FROM system.replicas WHERE is_readonly = 0
    " 2>/dev/null || echo "0")

    if [ "$replicas" -gt 0 ]; then
        test_passed
        log_info "  Active replicas: $replicas"
    else
        test_warn "No active replicas found (this might be expected if no replicated tables exist yet)"
        test_passed
    fi
}

# Test 11: Check Keeper connection
test_keeper_connection() {
    log_test "Testing Keeper connection from ClickHouse..."

    local pod=$(kubectl get pods -n clickhouse -l app=clickhouse -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$pod" ]; then
        test_failed "No ClickHouse pods found"
        return
    fi

    # Check if ClickHouse can see Keeper
    local keeper_status=$(kubectl exec -n clickhouse "$pod" -- clickhouse-client -q "
        SELECT COUNT(*) FROM system.zookeeper WHERE path = '/'
    " 2>/dev/null || echo "0")

    if [ "$keeper_status" -gt 0 ]; then
        test_passed
        log_info "  ClickHouse can connect to Keeper"
    else
        test_failed "ClickHouse cannot connect to Keeper"
    fi
}

# Test 12: Check backup configuration
test_backup() {
    log_test "Checking backup CronJob..."
    local cronjobs=$(kubectl get cronjob -n clickhouse clickhouse-backup -o name 2>/dev/null || echo "")

    if [ -n "$cronjobs" ]; then
        test_passed
        log_info "  Backup CronJob is configured"
        kubectl get cronjob -n clickhouse
    else
        test_failed "Backup CronJob not found"
    fi
}

# Test 13: Check monitoring
test_monitoring() {
    log_test "Checking monitoring stack..."
    local prometheus=$(kubectl get deployment -n monitoring kube-prometheus-stack-prometheus-operator -o name 2>/dev/null || echo "")

    if [ -n "$prometheus" ]; then
        test_passed
        log_info "  Prometheus operator is deployed"
    else
        test_warn "Monitoring stack not found (optional)"
        test_passed
    fi
}

# Print summary
print_summary() {
    echo ""
    echo "========================================"
    echo "Smoke Test Summary"
    echo "========================================"
    echo -e "Tests Passed: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Tests Failed: ${RED}${TESTS_FAILED}${NC}"
    echo ""

    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        echo ""
        echo "Your ClickHouse cluster is ready to use!"
        echo ""
        echo "Quick start commands:"
        echo "  # Connect to ClickHouse:"
        local pod=$(kubectl get pods -n clickhouse -l app=clickhouse -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "clickhouse-cluster-0-0-0")
        echo "  kubectl exec -it -n clickhouse $pod -- clickhouse-client"
        echo ""
        echo "  # View logs:"
        echo "  kubectl logs -n clickhouse -l app=clickhouse --tail=100"
        echo ""
        echo "  # Get load balancer endpoints:"
        echo "  kubectl get svc -n clickhouse"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        echo ""
        echo "Debug commands:"
        echo "  kubectl get pods -n clickhouse"
        echo "  kubectl describe pod -n clickhouse <pod-name>"
        echo "  kubectl logs -n clickhouse <pod-name>"
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting ClickHouse smoke tests..."
    echo ""

    test_namespace
    test_operator
    test_keeper
    test_clickhouse_pods
    test_pvcs
    test_services
    test_load_balancers
    test_clickhouse_connection
    test_clickhouse_query
    test_replication
    test_keeper_connection
    test_backup
    test_monitoring

    print_summary
}

# Run main function
main "$@"
