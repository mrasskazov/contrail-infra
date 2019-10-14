#!/bin/bash
#
# environment-specific variables for the bootstrap process.
declare -A HOSTS
HOSTS[puppetdb]=tf-infra-puppetdb.mosi.mirantis.net
HOSTS[puppetmaster]=tf-infra-puppetmaster.mosi.mirantis.net
ENVIRONMENT=development
CURRENT_BRANCH=development
