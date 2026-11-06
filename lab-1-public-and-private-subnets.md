# Lab 1: Capture the Errors in the Subnets

**Topic:** public and private subnets, route tables, NAT
**Errors:** 10, plus 1 final check
**Points:** 225
**Time:** about 75 minutes

Start with the [README](README.md) if you haven't.

Every fix in this lab is made in the AWS console. You only use the terminal to deploy, connect and test.

## Set up your sandbox

Do these steps each time you start a new playground session, because the old keys stop working when the session ends.

### Step 1: Create an access key

1. Start your AWS playground and sign in to the AWS console.
2. Open **IAM**, then **Users**, and select your playground user.
3. Open the **Security credentials** tab.
4. Under **Access keys**, choose **Create access key**.
5. Select **Command Line Interface (CLI)**, confirm, and choose **Next**.
6. Choose **Create access key**.
7. Copy the **Access key** and the **Secret access key**. AWS shows the secret only once, so keep this page open until Step 2 is done.

Never commit these keys or share them.

### Step 2: Add the key to the AWS CLI

Run this on your computer:

```bash
aws configure
```

Answer the prompts:

| Prompt | Enter |
|---|---|
| `AWS Access Key ID` | Your access key |
| `AWS Secret Access Key` | Your secret access key |
| `Default region name` | `us-east-1` |
| `Default output format` | `json` |

This saves the key as your **default** profile in `~/.aws/credentials`. Terraform and the grader both use it automatically.

Check that it works:

```bash
aws sts get-caller-identity
```

You should see your playground account and user. If you get an error, or the old account appears, check for old keys in your terminal, which override the default profile:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE
```

Then run `aws sts get-caller-identity` again.

### Step 3: Generate your SSH key

Terraform doesn't create a key for you. It uploads the public half of a key that you generate. From the `aws saa labs` folder:

```bash
cd terraform/lab-1
ssh-keygen -t rsa -b 4096 -m PEM -f lab-key.pem -N ""
```

| Option | Meaning |
|---|---|
| `-t rsa -b 4096` | Creates a 4096-bit RSA key |
| `-m PEM` | Saves the private key in PEM format |
| `-f lab-key.pem` | Sets the file name. Terraform and the grader expect exactly this name |
| `-N ""` | Sets no passphrase, so the grader can connect without a prompt |

This creates two files in `terraform/lab-1`:

| File | What it is |
|---|---|
| `lab-key.pem` | Your private key. It stays on your computer and is never committed |
| `lab-key.pem.pub` | Your public key. Terraform uploads it to AWS as the instances' key pair |

You only need to do this once. The same key works for later sessions, so skip this step if both files already exist.

### Step 4: Deploy with Terraform

Run this from `terraform/lab-1`:

```bash
terraform init
terraform apply -auto-approve
```

Terraform's normal output shows every setting, including the errors you're about to hunt. That's why it's saved to `apply.log`, which you shouldn't open. The command stays silent while it works, and it can take a few minutes. Any failure still appears in your terminal.

Stay in `terraform/lab-1` for the rest of the lab.

If your playground uses another region, add `-var region=<your-region>` to the apply command.

### Step 5: Start the game

```bash
terraform output
bash capture.sh
```

`terraform output` shows your addresses and IDs. `capture.sh` starts the clock and shows the scoreboard, with every error `open`.

### When you finish

Delete everything before your session ends:

```bash
terraform destroy -auto-approve > destroy.log
```

To replay the lab on the same session, delete it, then clear your old progress and deploy again:

```bash
rm -f .started .captured .hints .known_hosts
terraform apply -auto-approve > apply.log
```

## The situation

A team built this VPC and left. It should host a private application server behind a bastion. The bastion is also the NAT instance, because the playground blocks NAT Gateways. Its Linux NAT setup is already correct, so you only need to look at the AWS side. Nothing works, and nobody knows why.

## How it should work

| Item | Value |
|---|---|
| VPC | `lab1-vpc`, `10.30.0.0/16` |
| Public subnet | `public-subnet`, `10.30.1.0/24`, holds `bastion` (`10.30.1.10`) |
| Private subnet | `private-subnet`, `10.30.11.0/24`, holds `app` (`10.30.11.10`) |

## Requirements

1. You can SSH to `bastion` from your IP.
2. You can SSH to `app` through `bastion`.
3. `app` has no public IP, and new instances in `private-subnet` wouldn't get one either.
4. `app` reaches the **whole** internet, by IP and by name, through `bastion`. The internet sees `bastion`'s public IP.
5. Only subnets explicitly attached to a public route table can be public. A new subnet must be private by default.
6. Apache runs on `app`. It installs itself once `app` has a full way out, and `curl localhost` then prints `app online`.

Connect to `app` like this:

```bash
eval "$(ssh-agent)"
ssh-add lab-key.pem
ssh -J ubuntu@<bastion-public-ip> ubuntu@10.30.11.10
```

## Scoreboard

| # | Category | Points |
|---|---|---|
| 1 | routing | 20 |
| 2 | security | 10 |
| 3 | security | 15 |
| 4 | instance | 20 |
| 5 | routing | 15 |
| 6 | security | 20 |
| 7 | routing | 30 |
| 8 | vpc | 20 |
| 9 | routing | 15 |
| 10 | vpc | 10 |
| 11 | final | 50 |

## The final check

Number 11 isn't another error to find. It's the end-to-end test of the whole lab, and it passes by itself once `app` has a complete path to the internet through the NAT.

Connect to `app` and run these two commands to see what the grader sees:

```bash
curl localhost
curl https://checkip.amazonaws.com
```

| Command | Expected result | What it proves |
|---|---|---|
| `curl localhost` | `app online` | Apache was able to download and install from a private subnet |
| `curl https://checkip.amazonaws.com` | The **bastion's** public IP | The internet sees the NAT, not the private server |

