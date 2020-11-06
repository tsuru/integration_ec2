#!/bin/bash

set -e

if [[ "$AWSKEY" == "" ]] ||
    [[ "$AWSSECRET" == "" ]]; then
    echo "Missing required envs"
    exit 1
fi

export AWS_KUBERNETES_VERSION="1.14"
export AWS_VPC_ID="vpc-01454010307f8e87d"
export AWS_SUBNET_ID="subnet-0018fb7c290dc22ec"
export AWS_SUBNET_IDS="subnet-0018fb7c290dc22ec,subnet-04b0a2fee44861ba6,subnet-03267ff0ea37a7fc9"
export AWS_SECURITY_GROUP_ID="sg-03965b311758f0d0f"
export AWS_REGION="us-east-2"
export AWS_INSTANCE_TYPE="t2.2xlarge"
export EKS_ROLE_ARN="arn:aws:iam::161634971543:role/TsuruEKSIntegrationTest"
export AWS_USERDATA=$(cat <<'EOF'
#!/bin/bash
set -o xtrace
cat /etc/docker/daemon.json | jq '. + {"insecure-registries": ["172.31.0.0/16"]}' > /etc/docker/daemon.json.new
mv /etc/docker/daemon.json /etc/docker/daemon.json.old
mv /etc/docker/daemon.json.new /etc/docker/daemon.json
systemctl restart docker
/etc/eks/bootstrap.sh ${ClusterName} ${BootstrapArguments}
/opt/aws/bin/cfn-signal --exit-code $? --stack ${AWS::StackName} --resource NodeGroup --region ${AWS::Region}
EOF
)

curl --silent --location "https://github.com/weaveworks/eksctl/releases/download/0.30.0/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

function cleanup() {
  if which apt-get; then
    sudo apt-get update
    sudo apt-get install -y python3-pip python3-setuptools
    sudo pip3 install awscli --upgrade
  fi
  aws configure set aws_access_key_id $AWSKEY
  aws configure set aws_secret_access_key $AWSSECRET
  aws configure set default.region $AWS_REGION

  clusters=$(aws eks list-clusters | jq -r '.clusters[] | select(. | contains("icluster-kube-"))')
  stacks=$(aws cloudformation list-stacks --stack-status-filter CREATE_FAILED CREATE_IN_PROGRESS CREATE_COMPLETE | \
    jq -r '.StackSummaries[].StackName | select(. | contains("icluster-kube-"))')
  for cluster in $clusters; do
    aws eks delete-cluster --name $cluster
  done
  for stack in $stacks; do
    aws cloudformation delete-stack --stack-name $stack
  done

  instanceids=$(aws ec2 describe-instances --filter Name=instance.group-name,Values=docker-machine | \
    jq -r '.Reservations[].Instances[].InstanceId')
  if [ ! -z "$instanceids" ]; then
    aws ec2 terminate-instances --instance-ids $instanceids
  fi

  eksctl delete cluster --region=$AWS_REGION --name=icluster-kube-integration --wait || true
}

if which apt-get; then
  cleanup
  trap cleanup EXIT
fi

TSURUVERSION=${TSURUVERSION:-latest}
INTEGRATION_VERSION=${INTEGRATION_VERSION:-${TSURUVERSION}}

echo "Going to test tsuru image version: $TSURUVERSION"

function abspath() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }
mypath=$(abspath $(dirname ${BASH_SOURCE[0]}))
finalconfigpath=$(mktemp)
installname="int-$(uuidgen | head -c 18)"
cp ${mypath}/config.yml ${finalconfigpath}
sed -i.bak "s|\$AWSKEY|${AWSKEY}|g" ${finalconfigpath}
sed -i.bak "s|\$AWSSECRET|${AWSSECRET}|g" ${finalconfigpath}
sed -i.bak "s|\$INSTALLNAME|${installname}|g" ${finalconfigpath}
sed -i.bak "s|\$TSURUVERSION|${TSURUVERSION}|g" ${finalconfigpath}
sed -i.bak "s|\$AWS_VPC_ID|${AWS_VPC_ID}|g" ${finalconfigpath}
sed -i.bak "s|\$AWS_SUBNET_ID|${AWS_SUBNET_ID}|g" ${finalconfigpath}
sed -i.bak "s|\$AWS_INSTANCE_TYPE|${AWS_INSTANCE_TYPE}|g" ${finalconfigpath}
sed -i.bak "s|\$AWS_REGION|${AWS_REGION}|g" ${finalconfigpath}

tmpdir=$(mktemp -d)
export GO111MODULE=on
export GOPATH=${tmpdir}
export PATH=$GOPATH/bin:$PATH
mkdir -p $GOPATH/src/github.com/tsuru
echo "Go get tsuru..."
pushd $GOPATH/src/github.com/tsuru
git clone https://github.com/tsuru/tsuru
git clone https://github.com/tsuru/tsuru-client
git clone https://github.com/tsuru/platforms
popd
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

eksctl create cluster -f cluster.yaml

export TSURU_INTEGRATION_installername="${installname}"
export TSURU_INTEGRATION_examplesdir="${GOPATH}/src/github.com/tsuru/platforms/examples"
export TSURU_INTEGRATION_installerconfig=${finalconfigpath}
export TSURU_INTEGRATION_nodeopts="iaas=dockermachine"
export TSURU_INTEGRATION_maxconcurrency=4
export TSURU_INTEGRATION_verbose=1
export TSURU_INTEGRATION_enabled=1
export TSURU_INTEGRATION_clusters="kubectl"

pushd $GOPATH/src/github.com/tsuru/tsuru
if [ "$INTEGRATION_VERSION" != "latest" ]; then
  git checkout $INTEGRATION_VERSION
fi
go test -v -timeout 120m ./integration
popd

rm -f ${finalconfigpath}
