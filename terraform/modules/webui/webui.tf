variable "MinecraftWebUIBucketName" {
  type        = string
  description = "The name of the S3 bucket to host the web UI static files. This bucket will be created if it does not already exist. If the bucket already exists, it must be empty and owned by the same AWS account."
}

variable "MinecraftWebUIBuildDir" {
  type        = string
  description = "The directory containing the built web UI files to be uploaded to the S3 bucket."
}

variable "WebUIAllowedRegions" {
  type        = list(string)
  description = "A list of country codes to allow access to the web UI. This is used to configure the geo restriction settings for the CloudFront distribution. For a list of country codes, see: https://en.wikipedia.org/wiki/ISO_3166-1"
  default     = ["US", "CA"]
}

# Create an S3 bucket to host the web UI
resource "aws_s3_bucket" "webui_bucket" {
  bucket = var.MinecraftWebUIBucketName

  tags = {
    Name = "AWSCraft Web UI Bucket"
  }
}

# Create a policy to allow cloudfront access to S3
data "aws_iam_policy_document" "origin_bucket_policy" {
  statement {
    sid    = "AllowCloudFrontServicePrincipalReadWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${aws_s3_bucket.webui_bucket.arn}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.s3_distribution.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "MinecraftWebUIBucketPolicy" {
  bucket = aws_s3_bucket.webui_bucket.id
  policy = data.aws_iam_policy_document.origin_bucket_policy.json
}

resource "aws_cloudfront_origin_access_control" "MinecraftWebUIOriginAccess" {
  name = "AWSCraftWebUIOriginAccessControl"

  signing_behavior = "always"
  signing_protocol = "sigv4"

  origin_access_control_origin_type = "s3"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket.webui_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.MinecraftWebUIOriginAccess.id
    origin_id                = aws_s3_bucket.webui_bucket.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Enable CloudFront distribution for the Minecraft Web UI"
  default_root_object = "index.html"

  # Add aliases for custom domains 
  aliases = []

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.webui_bucket.id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    # Do not cache index.html and other dynamic entries
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  # Cache behavior for Next.js immutable static assets
  ordered_cache_behavior {
    path_pattern     = "/_next/static/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = aws_s3_bucket.webui_bucket.id

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = var.WebUIAllowedRegions
    }
  }

  tags = {
    Environment = "production"
    Name        = "Minecraft Web UI Distro"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    ssl_support_method             = "sni-only"
  }
}

# Upload the web UI static files to the S3 bucket
resource "aws_s3_object" "webui_files" {
  for_each = fileset(var.MinecraftWebUIBuildDir, "**")

  bucket = aws_s3_bucket.webui_bucket.id
  key    = each.value
  source = "${var.MinecraftWebUIBuildDir}/${each.value}"

  # Set the content type explicitly
  content_type = try(
    {
      "html" = "text/html",
      "css"  = "text/css",
      "js"   = "application/javascript",
      "json" = "application/json",
      "png"  = "image/png",
      "jpg"  = "image/jpeg",
      "svg"  = "image/svg+xml"
    }[split(".", each.value)[length(split(".", each.value)) - 1]],
    "application/octet-stream"
  )
}
