#!/bin/bash

##############################################################################
# start-kind.sh
#
# Starts up kind instances for each of the 2 clusters.
#
# For setting up the LB, see: https://kind.sigs.k8s.io/docs/user/loadbalancer
#
##############################################################################

SCRIPT_DIR="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)"
source ${SCRIPT_DIR}/env.sh $*

start_kind() {
  local clustername="${1}"
  "${KIND_EXE}" create cluster --name ${clustername}
  if [ "$?" != "0" ]; then
    echo "Failed to start kind for cluster [${clustername}]"
    exit 1
  fi
}

config_metallb() {
  local lb_addr_range="${1}"

  ${CLIENT_EXE} apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.5/config/manifests/metallb-native.yaml
  [ "$?" != "0" ] && echo "Failed to setup metallb on kind" && exit 1

  local subnet=$(${DORP} network inspect kind --format '{{(index .IPAM.Config 0).Subnet}}')
  [ "$?" != "0" ] && echo "Failed to inspect kind network" && exit 1

  kubectl rollout status deployment controller -n metallb-system

  local subnet_trimmed=$(echo ${subnet} | sed -E 's/([0-9]+\.[0-9]+)\.[0-9]+\..*/\1/')
  local first_ip="${subnet_trimmed}.$(echo "${lb_addr_range}" | cut -d '-' -f 1)"
  local last_ip="${subnet_trimmed}.$(echo "${lb_addr_range}" | cut -d '-' -f 2)"
  cat <<LBCONFIGMAP | ${CLIENT_EXE} apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  namespace: metallb-system
  name: config
spec:
  addresses:
  - ${first_ip}-${last_ip}
LBCONFIGMAP

  cat <<LBCONFIGMAP | ${CLIENT_EXE} apply -f -
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  namespace: metallb-system
  name: l2config
spec:
  ipAddressPools:
  - config
LBCONFIGMAP

  [ "$?" != "0" ] && echo "Failed to configure metallb on kind" && exit 1
}

# Find the kind executable
KIND_EXE=`which kind`
if [  -x "${KIND_EXE}" ]; then
  echo "Kind executable: ${KIND_EXE}"
else
  echo "Cannot find the kind executable. You must install it in your PATH. For details, see: https://kind.sigs.k8s.io/docs/user/quick-start"
  exit 1
fi

echo "==== START KIND FOR CLUSTER #1 [${CLUSTER1_NAME}] - ${CLUSTER1_CONTEXT}"
start_kind "${CLUSTER1_NAME}"
switch_cluster "${CLUSTER1_CONTEXT}" "${CLUSTER1_USER}" "${CLUSTER1_PASS}"
config_metallb "255.70-255.84"

echo "==== START KIND FOR CLUSTER #2 [${CLUSTER2_NAME}] - ${CLUSTER2_CONTEXT}"
start_kind "${CLUSTER2_NAME}"
switch_cluster "${CLUSTER2_CONTEXT}" "${CLUSTER2_USER}" "${CLUSTER2_PASS}"
config_metallb "255.85-255.98"
