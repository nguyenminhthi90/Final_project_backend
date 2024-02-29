terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-east-1"

  # If you have your own AWS account, you can set up a profile
  # using the AWS console and set it here.
  profile = "skobovm"
}

# Note: if not accessing AWS through Vocareum, another SSH keypair
# must be generated for having access to EC2 instances. This key must
# then be used with the SSH client. See:
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/create-key-pairs.html
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AccessingInstances.html
data "aws_key_pair" "ssh_key" {
  key_name           = "ec2_access"
  include_public_key = true

  filter {
    name   = "key-pair-id"
    # IOTEMBSYS: Copy the keypair ID from the current AWS lab.
    # Note: this changes with every new Vocareum lab!
    # This can be found under the EC2 page, in the "Key Pairs" section.

    # WARNING: this is NOT your key; you need to change it
    values = ["key-06c68812aa9271f80"]
  }
}

# Note: If you're using a different key name or path, change the SSH key here.
# You can also pass it in via command line like:
# terraform apply -var="ssh_key_path=personal.pem"
variable "ssh_key_path" {
  type    = string
  default = "labsuser.pem"
}

locals {
  userdata = file("config/userdata.sh")
}

resource "aws_security_group" "allow_all" {
  name        = "allow_all"
  description = "Allow all inbound traffic"

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Inbound"
    from_port        = 4242
    to_port          = 4242
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Inbound HTTP"
    from_port        = 8080
    to_port          = 8080
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Inbound HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Grafana"
    from_port        = 3000
    to_port          = 3000
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_all"
  }
}

# If you'd like to add any other policies, do so here.
locals {
  role_policy_arns = [
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ]
}

resource "aws_iam_instance_profile" "app_server_profile" {
  name = "EC2-Profile"
  role = aws_iam_role.app_server_role.name
}

resource "aws_iam_role_policy_attachment" "app_server_policy_attachment" {
  count = length(local.role_policy_arns)

  role       = aws_iam_role.app_server_role.name
  policy_arn = element(local.role_policy_arns, count.index)
}

# This just serves as an example of how to add a policy to a EC2 instance.
# If you would like S3 access from the server (e.g. to list release binaries)
# this would be the place to add it.
resource "aws_iam_role_policy" "app_server_policy" {
  name = "EC2-Inline-Policy"
  role = aws_iam_role.app_server_role.id
  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : [
            "ssm:GetParameter"
          ],
          "Resource" : "*"
        }
      ]
    }
  )
}

resource "aws_iam_role" "app_server_role" {
  name = "EC2-Role"
  path = "/"

  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : "sts:AssumeRole",
          "Principal" : {
            "Service" : "ec2.amazonaws.com"
          },
          "Effect" : "Allow"
        }
      ]
    }
  )
}

resource "aws_instance" "app_server" {
  ami           = "ami-0557a15b87f6559cf"
  instance_type = "t2.micro"
  key_name      = "ec2_access"
  vpc_security_group_ids = [aws_security_group.allow_all.id]
  iam_instance_profile = aws_iam_instance_profile.app_server_profile.name

  # TODO(mskobov): Install venv package and python/other packages
  # TODO(mskobov): Have separate user data for server/http/tcp
  # TODO(mskobov): Clean up git checkout procedure (e.g. use "release" branch)
  # TODO(mskobov): Use systemd to run python server instead of command
  user_data            = local.userdata

  # Copy the HTTP test server file to the EC2 instance.
  provisioner "file" {
    source = "http_server.py"
    destination = "/home/ubuntu/http_server.py"

    connection {
      type     = "ssh"
      user     = "ubuntu"
      private_key = file(var.ssh_key_path)
      host     = aws_instance.app_server.public_ip
    }
  }

  # Copies the python requirements to the EC2 instance.
  provisioner "file" {
    source = "requirements.txt"
    destination = "/home/ubuntu/requirements.txt"

    connection {
      type     = "ssh"
      user     = "ubuntu"
      private_key = file(var.ssh_key_path)
      host     = aws_instance.app_server.public_ip
    }
  }

  tags = {
    Name = "AppServerInstance"
  }
}

# Note: buckets need to be globally unique!
# Note2: buckets shouldn't be publicly accessible, and should instead be
# private, with the server generating pre-signed URLs to access the binaries.
# That, however, is out of scope for this course.
resource "aws_s3_bucket" "release_bucket" {
  bucket = "skobovm-iotemb-firmware-releases"
}

resource "aws_s3_bucket_ownership_controls" "release_bucket" {
  bucket = aws_s3_bucket.release_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "release_bucket" {
  bucket = aws_s3_bucket.release_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "release_bucket" {
  depends_on = [
    aws_s3_bucket_ownership_controls.release_bucket,
    aws_s3_bucket_public_access_block.release_bucket,
  ]

  bucket = aws_s3_bucket.release_bucket.id
  acl    = "public-read"
}

# Show details from applying
output "instance_public_ip" {
    value = aws_instance.app_server.public_ip
    description = "AWS EC2 Instance Public IP"
}
