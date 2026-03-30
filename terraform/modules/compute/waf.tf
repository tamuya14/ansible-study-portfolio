# WAF Web ACL の定義
resource "aws_wafv2_web_acl" "main" {
  name        = "wordpress-waf-${var.env_name}"
  description = "WAF for WordPress ALB"
  scope       = "REGIONAL" # ALBの場合は REGIONAL、CloudFrontの場合は CLOUDFRONT

  default_action {
    allow {} # 基本は通して、ルールに合致したものだけブロック
  }

  # AWS マネージドルール：共通攻撃セット（SQLi, XSS等）
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "wordpress-waf-main-metric"
    sampled_requests_enabled   = true
  }
}

# ALB と WAF の紐付け
resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = aws_lb.web.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}