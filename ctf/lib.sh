#!/usr/bin/env bash
# Capture the Errors engine, shared by the labs. Reading the capture.sh files spoils the game.

KEY=lab-key.pem
LAB_NAME=""
MAX_ID=0
HINT_COST_PERCENT=20
ERR_CATEGORY=(); ERR_POINTS=(); ERR_NAME=(); ERR_HINT1=(); ERR_HINT2=()

SSH_OPTS=(-i "$KEY" -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new
          -o UserKnownHostsFile=.known_hosts -o LogLevel=ERROR)

out() { terraform output -raw "$1" 2>/dev/null; }

error_def() { # id category points name hint1 hint2
  ERR_CATEGORY[$1]=$2; ERR_POINTS[$1]=$3; ERR_NAME[$1]=$4; ERR_HINT1[$1]=$5; ERR_HINT2[$1]=$6
  if [ "$1" -gt "$MAX_ID" ]; then MAX_ID=$1; fi
}

remote() { ssh "${SSH_OPTS[@]}" "ubuntu@$1" "$2" 2>/dev/null; }

remote_via() { # jump-host target command
  ssh "${SSH_OPTS[@]}" \
    -o "ProxyCommand=ssh ${SSH_OPTS[*]} -W %h:%p ubuntu@$1" "ubuntu@$2" "$3" 2>/dev/null
}

sha() { if command -v sha256sum >/dev/null; then sha256sum; else shasum -a 256; fi; }

flag_for() { # id
  local digest
  digest=$(printf '%s:%s:%s' "$CTF_SEED" "$LAB_NAME" "$1" | sha | cut -c1-10)
  printf 'ERR{%s-%02d-%s}' "$LAB_NAME" "$1" "$digest"
}

nacl_for_subnet() {
  aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$1" \
    --query 'NetworkAcls[0].NetworkAclId' --output text
}

# Applies a NACL the way AWS does: lowest rule number first, first match wins.
# Prints allow or deny. Usage: nacl_verdict <acl-id> <in|out> <tcp-port> <peer-ip>
nacl_verdict() {
  local egress=false
  if [ "$2" = out ]; then egress=true; fi
  aws ec2 describe-network-acls --network-acl-ids "$1" \
    --query "NetworkAcls[0].Entries[?Egress==\`$egress\`].[RuleNumber,RuleAction,Protocol,CidrBlock,PortRange.From,PortRange.To]" \
    --output text | sort -n | awk -v port="$3" -v peer="$4" '
    function toint(ip, p) { split(ip, p, "."); return p[1]*16777216 + p[2]*65536 + p[3]*256 + p[4] }
    function incidr(ip, cidr, parts, bits, size) {
      split(cidr, parts, "/"); bits = parts[2]
      if (bits == 0) return 1
      size = 2 ^ (32 - bits)
      return int(toint(ip) / size) == int(toint(parts[1]) / size)
    }
    {
      if ($3 != "-1" && $3 != "6") next
      if (!incidr(peer, $4)) next
      if ($3 == "6" && $5 != "None" && (port < $5 || port > $6)) next
      print $2; exit
    }'
}

alb_get() { # path [extra curl args]. Retries, because one load balancer node may not answer.
  local path=$1 i result
  shift
  for i in 1 2 3 4 5 6; do
    if result=$(curl -s -m 8 --connect-timeout 3 "$@" "http://$ALB_DNS$path"); then
      printf '%s' "$result"
      return 0
    fi
  done
  return 1
}

load_state() {
  local tool
  for tool in terraform aws ssh curl; do
    if ! command -v "$tool" >/dev/null; then
      echo "Missing tool: $tool. See the README."
      exit 1
    fi
  done

  CTF_SEED=$(out ctf_seed)
  if [ -z "$CTF_SEED" ]; then
    echo "No deployment found. Run 'terraform init' and 'terraform apply' in this folder first."
    exit 1
  fi

  export AWS_REGION
  AWS_REGION=$(out region)
  export AWS_DEFAULT_REGION=$AWS_REGION

  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "Warning: the AWS CLI can't confirm your credentials, so errors may show as open."
    echo "Check that your sandbox is still running and your access keys are exported."
    echo
  fi

  if [ ! -f .started ]; then date +%s > .started; fi
  touch .captured .hints
}

hints_used() { grep -c "^$1\$" .hints 2>/dev/null || true; }

show_hint() { # id
  local id=$1 used
  if [ -z "${ERR_NAME[$id]:-}" ]; then
    echo "No error #$id in this lab."
    exit 1
  fi

  used=$(hints_used "$id")
  if [ "$used" -ge 2 ]; then
    echo "Hint 1: ${ERR_HINT1[$id]}"
    echo "Hint 2: ${ERR_HINT2[$id]}"
    return
  fi

  echo "$id" >> .hints
  echo "Hint 1: ${ERR_HINT1[$id]}"
  if [ "$used" -eq 1 ]; then echo "Hint 2: ${ERR_HINT2[$id]}"; fi
  echo "(costs $((ERR_POINTS[id] * HINT_COST_PERCENT / 100)) points per hint)"
}

board() {
  local id status score=0 found=0 now start penalty hints
  printf '\n%s  CAPTURE THE ERRORS\n\n' "$(echo "$LAB_NAME" | tr '[:lower:]' '[:upper:]')"
  printf '%-3s %-10s %4s  %-6s %s\n' '#' CATEGORY PTS HINTS STATUS

  for id in $(seq 1 "$MAX_ID"); do
    hints=$(hints_used "$id")
    if "check_$id"; then
      grep -q "^$id " .captured || echo "$id $(date +%s)" >> .captured
      penalty=$((hints * ERR_POINTS[id] * HINT_COST_PERCENT / 100))
      score=$((score + ERR_POINTS[id] - penalty))
      found=$((found + 1))
      status="CAPTURED $(flag_for "$id")  ${ERR_NAME[$id]}"
    else
      status="open"
    fi
    printf '%-3s %-10s %4s  %-6s %s\n' "$id" "${ERR_CATEGORY[$id]}" "${ERR_POINTS[$id]}" "$hints" "$status"
  done

  now=$(date +%s)
  start=$(cat .started)
  printf '\nCaptured %s/%s   Score %s   Time %s min\n' "$found" "$MAX_ID" "$score" "$(((now - start) / 60))"
  if [ "$found" -eq "$MAX_ID" ]; then echo "All errors captured."; fi
}

main() {
  case "${1:-board}" in
    board)
      board
      ;;
    hint)
      if [ -z "${2:-}" ]; then
        echo "Usage: bash capture.sh hint <error-number>"
        exit 1
      fi
      show_hint "$2"
      ;;
    *)
      echo "Usage: bash capture.sh [hint <error-number>]"
      exit 1
      ;;
  esac
}
