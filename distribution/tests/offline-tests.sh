#!/bin/bash
# Note: would have used set -euo pipefail, but ./shunit2 unfortunately fails hard with this :-(.

current_directory=$(dirname "$0")
export PATH="$current_directory/../../tools:$PATH"

JENKINS_HOME=to_override

# shellcheck source=tests/utilities
. "$current_directory/utilities"


oneTimeSetUp() {
  setup_container_under_test
  # shellcheck disable=SC2016
  JENKINS_HOME="$( docker exec "$container_under_test" bash -c 'echo $JENKINS_HOME' )"
}

# JENKINS-49864
test_docker_CLI_available() {
  docker exec "$container_under_test" which docker > /dev/null
  assertEquals "docker found in the PATH" 0 $?

  # Check that not only something called docker can be found on the PATH
  # but is actually looking more like it using a specific command call
  output=$( docker exec "$container_under_test" docker --version 2>&1 | cut -d ' ' -f 1,2 )
  assertEquals "Command should succeed" 0 "$?"
  assertEquals "Should start with 'Docker version ...'" "Docker version" "$output"
}

# JENKINS-50195
test_not_root() {
  username=$( docker exec "$container_under_test" whoami )
  assertEquals "root" "$username"

  docker exec "$container_under_test" ps -o user= -o comm= | \
    grep -E 'jenkins|npm' | \
    while read process_user
  do
    currentUser=$( echo "$process_user" | awk '{print $1}' )
    assertEquals "User for '$process_user' should be jenkins" "jenkins" "$currentUser"
  done
}


# Check NPM is 5+ to make sure we do check the integrity values
# https://github.com/jenkins-infra/evergreen/pull/60#discussion_r182666012
test_npm_5_plus() {
  result=$( docker exec "$container_under_test" npm --version )
  assertEquals "5." "${result:0:2}"
}
test_node_version() {
  result=$( docker exec "$container_under_test" node --version )
  assertEquals "v8." "${result:0:3}"
}

# Ensure that we can successfully connect to only Let's Encrypt authorized
# sites. See JEP-307
test_jep_307() {
  result=$( docker exec "$container_under_test" curl -s https://jenkins.io/ )
  assertEquals "jenkins.io should be OK" "0" "$?"

  # Incrementals, like https://repo.jenkins-ci.org/incrementals/org/jenkins-ci/main/jenkins-war/maven-metadata.xml
  result=$( docker exec "$container_under_test" curl -s https://repo.jenkins-ci.org )
  assertEquals "Incrementals repo should be OK" "0" "$?"

  result=$( docker exec "$container_under_test" curl -s https://sonic.com/ )
  assertEquals "everything else should not validate" "60" "$?"
}

. ./shunit2/shunit2
