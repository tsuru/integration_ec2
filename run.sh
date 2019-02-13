#!/bin/bash

set -e

export AWS_VPC_ID="vpc-881598ed"
export AWS_SUBNET_ID="subnet-6d907c46"
export AWS_SUBNET_IDS="subnet-6d907c46,subnet-a363c1d4"
export AWS_SECURITY_GROUP_ID="sg-46a6e73d"
export AWS_REGION="us-east-1"
export AWS_INSTANCE_TYPE="t2.2xlarge"
export AWS_USERDATA=$(cat <<'EOF'
#!/bin/bash
set -o xtrace
cat /etc/docker/daemon.json | jq '. + {"insecure-registries": ["172.30.0.0/16"]}' > /etc/docker/daemon.json.new
mv /etc/docker/daemon.json /etc/docker/daemon.json.old
mv /etc/docker/daemon.json.new /etc/docker/daemon.json
systemctl restart docker
/etc/eks/bootstrap.sh ${ClusterName} ${BootstrapArguments}
/opt/aws/bin/cfn-signal --exit-code $? --stack ${AWS::StackName} --resource NodeGroup --region ${AWS::Region}
EOF
)

TSURUVERSION=${TSURUVERSION:-latest}

echo "Going to test tsuru image version: $TSURUVERSION"

function abspath() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }
mypath=$(abspath $(dirname ${BASH_SOURCE[0]}))
finalconfigpath=$(mktemp)
installname=$(uuidgen | head -c 18)
cp ${mypath}/config.yml ${finalconfigpath}
sed -i.bak "s|\$AWSKEY|${AWSKEY}|g" ${finalconfigpath}
sed -i.bak "s|\$AWSSECRET|${AWSSECRET}|g" ${finalconfigpath}
sed -i.bak "s|\$INSTALLNAME|int-${installname}|g" ${finalconfigpath}
sed -i.bak "s|\$TSURUVERSION|${TSURUVERSION}|g" ${finalconfigpath}
sed -i.bak "s|\$AWS_VPC_ID|${AWS_VPC_ID}|g" ${finalconfigpath}
sed -i.bak "s|\$AWS_SUBNET_ID|${AWS_SUBNET_ID}|g" ${finalconfigpath}
sed -i.bak "s|\$AWS_INSTANCE_TYPE|${AWS_INSTANCE_TYPE}|g" ${finalconfigpath}
sed -i.bak "s|\$AWS_REGION|${AWS_REGION}|g" ${finalconfigpath}

tmpdir=$(mktemp -d)
export GOPATH=${tmpdir}
export PATH=$GOPATH/bin:$PATH
echo "Go get platforms..."
go get -d github.com/tsuru/platforms/examples/go
echo "Go get tsuru..."
go get github.com/tsuru/tsuru/integration

echo "Go get tsuru client..."
go get -d github.com/tsuru/tsuru-client/tsuru
pushd $GOPATH/src/github.com/tsuru/tsuru-client
if [ "$TSURUVERSION" != "latest" ]; then
  MINOR=$(echo "$TSURUVERSION" | sed -E 's/^[^0-9]*([0-9]+\.[0-9]+).*$/\1/g')
  CLIENT_TAG=$(git tag --list "$MINOR.*" --sort=-taggerdate | head -1)
  if [ "$CLIENT_TAG" != "" ]; then
    echo "Checking out tsuru-client $CLIENT_TAG"
    git checkout $CLIENT_TAG
  fi
fi
go install ./...
popd

export TSURU_INTEGRATION_examplesdir="${GOPATH}/src/github.com/tsuru/platforms/examples"
export TSURU_INTEGRATION_installerconfig=${finalconfigpath}
export TSURU_INTEGRATION_nodeopts="iaas=dockermachine"
export TSURU_INTEGRATION_maxconcurrency=4
export TSURU_INTEGRATION_verbose=1
export TSURU_INTEGRATION_enabled=1
export TSURU_INTEGRATION_clusters="eks"

go test -v -timeout 120m github.com/tsuru/tsuru/integration

rm -f ${finalconfigpath}