If number 11 stays open after the other 10 are captured, re-check your fixes. It can take a few minutes after the last fix, because `app` retries the Apache install in a loop.

## Error report

For each error, record what you found. Being able to explain it matters as much as the flag.

| # | Flag | Resource | Root cause | Evidence |
|---|---|---|---|---|
| | | | | |

## Quiz

Answer these after passing the final check.

**1.** What exactly makes a subnet public?

- A. Auto-assign public IPv4 is enabled
- B. Its associated route table has a route to an Internet Gateway
- C. Its name contains "public"
- D. Its network ACL allows `0.0.0.0/0`

**2.** A route table has `0.0.0.0/0` -> NAT and `128.0.0.0/1` -> IGW. An instance with no public IP calls `149.112.112.112`. What happens?

- A. It goes through the NAT
- B. It goes to the IGW and fails, because the instance has no public IP
- C. It's split evenly between both routes
- D. AWS rejects the route table

**3.** How many usable host addresses does a `/27` subnet have?

- A. 32
- B. 30
- C. 27
- D. 11

**4.** A NAT instance is configured correctly and private route tables point at it, but it drops forwarded traffic. Which EC2 setting is the likely cause?

- A. Detailed monitoring
- B. Source/destination check
- C. Termination protection
- D. The instance's IAM role

**5.** You run private instances in two AZs, with one zonal NAT Gateway in `AZ-a`. `AZ-a` fails. What's the result and the fix?

- A. No impact, because it fails over by itself
- B. `AZ-b` loses internet access, so deploy one NAT Gateway per AZ
- C. `AZ-b` loses internet access, so add a second IGW
- D. No impact, because AWS moves the NAT Gateway

**6.** Where must a NAT Gateway go?

- A. In the private subnet
- B. In a public subnet, with private route tables pointing at it
- C. Attached directly to the VPC
- D. In any subnet, with the IGW pointing at it

**7.** A new subnet has no explicit route table association. Which table does it use?

- A. None, so it has no routes
- B. The VPC's main route table
- C. The most recently created table
- D. The table of the nearest subnet

**8.** An instance can connect to `1.1.1.1`, but `apt update` fails with name resolution errors. What's the most likely cause?

- A. Its security group blocks port 443
- B. DNS resolution is disabled on the VPC
- C. It has no public IP
- D. The NAT has no route

<details>
<summary>Answers</summary>

1. **B.** Only routing makes a subnet public.
2. **B.** The `/1` is more specific than `/0`, so longest prefix match sends it to the IGW.
3. **C.** 32 addresses minus 5 reserved leaves 27.
4. **B.** Instances drop traffic they aren't the source or destination of, unless the check is off.
5. **B.** A zonal NAT Gateway depends on its AZ.
6. **B.** It needs its own path to the IGW.
7. **B.** Without an explicit association, a subnet uses the main route table.
8. **B.** IP connectivity works, so the fault is name resolution.

</details>
