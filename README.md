# AWS SAA Labs: Capture the Errors

A capture-the-errors challenge for SAA-C03. Terraform deploys a broken AWS environment, and you hunt down what's wrong with it. Each error you truly fix gives you a flag and points.

| Lab | Topic | Errors | Points |
|---|---|---|---|
| [Lab 1](lab-1-public-and-private-subnets.md) | Public and private subnets | 10 + final check | 225 |

## Rules

1. **Don't read `main.tf`, `capture.sh`, `terraform.tfstate` or `apply.log`.** They contain the answers.
2. **Fix errors in the AWS console.** Don't edit the Terraform files.
3. **You aren't told what's broken.** You get the requirements. Work out the rest from evidence.
4. **A flag only appears when the error is really fixed.** The grader checks your live environment.

## What you need

- Terraform 1.5 or newer
- AWS CLI v2
- `ssh`, `curl` and `bash` (on Windows, use WSL)
- An AWS playground session

The [Lab 1 sheet](lab-1-public-and-private-subnets.md) has the steps to create an access key, configure the AWS CLI and deploy with Terraform.

## Commands

Run these from `terraform/lab-1`.

| Command | What it does |
|---|---|
| `bash capture.sh` | Tests your environment and shows the scoreboard |
| `bash capture.sh hint 4` | Shows a hint for error 4, and costs 20% of its points. Each error has 2 hints |
| `terraform output` | Shows the addresses and IDs of your deployment |
| `terraform destroy` | Deletes the lab. Do this when you finish |

A scoreboard run takes a little while, because it tests everything live. The clock starts the first time you run it.

The error numbers aren't in solving order, and some errors hide behind others. For example, you can't test anything on a server until you can reach it.

## Competing

Each student or team deploys their own lab and compares score and time. Highest score wins, and the faster time breaks a tie. Flags are unique to each deployment.

Instructors: the answers are in [instructor-solutions.md](instructor-solutions.md).
