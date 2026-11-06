#!/usr/bin/env bash
# Spoiler warning: this file names every error.
cd "$(dirname "$0")" || exit 1
. ../../ctf/lib.sh
LAB_NAME=lab1
load_state

VPC=$(out vpc_id); PUBLIC_SUBNET=$(out public_subnet_id); PRIVATE_SUBNET=$(out private_subnet_id)
BASTION_ID=$(out bastion_id); BASTION_SG=$(out bastion_sg_id)
BASTION=$(out bastion_public_ip); APP=$(out app_private_ip)

rt_of() { aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$1" --query 'RouteTables[0].RouteTableId' --output text; }

error_def 1 routing 20 "Public subnet associated with the private route table" \
  "Does the bastion's subnet really have a path to the internet?" \
  "Compare the route table each subnet uses with the tables that exist."
error_def 2 security 10 "App security group allows SSH from the wrong subnet" \
  "The bastion works but can't open a session to the app. Compare source addresses." \
  "Which subnet is the bastion really in?"
error_def 3 security 15 "Bastion security group allows the wrong private CIDR" \
  "A NAT is also an instance with a firewall in front of it." \
  "Read the bastion's inbound rules one digit at a time."
error_def 4 instance 20 "Source/destination check enabled on the NAT" \
  "EC2 has an instance-level setting that drops traffic not addressed to the instance." \
  "Look under Actions > Networking."
error_def 5 routing 15 "Private route table has no default route to the NAT" \
  "How would a packet from the private subnet know where the internet is?" \
  "Read the routes in private-rt. Look for 0.0.0.0/0."
error_def 6 security 20 "Bastion security group blocks outbound internet traffic" \
  "Traffic through a NAT instance also has to leave through its security group." \
  "Everyone checks inbound rules. Read the bastion's outbound rules."
error_def 7 routing 30 "More specific route sends half the internet to the IGW" \
  "Some internet destinations work from the app and others don't." \
  "Route tables use longest prefix match. Look for a route more specific than 0.0.0.0/0."
error_def 8 vpc 20 "VPC DNS resolution disabled" \
  "Connecting to an IP works, but connecting to a name doesn't." \
  "It's a setting on the VPC itself."
error_def 9 routing 15 "Main route table has a route to the IGW" \
  "Nothing is broken yet. What would happen to the next subnet someone creates?" \
  "Find the table marked Main."
error_def 10 vpc 10 "Private subnet auto-assigns public IPs" \
  "The next instance launched in the private subnet would have a surprise." \
  "Check the subnet's settings."
error_def 11 final 50 "Final check: the private server reaches the internet through the NAT" \
  "This isn't a new error. It passes by itself once the app has a complete way out." \
  "If it stays open, one of the errors above isn't really fixed. Follow the packet from app to the internet."

check_1() {
  local rt; rt=$(rt_of "$PUBLIC_SUBNET")
  [ "$(aws ec2 describe-route-tables --route-table-ids "$rt" --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId | [0]" --output text)" != None ] &&
    [ "$(aws ec2 describe-route-tables --route-table-ids "$rt" --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId | [0]" --output text | cut -c1-4)" = igw- ]
}
check_2() { [ "$(aws ec2 describe-security-groups --filters "Name=group-name,Values=app-sg" "Name=vpc-id,Values=$VPC" --query "SecurityGroups[0].IpPermissions[?FromPort==\`22\`].IpRanges[].CidrIp | contains(@, '10.30.1.0/24') || contains(@, '10.30.1.10/32') || contains(@, '10.30.0.0/16')" --output text)" = True ]; }
check_3() { [ "$(aws ec2 describe-security-groups --group-ids "$BASTION_SG" --query "SecurityGroups[0].IpPermissions[?FromPort!=\`22\` || IpProtocol=='-1'].IpRanges[].CidrIp | contains(@, '10.30.11.0/24') || contains(@, '10.30.11.10/32') || contains(@, '10.30.0.0/16')" --output text)" = True ]; }
check_4() { [ "$(aws ec2 describe-instances --instance-ids "$BASTION_ID" --query 'Reservations[0].Instances[0].SourceDestCheck' --output text)" = False ]; }
check_5() { aws ec2 describe-route-tables --route-table-ids "$(rt_of "$PRIVATE_SUBNET")" --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].[InstanceId,NetworkInterfaceId,NatGatewayId]" --output text | grep -Eq '(i|eni|nat)-'; }
egress_open() { [ -n "$(aws ec2 describe-security-groups --group-ids "$BASTION_SG" --query "SecurityGroups[0].IpPermissionsEgress[?contains(IpRanges[].CidrIp, '0.0.0.0/0') && (IpProtocol=='-1' || (FromPort<=\`$1\` && ToPort>=\`$1\`))].IpProtocol" --output text)" ]; }
check_6() { egress_open 80 && egress_open 443; }
check_7() { [ -z "$(aws ec2 describe-route-tables --route-table-ids "$(rt_of "$PRIVATE_SUBNET")" --query "RouteTables[0].Routes[?DestinationCidrBlock=='128.0.0.0/1'].DestinationCidrBlock" --output text)" ]; }
check_8() { [ "$(aws ec2 describe-vpc-attribute --vpc-id "$VPC" --attribute enableDnsSupport --query 'EnableDnsSupport.Value' --output text)" = True ]; }
check_9() { [ -z "$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC" "Name=association.main,Values=true" --query "RouteTables[0].Routes[?GatewayId!=null && starts_with(GatewayId, 'igw-')].GatewayId" --output text)" ]; }
check_10() { [ "$(aws ec2 describe-subnets --subnet-ids "$PRIVATE_SUBNET" --query 'Subnets[0].MapPublicIpOnLaunch' --output text)" = False ]; }
check_11() {
  local page ip
  page=$(remote_via "$BASTION" "$APP" 'curl -s -m 3 localhost') || return 1
  [ "$page" = "app online" ] || return 1
  ip=$(remote_via "$BASTION" "$APP" 'curl -s -m 6 https://checkip.amazonaws.com') || return 1
  [ "$ip" = "$BASTION" ]
}

main "$@"
