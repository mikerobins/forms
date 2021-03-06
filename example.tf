provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "${var.aws_region}"
}

/*
resource "aws_vpc" "default" {

  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = "true"

  tags {
    project = "twitter"
  }

}
*/

resource "aws_security_group" "twitter_ingress" {
  name = "vpc_twitter_ingress"
  description = "Allow ssh traffic"

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["${var.my_ip}"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

//  vpc_id = "${aws_vpc.default.id}"
}

// Setup bucket for twitter images
resource "aws_s3_bucket" "tweetbucket" {
  bucket = "archimage-solutions.twitter.tweets"
  acl = "private"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags {
    project = "twitter"
  }
}

// IAM role for EC2 Tweet grabbing instance
resource "aws_iam_role" "tweets_iam_role" {
  name = "tweets_iam_role"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
              "Service": [
                "ec2.amazonaws.com"
              ]
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

// IAM role for Kinesis lambda which dumps tweets to dynamo
resource "aws_iam_role" "kinesis_lambda_dynamo_role" {
  name = "kinesis_lambda_dynamo_role"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
              "Service": [
                "lambda.amazonaws.com"
              ]
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

// Kinesis ingest EC2 role
resource "aws_iam_role" "kinesis_ingest_iam_role" {
  name = "kinesis_ingest_iam_role"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
              "Service": [
                "ec2.amazonaws.com"
              ]
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

resource "aws_iam_instance_profile" "kinesis_ingest_ec2_profile" {
   name = "kinesis_ingest_ec2_profile"
   role = "kinesis_ingest_iam_role"
}

resource "aws_iam_instance_profile" "tweets_ec2_profile" {
   name = "tweets_ec2_profile"
   role = "tweets_iam_role"
}

// IAM policy which allows tweets to be placed in Kinesis
resource "aws_iam_role_policy" "tweets_iam_role_policy" {
   name = "tweets_iam_role_policy"
   role = "${aws_iam_role.tweets_iam_role.id}"
   policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kinesis:PutRecord"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

// IAM policy allowing kinesis ingest to push stuff to dynamo
resource "aws_iam_role_policy" "kinesis_ingest_iam_role_policy" {
   name = "kinesis_ingest_iam_role_policy"
   role = "${aws_iam_role.kinesis_ingest_iam_role.id}"
   policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kinesis:DescribeStream",
        "kinesis:GetShardIterator",
        "kinesis:GetRecords",
	"dynamodb:*",
	"cloudwatch:PutMetricData",
        "s3:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

// Define kinesis stream for tweets - note the dynamo table for this is not auto-destroyed
resource "aws_kinesis_stream" "tweet_stream" {
  name             = "tweet_stream"
  shard_count      = 1
  retention_period = 24

  shard_level_metrics = [
    "IncomingBytes",
    "OutgoingBytes",
  ]

  tags {
    Environment = "test"
  }
}

// EC2 instance to scrape tweets
resource "aws_instance" "twitter_api_scrape" {
  ami           = "ami-26ebbc5c" // RHEL 7.4
//  ami           = "ami-2757f631" Ubuntu
  instance_type = "t2.micro"
  iam_instance_profile = "${aws_iam_instance_profile.tweets_ec2_profile.id}"
  key_name = "banana"
  vpc_security_group_ids = ["${aws_security_group.twitter_ingress.id}"]

  tags {
    project = "twitter"
  }
}

// EC2 instance for processing kinesis stream to get images
resource "aws_instance" "example" {
  ami           = "ami-26ebbc5c" // RHEL 7.4
//  ami           = "ami-2757f631" Ubuntu
  instance_type = "t2.micro"
  iam_instance_profile = "${aws_iam_instance_profile.kinesis_ingest_ec2_profile.id}"
  key_name = "banana"
  vpc_security_group_ids = ["${aws_security_group.twitter_ingress.id}"]

  tags {
    project = "twitter"
  }
}

// Permissive policy for lambdas allowing kinesis, logs, dynamo and comprehend access
resource "aws_iam_policy" "lambda_kinesis_dynamo" {
  name = "lambda_kinesis_dynamo"
  description = " IAM policy allowing lambda to talk to Kinesis and Dynamo"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": [
                "logs:*",
                "kinesis:ListStreams",
                "kinesis:GetShardIterator",
                "kinesis:GetRecords",
                "kinesis:DescribeStream",
                "dynamodb:*",
		"comprehend:*"
            ],
            "Resource": "*"
        }
    ]
}    
EOF
}


resource "aws_iam_role_policy_attachment" "lambda_kinesis_dynamo" {
   role = "${aws_iam_role.kinesis_lambda_dynamo_role.name}"
   policy_arn = "${aws_iam_policy.lambda_kinesis_dynamo.arn}"
}


// Tweets table
resource "aws_dynamodb_table" "tweets-table" {
  name           = "Tweets"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "tweet_id"

  attribute {
    name = "tweet_id"
    type = "S"
  }

  ttl {
    attribute_name = "TimeToExist"
    enabled = false
  }
}

// Tweets sentiment table
resource "aws_dynamodb_table" "twitter_sentiment_lang" {
  name           = "twitter_sentiment"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "tweet_id"

  attribute {
    name = "tweet_id"
    type = "S"
  }

  ttl {
    attribute_name = "TimeToExist"
    enabled = false
  }
}

data "archive_file" "kinesis_tweet_dynamo_lambda" {
  type = "zip"
  source_dir = "./lambdas/kinesis_tweet_dynamo_lambda"
  output_path = "./lambdas/kinesis_tweet_dynamo_lambda/kinesis_tweet_dynamo_lambda.zip"
}

data "archive_file" "tweets_lang_lambda" {
  type = "zip"
  source_dir = "./lambdas/tweets_lang_lambda"
  output_path = "./lambdas/tweets_lang_lambda/tweets_lang_lambda.zip"
}

// Lamdba for processing tweets and pushing them to dynamo
resource "aws_lambda_function" "kinesis_tweet_dynamo_lambda" {
  filename = "${data.archive_file.kinesis_tweet_dynamo_lambda.output_path}"
  function_name = "kinesis_tweet_dynamo_lambda"
  handler = "kinesis_tweet_dynamo_lambda.handler"
  description = "Lambda which takes tweets from Kinesis and stores them in Dynamo"
  role = "${aws_iam_role.kinesis_lambda_dynamo_role.arn}"
  runtime = "nodejs6.10"
  timeout = 300
  source_code_hash = "${base64sha256(file("${data.archive_file.kinesis_tweet_dynamo_lambda.output_path}"))}"

  environment {
    variables = {
      TABLE_NAME = "Tweets"
    }
  }
}

// Lambda for sentiment analysis
resource "aws_lambda_function" "tweets_lang_lambda" {
  filename = "${data.archive_file.tweets_lang_lambda.output_path}"
  function_name = "tweets_lang_lambda"
  handler = "tweets_lang_lambda.handler"
  description = "Lambda which takes tweets and does language analysis"
  role = "${aws_iam_role.kinesis_lambda_dynamo_role.arn}"
  runtime = "python2.7"
  timeout = 300
  source_code_hash = "${base64sha256(file("${data.archive_file.tweets_lang_lambda.output_path}"))}"
}

resource "aws_lambda_event_source_mapping" "lang_event_source_mapping" {
  batch_size        = 100
  event_source_arn  = "${aws_kinesis_stream.tweet_stream.arn}"
  enabled           = true
  function_name     = "${aws_lambda_function.tweets_lang_lambda.arn}"
  starting_position = "TRIM_HORIZON"
}

resource "aws_lambda_event_source_mapping" "event_source_mapping" {
  batch_size        = 100
  event_source_arn  = "${aws_kinesis_stream.tweet_stream.arn}"
  enabled           = true
  function_name     = "${aws_lambda_function.kinesis_tweet_dynamo_lambda.arn}"
  starting_position = "TRIM_HORIZON"
}

